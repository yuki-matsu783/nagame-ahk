#!/usr/bin/env bash
#
# post-push-usage-report.sh（PostToolUse, git push検知）が使う共有ロジック（bash版）。
# 設計: plans/inherited-gathering-biscuit.md（issue #37）,
#       dev-tools/docs/spec/issue-mr-workflow.md, dev-tools/docs/spec/shell-scripts.md
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
# 注意（tools/tokens/turns/skillCalls/agentCalls/askUserQuestionsの集計方式、issue #37）:
# 同一セッションが複数回・複数ブランチにわたってresumeされると、transcript JSONL上に同一行が
# 複数回（異なるgitBranchラベル付きで）出現することが実データで確認された。「毎回全件を再パースし、
# 前回の累計との差分（引き算）を計上する」という以前の方式では、セッションが新しいブランチで
# 初めてpushされた際に前回スナップショットが存在せず、蓄積済みの全件がその新ブランチの初回差分と
# して計上されてしまう不具合があった。
# 対策として、これらのフィールドは「セッション単位でグローバルなカーソル
# （usage/state/session-cursors/<sessionId>.json の lastLineCount）が指す、前回処理済み行数
# 以降の新規行のみ」を対象に集計する方式へ変更した（_usage_read_new_lines /
# _usage_aggregate_new_lines）。この方式は行の中身（重複かどうか・どのgitBranchラベルが「正しい」か）
# を一切詮索せず、「一度数えた範囲は二度と数え直さない」という機械的な原則だけで問題を回避する。
# 集計結果はそのまま「新規分（差分）」であるため、_usage_merge_state 側での引き算は不要で、
# sinceLastPush へ単純加算・追記するだけでよい。
#
# 注意（activeSecondsだけは全件再パース方式を維持する理由）: 稼働時間(activeSeconds)のgapベースの
# 区間計算は「毎回全件を時系列で走査し直す」ことを前提に単調非減少性を保証する設計になっており
# （後述のコメント参照）、新規行だけの断片的な走査では前回pushの「暫定クローズした末尾セグメント」を
# 正しく補正できない。そのため activeSeconds の算出だけは _usage_aggregate_transcript
# （全件再パース＋sessions[sessionId].lastActiveSeconds とのスナップショット差分）を維持する。
#
# 注意（PowerShell版との差分）: PowerShell版が持っていた ConvertTo-HashtableDeep は、
# Windows PowerShell 5.1 の `ConvertFrom-Json` が `-AsHashtable` を持たないための回避策であり、
# jqにはその制約が無いためbash版には存在しない（詳細: dev-tools/docs/shell-scripts.md）。

# 稼働時間（activeSeconds）算出用の閾値（秒）。連続するtranscript entry間の経過時間がこれ以上の
# 場合は「人間の入力待ち」（AskUserQuestionの回答待ち・応答終了後の次指示待ち等）とみなし、
# その区間（gapそのもの）は稼働時間に加算しない（ちょうど閾値と同じgapも「待ち」側として扱う）。
# 閾値未満のgapはツール実行待ち等の実作業とみなしそのまま加算する。
# `:=` を使い、呼び出し側（テスト等）が事前に設定していればそちらを優先する。
: "${IDLE_GAP_THRESHOLD_SECONDS:=300}"

# 稼働時間の区間（セグメント）が閉じるたびに末尾へ加算する固定秒数。応答を読む・確認する等、
# 次のgapとしては現れない実作業時間を補うためのもの。
: "${TAIL_BUFFER_SECONDS:=30}"

# ブランチ名を状態ファイル名・ディレクトリ名に使える形へサニタイズする（英数字・ハイフン・
# アンダースコア以外を`_`へ置換）。
_usage_safe_branch_name() {
  printf '%s' "$1" | sed -E 's/[^a-zA-Z0-9_-]/_/g'
}

# transcript(JSONL)を全件再パースし、{tokens, tools, assistantCount, activeSeconds} のJSONを
# stdoutへ出力する。空行・不正なJSON行は無視する（ベストエフォート）。指定ブランチ以外の
# assistantエントリは除外する。
#
# 注意（issue #37以降の使いどころ）: 本関数はもはやtools/tokens/assistantCountの差分計算には
# 使われない（新規行diff方式へ移行したため）。activeSeconds算出専用として維持している
# （呼び出し元は戻り値のうち .activeSeconds のみを使う）。
#
# activeSeconds: 集計対象entry（gitBranch一致・assistant）を出現順（transcriptは時系列で
# 書き出される前提）に走査し、直前entryとの`.timestamp`差（gap）が IDLE_GAP_THRESHOLD_SECONDS
# 未満ならその区間分を、以上ならセグメント終端として TAIL_BUFFER_SECONDS を積算する「累計稼働秒数」。
# 最初のentryには比較対象が無いため加算しない。タイムスタンプが逆行する（負のgap）場合は異常値として
# 何も加算しない。走査完了後、集計対象entryが1件以上あれば、末尾の（まだ閉じていない）セグメントを
# 閉じる分として TAIL_BUFFER_SECONDS をもう1回加算する（entryが1件のみのセッションでも
# activeSecondsが0にならない）。
#
# 単調性メモ: 上記「末尾セグメントの暫定クローズ」は、次回pushで同じセッションのtranscriptが
# 伸びて再集計されると「実際のgap＋新しい末尾へのtail buffer」に置き換わる。置き換え後の値は常に
# 元の値以上になる（新しく追加された時間の分だけ増える）ため、activeSecondsは再集計を繰り返しても
# 単調非減少であり続ける。これにより呼び出し元（_usage_merge_state）の
# 「current - prevSession値（下限0）」という累計差分パターンがそのまま安全に使える。
#
# 注意（`fromdateiso8601`を使わない理由）: 開発機のjq（Windowsネイティブ版jq 1.6）は
# `strptime`/`mktime`が未実装のため、`days_from_civil`アルゴリズムによる自前のISO8601→epoch秒変換を
# 実装する（詳細: .claude/rules/shell-script-style.md「JSON操作」節）。
_usage_aggregate_transcript() {
  local transcript_path="$1" branch="$2"
  jq -R -n --arg branch "$branch" \
    --argjson idleThreshold "$IDLE_GAP_THRESHOLD_SECONDS" \
    --argjson tailBuffer "$TAIL_BUFFER_SECONDS" '
    def zero_bucket: {input: 0, output: 0, cacheCreate: 0, cacheRead: 0};
    # グレゴリオ暦の年月日→エポック日数（1970-01-01を0とする）。strptime/mktimeに依存しない。
    def days_from_civil($y; $m; $d):
      (if $m <= 2 then $y - 1 else $y end) as $yAdj
      | ($yAdj / 400 | floor) as $era
      | ($yAdj - $era * 400) as $yoe
      | ((153 * ($m + (if $m > 2 then -3 else 9 end)) + 2) / 5 | floor) as $doy
      | ($yoe * 365 + ($yoe / 4 | floor) - ($yoe / 100 | floor) + $doy + $d - 1) as $doe
      | ($era * 146097 + $doe - 719468);
    # "YYYY-MM-DDTHH:MM:SS" で始まる文字列（末尾のミリ秒・Zは無視）をUTCエポック秒へ変換する。
    def epoch_from_iso8601:
      . as $s
      | ($s[0:4]   | tonumber) as $Y
      | ($s[5:7]   | tonumber) as $Mo
      | ($s[8:10]  | tonumber) as $D
      | ($s[11:13] | tonumber) as $H
      | ($s[14:16] | tonumber) as $Mi
      | ($s[17:19] | tonumber) as $S
      | (days_from_civil($Y; $Mo; $D) * 86400 + $H * 3600 + $Mi * 60 + $S);
    reduce (
      inputs
      | select(length > 0)
      | (try fromjson catch empty)
      | select(.type == "assistant" and .message != null and ((.gitBranch // "") == $branch))
    ) as $entry (
      {tokens: {}, tools: {}, assistantCount: 0, activeSeconds: 0, prevTimestamp: null};
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
      | (if ($entry.timestamp != null) then
          ($entry.timestamp | epoch_from_iso8601) as $ts
          | (if .prevTimestamp != null then
              (($ts - .prevTimestamp) as $gap
               | if $gap < 0 then
                   .
                 elif $gap < $idleThreshold then
                   .activeSeconds += $gap
                 else
                   .activeSeconds += $tailBuffer
                 end)
            else . end)
          | .prevTimestamp = $ts
        else . end)
    )
    | (if .assistantCount > 0 then .activeSeconds += $tailBuffer else . end)
    | del(.prevTimestamp)
  ' "$transcript_path"
}

# transcript(JSONL)から、空行を除いた行数（totalLines）と、前回カーソル位置（last_line_count）
# 以降の新規行のみをパース済みJSONオブジェクトとして返す（newEntries。不正なJSON行は無視する）。
# {totalLines, newEntries} をstdoutへ出力する。
#
# 行の位置基準は _usage_aggregate_transcript の `select(length > 0)` と同じ「空行を除いた行数」で
# 揃えている（カーソルの整合性を保つため）。
_usage_read_new_lines() {
  local transcript_path="$1" last_line_count="$2"
  jq -R -n --argjson offset "$last_line_count" '
    [inputs | select(length > 0)] as $rawLines
    | {
        totalLines: ($rawLines | length),
        newEntries: ($rawLines[$offset:] | map(try fromjson catch empty) | map(select(. != null)))
      }
  ' "$transcript_path"
}

# _usage_read_new_lines が返した新規行（newEntries）のみを対象に、tokens/tools/assistantCount
# （turns）と、skillCalls/agentCalls/askUserQuestions（対応工数レポートの詳細テーブル用、issue #37）
# を集計する。指定ブランチ以外のエントリは除外する。戻り値はそのまま「前回pushからの新規分（差分）」
# であり、呼び出し元は引き算せずsinceLastPushへ加算・追記すればよい。
#
# skillCalls: `Skill` tool_useブロックから {id, skill, args} を抽出する。
# agentCalls: `Agent` tool_useブロックから {id, subagentType, description, prompt} を抽出する
#   （メインセッションのtranscriptのみを対象とする想定。ネストしたサブエージェント・
#   サブエージェント自身が呼んだAgent/Skillは対象外＝plan「対象外」節参照）。
# askUserQuestions: `.type=="user"`エントリのtool_result本文（"Your questions have been
#   answered: \"Q\"=\"A\", ... "形式。実データで確認済み）から質問=回答ペアを正規表現で抽出する。
#   質問・回答の文字列自体に `"..."="..."` と一致するパターンが含まれる場合は誤抽出しうる
#   既知の制約（レアケースとして許容する）。
_usage_aggregate_new_lines() {
  local new_entries="$1" branch="$2"
  jq -n --argjson entries "$new_entries" --arg branch "$branch" '
    def zero_bucket: {input: 0, output: 0, cacheCreate: 0, cacheRead: 0};
    ($entries | map(select(.message != null and ((.gitBranch // "") == $branch)))) as $filtered
    | ($filtered | map(select(.type == "assistant"))) as $assistantEntries
    | ($filtered | map(select(.type == "user"))) as $userEntries
    | (reduce $assistantEntries[] as $entry (
        {tokens: {}, tools: {}, assistantCount: 0, skillCalls: [], agentCalls: []};
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
            .;
            .tools[$block.name] = ((.tools[$block.name] // 0) + 1)
            | if $block.name == "Skill" then
                .skillCalls += [{id: $block.id, skill: ($block.input.skill // null), args: ($block.input.args // null)}]
              elif $block.name == "Agent" then
                .agentCalls += [{id: $block.id, subagentType: ($block.input.subagent_type // null),
                  description: ($block.input.description // null), prompt: ($block.input.prompt // null)}]
              else . end
          ))
      )) as $assistantAgg
    | (reduce $userEntries[] as $entry (
        {askUserQuestions: []};
        (reduce (($entry.message.content // [])[] | select(.type == "tool_result")) as $block (
            .;
            ($block.content
              | if type == "string" then .
                elif type == "array" then ([.[] | .text? // ""] | join(""))
                else "" end) as $text
            | if ($text | test("Your questions have been answered:")) then
                reduce ($text | scan("\"([^\"]*)\"=\"([^\"]*)\"")) as $pair (
                  .;
                  (.askUserQuestions | length) as $idx
                  | .askUserQuestions += [{id: (($entry.uuid // "noid") + "#" + ($idx | tostring)),
                      question: $pair[0], answer: $pair[1]}]
                )
              else . end
          ))
      )) as $userAgg
    | $assistantAgg + $userAgg
  '
}

# 状態ファイル(既存JSON)・今回の新規分（delta。_usage_aggregate_new_linesの戻り値）・
# activeSecondsの累計値（_usage_aggregate_transcriptの戻り値の.activeSeconds）・セッションIDを
# 突き合わせ、更新後の状態JSONを返す。
#
# tokens/tools/turns（assistantCount）/skillCalls/agentCalls/askUserQuestions は既に「新規分」
# として渡されるため、sinceLastPushへそのまま加算・追記する（引き算は不要。issue #37対応）。
# activeSecondsだけは従来通り「累計値 - 前回スナップショット」という差分計算を行う
# （_usage_aggregate_transcriptがactiveSeconds専用に全件再パースする設計のため。ファイル冒頭の
# コメント参照）。
#
# 注意（`agents`のpassthrough）: `$existing.agents`（サブエージェントのagentId単位累計
# スナップショット。`_usage_merge_agent_state`が読み書きする）は本関数が管理するフィールドでは
# ないが、出力オブジェクトへそのまま引き継ぐ。
_usage_merge_state() {
  local existing="$1" delta="$2" active_seconds="$3" session_id="$4" branch="$5"
  local jq_program
  jq_program="$(cat <<'JQ'
def zero_bucket: {input: 0, output: 0, cacheCreate: 0, cacheRead: 0};

($existing.sessions // {}) as $sessions
| ($sessions[$sessionId] // {lastActiveSeconds: 0}) as $prevSession
| (($prevSession.lastActiveSeconds // 0) | tonumber) as $prevActiveSeconds
| ($existing.sinceLastPush // {tokensByModel: {}, toolCalls: {}, turns: 0, activeSeconds: 0,
    skillCalls: [], agentCalls: [], askUserQuestions: []}) as $sincePrev
| (reduce (($delta.tokens // {}) | keys[]) as $model (
    $sincePrev;
    ($delta.tokens[$model]) as $d
    | (.tokensByModel[$model] // zero_bucket) as $acc
    | .tokensByModel[$model] = {
        input: ($acc.input + ($d.input // 0)),
        output: ($acc.output + ($d.output // 0)),
        cacheCreate: ($acc.cacheCreate + ($d.cacheCreate // 0)),
        cacheRead: ($acc.cacheRead + ($d.cacheRead // 0))
      }
  )) as $sinceTokens
| (reduce (($delta.tools // {}) | keys[]) as $tool (
    $sinceTokens;
    .toolCalls[$tool] = ((.toolCalls[$tool] // 0) + $delta.tools[$tool])
  )) as $sinceTools
| ($sinceTools
    | .turns = ((.turns // 0) + ($delta.assistantCount // 0))
    | .activeSeconds = ((.activeSeconds // 0) + ([0, ($activeSeconds - $prevActiveSeconds)] | max))
    | .skillCalls = ((.skillCalls // []) + ($delta.skillCalls // []))
    | .agentCalls = ((.agentCalls // []) + ($delta.agentCalls // []))
    | .askUserQuestions = ((.askUserQuestions // []) + ($delta.askUserQuestions // []))
  ) as $newSince
| ($existing.sessions // {}) as $existingSessions
| ($existingSessions + {($sessionId): {lastActiveSeconds: $activeSeconds}}) as $newSessions
| {branch: $branch, sessions: $newSessions, sinceLastPush: $newSince}
  + (if $existing.lastPostedAt then {lastPostedAt: $existing.lastPostedAt} else {} end)
  + (if $existing.agents then {agents: $existing.agents} else {} end)
JQ
)"
  jq -n --argjson existing "$existing" --argjson delta "$delta" --argjson activeSeconds "$active_seconds" \
    --arg sessionId "$session_id" --arg branch "$branch" \
    "$jq_program"
}

# git push検知時に、集計対象のtranscript（メイン＋サブエージェント）をリポジトリ内の
# gitignore対象ディレクトリ（usage/session-logs/<safeBranch>/<sessionId>/）へコピーする
# （非公開・ユーザープロファイル配下の揮発性のあるパスに集計処理が直接依存し続けるのを避け、
# pushのたびにリポジトリ内へスナップショットを退避する）。
# コピー先ディレクトリパスをstdoutへ返す。
#
# サブエージェントの発見: `${transcript_path%.jsonl}/subagents/agent-*.jsonl` のみを対象とする
# （直接の子、spawnDepth 1相当）。
_usage_sync_session_logs() {
  local repo_root="$1" branch="$2" session_id="$3" transcript_path="$4"

  local safe_branch
  safe_branch="$(_usage_safe_branch_name "$branch")"
  local log_dir="${repo_root}/usage/session-logs/${safe_branch}/${session_id}"
  mkdir -p "${log_dir}/subagents"
  cp "$transcript_path" "${log_dir}/main.jsonl"

  local session_dir="${transcript_path%.jsonl}"
  if [ -d "${session_dir}/subagents" ]; then
    local f meta
    for f in "${session_dir}/subagents"/agent-*.jsonl; do
      [ -e "$f" ] || continue
      cp "$f" "${log_dir}/subagents/" 2>/dev/null || true
      meta="${f%.jsonl}.meta.json"
      if [ -f "$meta" ]; then
        cp "$meta" "${log_dir}/subagents/" 2>/dev/null || true
      fi
    done
  fi

  printf '%s' "$log_dir"
}

# セッション横断（ブランチをまたいでも共有）のカーソルファイル
# （usage/state/session-cursors/<cursorKey>.json）から lastLineCount を読む。無ければ0を返す。
_usage_read_cursor() {
  local repo_root="$1" cursor_key="$2"
  local cursor_file="${repo_root}/usage/state/session-cursors/${cursor_key}.json"
  if [ -f "$cursor_file" ]; then
    jq -r '.lastLineCount // 0' "$cursor_file"
  else
    printf '0'
  fi
}

# カーソルファイルへ lastLineCount を書き込む。
_usage_write_cursor() {
  local repo_root="$1" cursor_key="$2" total_lines="$3"
  local cursor_dir="${repo_root}/usage/state/session-cursors"
  mkdir -p "$cursor_dir"
  jq -n --argjson n "$total_lines" '{lastLineCount: $n}' > "${cursor_dir}/${cursor_key}.json"
}

# 1つのサブエージェント（agentId単位）について、_usage_merge_state と全く同じ
# 「delta加算＋activeSecondsのみ差分」ロジックを適用する。累計スナップショット・sinceLastPush差分の
# いずれもagentId単位で保持する。レポート表示はagentIdごとに1行とする方針のため、agentType単位での
# 合算は行わない（issue #34）。`agentType`・`description`はスナップショット・sinceLastPushの
# 両方に付与して保存する。
#
# _usage_merge_state 本体は無改造のまま、agentId を「疑似session_id」、agentId別の累計を
# 「疑似sinceLastPush」としてラップして渡すことで、既存の差分計算ロジックをそのまま再利用する。
_usage_merge_agent_state() {
  local existing="$1" agent_id="$2" agent_type="$3" description="$4" delta="$5" active_seconds="$6" branch="$7"

  local pseudo_existing
  pseudo_existing="$(printf '%s' "$existing" | jq -c --arg agentId "$agent_id" '
    {
      sessions: {($agentId): (.agents[$agentId] // {})},
      sinceLastPush: (.sinceLastPush.subagents[$agentId]
        // {tokensByModel: {}, toolCalls: {}, turns: 0, activeSeconds: 0,
            skillCalls: [], agentCalls: [], askUserQuestions: []})
    }
  ')"

  local merged
  merged="$(_usage_merge_state "$pseudo_existing" "$delta" "$active_seconds" "$agent_id" "$branch")"

  jq -n --argjson existing "$existing" --argjson merged "$merged" \
    --arg agentId "$agent_id" --arg agentType "$agent_type" --arg description "$description" '
    $existing
    | .agents[$agentId] = ($merged.sessions[$agentId] + {agentType: $agentType, description: $description})
    | .sinceLastPush.subagents[$agentId] = ($merged.sinceLastPush + {agentType: $agentType, description: $description})
  '
}

# コピー済みディレクトリ（_usage_sync_session_logsの戻り値）配下のサブエージェントtranscriptを
# 列挙し、agentId単位のセッションカーソル（usage/state/session-cursors/<agentId>.json）を使って
# 新規行のみを集計→_usage_merge_agent_state で existing へ畳み込む。新規行が無いagentはスキップする。
# サブエージェントが1件も無ければexistingをそのまま返す。
_usage_aggregate_and_merge_subagents() {
  local existing="$1" log_dir="$2" branch="$3" repo_root="$4"
  local subagents_dir="${log_dir}/subagents"

  if [ ! -d "$subagents_dir" ]; then
    printf '%s' "$existing"
    return 0
  fi

  local f
  for f in "$subagents_dir"/agent-*.jsonl; do
    [ -e "$f" ] || continue
    local agent_id agent_type description meta_file
    agent_id="$(basename "$f" .jsonl)"
    agent_id="${agent_id#agent-}"
    meta_file="${f%.jsonl}.meta.json"
    if [ -f "$meta_file" ]; then
      agent_type="$(jq -r '.agentType // "unknown"' "$meta_file" 2>/dev/null || echo "unknown")"
      description="$(jq -r '.description // ""' "$meta_file" 2>/dev/null || echo "")"
    else
      agent_type="unknown"
      description=""
    fi
    [ -n "$agent_type" ] || agent_type="unknown"

    local last_line_count
    last_line_count="$(_usage_read_cursor "$repo_root" "$agent_id")"

    local read_result total_lines
    read_result="$(_usage_read_new_lines "$f" "$last_line_count")"
    total_lines="$(printf '%s' "$read_result" | jq -r '.totalLines')"

    if [ "$total_lines" -le "$last_line_count" ]; then
      continue
    fi

    local new_entries delta active_seconds
    new_entries="$(printf '%s' "$read_result" | jq -c '.newEntries')"
    delta="$(_usage_aggregate_new_lines "$new_entries" "$branch")"
    active_seconds="$(_usage_aggregate_transcript "$f" "$branch" | jq -r '.activeSeconds')"

    existing="$(_usage_merge_agent_state "$existing" "$agent_id" "$agent_type" "$description" "$delta" "$active_seconds" "$branch")"

    _usage_write_cursor "$repo_root" "$agent_id" "$total_lines"
  done

  printf '%s' "$existing"
}

# 指定ブランチ・セッションのtranscriptを集計し、状態ファイル（usage/state/<branch>.json）の
# sinceLastPush へ「前回pushからの新規分」を加算して保存する。更新後の状態JSONをstdoutへ出力する。
# 呼び出し元は post-push-usage-report.sh（PostToolUse, git push検知）。
# transcript_pathが存在しない場合は何も出力せず終了コード1を返す。
#
# セッション横断のカーソル（usage/state/session-cursors/<sessionId>.json）を見て、前回処理済み
# 行数以降に新規行が無ければ、session-logsへのコピー・状態更新をスキップし既存状態をそのまま返す
# （issue #37「差分がなければコピーしない」対応）。新規行があれば、既存同様
# usage/session-logs/ へメイン・サブエージェント両方のtranscriptをコピーし、新規行の集計
# （tools/tokens/turns/詳細3種）とactiveSecondsの全件再パースをそれぞれ行う。
sync_usage_state() {
  local repo_root="$1" branch="$2" session_id="$3" transcript_path="$4"

  if [ ! -f "$transcript_path" ]; then
    return 1
  fi

  local state_dir="${repo_root}/usage/state"
  local safe_branch state_file
  safe_branch="$(_usage_safe_branch_name "$branch")"
  state_file="${state_dir}/${safe_branch}.json"

  local last_line_count
  last_line_count="$(_usage_read_cursor "$repo_root" "$session_id")"

  local read_result total_lines
  read_result="$(_usage_read_new_lines "$transcript_path" "$last_line_count")"
  total_lines="$(printf '%s' "$read_result" | jq -r '.totalLines')"

  if [ "$total_lines" -le "$last_line_count" ]; then
    # 新規行が無い: session-logsへのコピー・状態更新をスキップし、既存状態をそのまま返す
    if [ -f "$state_file" ]; then
      cat "$state_file"
    fi
    return 0
  fi

  local log_dir
  log_dir="$(_usage_sync_session_logs "$repo_root" "$branch" "$session_id" "$transcript_path")"

  local new_entries delta active_seconds
  new_entries="$(printf '%s' "$read_result" | jq -c '.newEntries')"
  delta="$(_usage_aggregate_new_lines "$new_entries" "$branch")"
  active_seconds="$(_usage_aggregate_transcript "${log_dir}/main.jsonl" "$branch" | jq -r '.activeSeconds')"

  mkdir -p "$state_dir"
  local existing="{}"
  if [ -f "$state_file" ]; then
    existing="$(cat "$state_file")"
  fi

  local new_state
  new_state="$(_usage_merge_state "$existing" "$delta" "$active_seconds" "$session_id" "$branch")"
  new_state="$(_usage_aggregate_and_merge_subagents "$new_state" "$log_dir" "$branch" "$repo_root")"

  printf '%s' "$new_state" > "$state_file"
  printf '%s' "$new_state"

  _usage_write_cursor "$repo_root" "$session_id" "$total_lines"
}

# post-push-usage-report.sh がMRへの投稿成功後に呼ぶ、sinceLastPushのゼロ初期化。
# 状態JSON全体（state）を受け取り、sinceLastPushをゼロ初期化・lastPostedAtを現在時刻に更新した
# 新しい状態JSONをstdoutへ返す（呼び出し元がstate_fileへ書き戻す）。他のフィールド（sessions,
# agents等）はそのまま保持する。
_usage_reset_since_last_push() {
  local state="$1"
  printf '%s' "$state" | jq \
    --arg postedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.sinceLastPush = {tokensByModel: {}, toolCalls: {}, turns: 0, activeSeconds: 0, subagents: {},
        skillCalls: [], agentCalls: [], askUserQuestions: []} | .lastPostedAt = $postedAt'
}

# サブエージェントレポート用: 前回pushからの差分が0（tokensByModel全モデル・toolCalls・
# activeSecondsのいずれも0）のagentIdを `sinceLastPush.subagents` から除外して返す（issue #34、
# 「差分0のagentはレポートに出力しない」というフィードバックへの対応）。
_usage_filter_nonzero_subagents() {
  local subagents="$1"
  printf '%s' "$subagents" | jq '
    to_entries
    | map(select(
        (((.value.tokensByModel // {}) | [.[] | (.input // 0) + (.output // 0) + (.cacheCreate // 0) + (.cacheRead // 0)] | add // 0) > 0)
        or (((.value.toolCalls // {}) | [.[]] | add // 0) > 0)
        or ((.value.activeSeconds // 0) > 0)
      ))
    | from_entries
  '
}
