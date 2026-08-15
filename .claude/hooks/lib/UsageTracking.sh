#!/usr/bin/env bash
#
# post-push-usage-report.sh（PostToolUse, git push検知）が使う共有ロジック（bash版）。
# 設計: dev-tools/docs/spec/issue-mr-workflow.md, dev-tools/docs/spec/shell-scripts.md
#
# 単体でsourceせず、`source "$(dirname "${BASH_SOURCE[0]}")/lib/UsageTracking.sh"` の形でsourceして
# 使う。
#
# 注意: transcript_path が指すJSONLの形式はClaude Code非公開の内部フォーマットであり、
# 将来のバージョンで変更されうる（公式ドキュメントに明記）。他に取得手段が無いためベストエフォートで
# パースする。呼び出し元（post-push-usage-report.sh）側で失敗を検知して握りつぶす想定で、本ファイル内
# では集計ロジックの失敗（`set -e`によるエラー）をそのまま呼び出し元へ伝播させる。
#
# 注意: 各assistantメッセージには実行時のgitBranchが記録されている（実機確認済み）。これで
# フィルタしない場合、同一セッション内で複数ブランチを跨いだ際に他ブランチ分のトークンが
# 混入するため、必ず `.gitBranch == $branch` で絞り込む。
#
# 注意（PowerShell版との差分）: PowerShell版が持っていた ConvertTo-HashtableDeep は、
# Windows PowerShell 5.1 の `ConvertFrom-Json` が `-AsHashtable` を持たないための回避策であり、
# jqにはその制約が無いためbash版には存在しない（詳細: dev-tools/docs/spec/shell-scripts.md）。

# transcript(JSONL)を集計し、{tokens, tools, assistantCount} のJSONをstdoutへ出力する。
# 空行・不正なJSON行は無視する（ベストエフォート）。指定ブランチ以外のassistantエントリは除外する。
_usage_aggregate_transcript() {
  local transcript_path="$1" branch="$2"
  jq -R -n --arg branch "$branch" '
    def zero_bucket: {input: 0, output: 0, cacheCreate: 0, cacheRead: 0};
    reduce (
      inputs
      | select(length > 0)
      | (try fromjson catch empty)
      | select(.type == "assistant" and .message != null and ((.gitBranch // "") == $branch))
    ) as $entry (
      {tokens: {}, tools: {}, assistantCount: 0};
      .assistantCount += 1
      | (if $entry.message.usage then
          ($entry.message.model // "unknown") as $model
          | .tokens[$model] = ((.tokens[$model] // zero_bucket)
              | .input += ($entry.message.usage.input_tokens // 0)
              | .output += ($entry.message.usage.output_tokens // 0)
              | .cacheCreate += ($entry.message.usage.cache_creation_input_tokens // 0)
              | .cacheRead += ($entry.message.usage.cache_read_input_tokens // 0))
        else . end)
      | (reduce (($entry.message.content // [])[] | select(.type == "tool_use" and .name != null)) as $block (
          .; .tools[$block.name] = ((.tools[$block.name] // 0) + 1)
        ))
    )
  ' "$transcript_path"
}

# 状態ファイル(既存JSON)・今回の集計(current)・セッションIDを突き合わせ、
# 「前回このセッションで記録した累計との差分」をsinceLastPushへ加算した新しい状態JSONを返す。
_usage_merge_state() {
  local existing="$1" current="$2" session_id="$3" branch="$4"
  local jq_program
  jq_program="$(cat <<'JQ'
def zero_bucket: {input: 0, output: 0, cacheCreate: 0, cacheRead: 0};

($existing.sessions // {}) as $sessions
| ($sessions[$sessionId] // {lastTokens: {}, lastTools: {}, lastAssistantCount: 0}) as $prevSession
| ($prevSession.lastTokens // {}) as $prevTokens
| ($prevSession.lastTools // {}) as $prevTools
| (($prevSession.lastAssistantCount // 0) | tonumber) as $prevAssistantCount
| ($existing.sinceLastPush // {tokensByModel: {}, toolCalls: {}, turns: 0}) as $sincePrev
| (reduce ($current.tokens | keys[]) as $model (
    $sincePrev;
    ($current.tokens[$model]) as $cur
    | ($prevTokens[$model] // zero_bucket) as $prev
    | (.tokensByModel[$model] // zero_bucket) as $acc
    | .tokensByModel[$model] = {
        input: ($acc.input + ([0, ($cur.input - $prev.input)] | max)),
        output: ($acc.output + ([0, ($cur.output - $prev.output)] | max)),
        cacheCreate: ($acc.cacheCreate + ([0, ($cur.cacheCreate - $prev.cacheCreate)] | max)),
        cacheRead: ($acc.cacheRead + ([0, ($cur.cacheRead - $prev.cacheRead)] | max))
      }
  )) as $sinceTokens
| (reduce ($current.tools | keys[]) as $tool (
    $sinceTokens;
    ($current.tools[$tool]) as $cur
    | ($prevTools[$tool] // 0) as $prev
    | (.toolCalls[$tool] // 0) as $acc
    | .toolCalls[$tool] = ($acc + ([0, ($cur - $prev)] | max))
  )) as $sinceAfterTools
| ($sinceAfterTools.turns // 0) as $turnsAcc
| ([0, ($current.assistantCount - $prevAssistantCount)] | max) as $turnsDelta
| ($sinceAfterTools | .turns = ($turnsAcc + $turnsDelta)) as $newSince
| ($existing.sessions // {}) as $existingSessions
| ($existingSessions + {($sessionId): {lastTokens: $current.tokens, lastTools: $current.tools, lastAssistantCount: $current.assistantCount}}) as $newSessions
| {branch: $branch, sessions: $newSessions, sinceLastPush: $newSince}
  + (if $existing.lastPostedAt then {lastPostedAt: $existing.lastPostedAt} else {} end)
JQ
)"
  jq -n --argjson existing "$existing" --argjson current "$current" \
    --arg sessionId "$session_id" --arg branch "$branch" \
    "$jq_program"
}

# 指定ブランチ・セッションのtranscriptを集計し、状態ファイル（.claude/usage-state/<branch>.json）の
# sinceLastPush へ「前回このセッションで記録した累計との差分」を加算して保存する。更新後の状態JSONを
# stdoutへ出力する。呼び出し元は post-push-usage-report.sh（PostToolUse, git push検知）。
# transcript_pathが存在しない場合は何も出力せず終了コード1を返す。
sync_usage_state() {
  local repo_root="$1" branch="$2" session_id="$3" transcript_path="$4"

  if [ ! -f "$transcript_path" ]; then
    return 1
  fi

  local current
  current="$(_usage_aggregate_transcript "$transcript_path" "$branch")"

  local state_dir="${repo_root}/.claude/usage-state"
  mkdir -p "$state_dir"
  local safe_branch
  safe_branch="$(printf '%s' "$branch" | sed -E 's/[^a-zA-Z0-9_-]/_/g')"
  local state_file="${state_dir}/${safe_branch}.json"

  local existing="{}"
  if [ -f "$state_file" ]; then
    existing="$(cat "$state_file")"
  fi

  local new_state
  new_state="$(_usage_merge_state "$existing" "$current" "$session_id" "$branch")"

  printf '%s' "$new_state" > "$state_file"
  printf '%s' "$new_state"
}
