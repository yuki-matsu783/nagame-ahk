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

# 稼働時間（activeSeconds）算出用の閾値（秒）。連続するtranscript entry間の経過時間がこれ以上の
# 場合は「人間の入力待ち」（AskUserQuestionの回答待ち・応答終了後の次指示待ち等）とみなし、
# その区間（gapそのもの）は稼働時間に加算しない（ちょうど閾値と同じgapも「待ち」側として扱う）。
# 閾値未満のgapはツール実行待ち等の実作業とみなしそのまま加算する。
# `:=` を使い、呼び出し側（テスト等）が事前に設定していればそちらを優先する。
# 詳細: dev-tools/docs/spec/issue-mr-workflow.md「対応工数レポート」節
: "${IDLE_GAP_THRESHOLD_SECONDS:=300}"

# 稼働時間の区間（セグメント）が閉じるたびに末尾へ加算する固定秒数。応答を読む・確認する等、
# 次のgapとしては現れない実作業時間を補うためのもの（参考実装 claude-work-timer の
# tail-buffer相当。既定値もそれに合わせて30秒とした）。
: "${TAIL_BUFFER_SECONDS:=30}"

# ブランチ名を状態ファイル名・ディレクトリ名に使える形へサニタイズする（英数字・ハイフン・
# アンダースコア以外を`_`へ置換）。sync_usage_state / _usage_sync_session_logs /
# post-push-usage-report.sh の3箇所で同じ変換が必要になったため関数化した。
_usage_safe_branch_name() {
  printf '%s' "$1" | sed -E 's/[^a-zA-Z0-9_-]/_/g'
}

# transcript(JSONL)を集計し、{tokens, tools, assistantCount, activeSeconds} のJSONをstdoutへ
# 出力する。空行・不正なJSON行は無視する（ベストエフォート）。指定ブランチ以外のassistantエントリは
# 除外する。
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
# 「current - prevSession値（下限0）」という既存の累計差分パターンがそのまま安全に使える。
#
# 注意（`fromdateiso8601`を使わない理由）: 開発機のjq（Windowsネイティブ版jq 1.6）は
# `strptime`/`mktime`が未実装で、`fromdateiso8601`（内部で`strptime`を使う）を呼ぶと
# `strptime/1 not implemented on this platform`で失敗する（実機確認済み）。さらに、この失敗が
# 後段の`try fromjson catch empty`（不正なJSON行を無視するための既存ガード）と組み合わさると、
# jq自体がエラーを一切出さずに出力全体が`null`になるという実機確認済みの現象があり、原因の特定が
# 非常に困難だった。そのため`strptime`/`mktime`に依存しない、`days_from_civil`アルゴリズム
# （Howard Hinnant氏の“chrono”ライブラリで広く使われる、グレゴリオ暦の日数計算を四則演算のみで
# 行う手法）による自前のISO8601→epoch秒変換を実装する。ミリ秒（`.461Z`等）が付いた実際の
# transcriptタイムスタンプ形式に対しても、先頭19文字（`YYYY-MM-DDTHH:MM:SS`）だけを固定位置で
# 読み取るため問題なく動作する（`date -u -d <iso8601> +%s`との一致を手動確認済み）。
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

# 状態ファイル(既存JSON)・今回の集計(current)・セッションIDを突き合わせ、
# 「前回このセッションで記録した累計との差分」をsinceLastPushへ加算した新しい状態JSONを返す。
#
# 注意（`agents`のpassthrough）: `$existing.agents`（サブエージェントのagentId単位累計
# スナップショット。`_usage_merge_agent_state`が読み書きする）は本関数が管理するフィールドでは
# ないが、出力オブジェクトへそのまま引き継ぐ。`sync_usage_state`はメインセッション分の本関数呼び出し
# →サブエージェント分の`_usage_aggregate_and_merge_subagents`呼び出し、の順で状態を受け渡すため、
# ここで`agents`を落とすと後続のサブエージェント差分計算が毎回「前回スナップショット無し」扱いになり、
# 差分ではなく毎回transcript全体を計上してしまうバグになる（issue #34で発生・修正）。
_usage_merge_state() {
  local existing="$1" current="$2" session_id="$3" branch="$4"
  local jq_program
  jq_program="$(cat <<'JQ'
def zero_bucket: {input: 0, output: 0, cacheCreate: 0, cacheRead: 0};

($existing.sessions // {}) as $sessions
| ($sessions[$sessionId] // {lastTokens: {}, lastTools: {}, lastAssistantCount: 0, lastActiveSeconds: 0}) as $prevSession
| ($prevSession.lastTokens // {}) as $prevTokens
| ($prevSession.lastTools // {}) as $prevTools
| (($prevSession.lastAssistantCount // 0) | tonumber) as $prevAssistantCount
| (($prevSession.lastActiveSeconds // 0) | tonumber) as $prevActiveSeconds
| ($existing.sinceLastPush // {tokensByModel: {}, toolCalls: {}, turns: 0, activeSeconds: 0}) as $sincePrev
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
| ($sinceAfterTools.activeSeconds // 0) as $activeSecondsAcc
| ([0, ($current.activeSeconds - $prevActiveSeconds)] | max) as $activeSecondsDelta
| ($sinceAfterTools
    | .turns = ($turnsAcc + $turnsDelta)
    | .activeSeconds = ($activeSecondsAcc + $activeSecondsDelta)) as $newSince
| ($existing.sessions // {}) as $existingSessions
| ($existingSessions + {($sessionId): {
    lastTokens: $current.tokens,
    lastTools: $current.tools,
    lastAssistantCount: $current.assistantCount,
    lastActiveSeconds: $current.activeSeconds
  }}) as $newSessions
| {branch: $branch, sessions: $newSessions, sinceLastPush: $newSince}
  + (if $existing.lastPostedAt then {lastPostedAt: $existing.lastPostedAt} else {} end)
  + (if $existing.agents then {agents: $existing.agents} else {} end)
JQ
)"
  jq -n --argjson existing "$existing" --argjson current "$current" \
    --arg sessionId "$session_id" --arg branch "$branch" \
    "$jq_program"
}

# git push検知時に、集計対象のtranscript（メイン＋サブエージェント）をリポジトリ内の
# gitignore対象ディレクトリ（.claude/session-logs/<safeBranch>/<sessionId>/）へコピーする
# （PR #29レビュー指摘: `~/.claude/projects`という非公開・ユーザープロファイル配下の揮発性のある
# パスに集計処理が直接依存し続けるのを避け、pushのたびにリポジトリ内へスナップショットを退避する）。
# コピー先ディレクトリパスをstdoutへ返す。
#
# メインtranscriptのコピー失敗はそのまま呼び出し元へエラー伝播させる（sync_usage_state側の
# `[ -f "$transcript_path" ]` チェックと同格の致命条件のため、set -eに任せる）。個々のサブエージェント
# ファイルのコピー失敗は`|| true`で握りつぶし他のファイルへ波及させない（次回pushの全件再パースで
# 自然に回収されるため、1ファイルの失敗でpush全体の記録が止まる必要は無い）。
#
# サブエージェントの発見: `${transcript_path%.jsonl}/subagents/agent-*.jsonl` のみを対象とする
# （直接の子、spawnDepth 1相当）。サブエージェントがさらに起動するネストしたサブエージェント
# （depth 2以降）は対象外（実データで未観測かつディレクトリ構造・スキーマが未確認のため。詳細:
# dev-tools/docs/spec/issue-mr-workflow.md「サブエージェントの使用量記録」節）。
_usage_sync_session_logs() {
  local repo_root="$1" branch="$2" session_id="$3" transcript_path="$4"

  local safe_branch
  safe_branch="$(_usage_safe_branch_name "$branch")"
  local log_dir="${repo_root}/.claude/session-logs/${safe_branch}/${session_id}"
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

# 1つのサブエージェント（agentId単位）について、_usage_merge_state と全く同じ
# 「current - prevSnapshot（下限0）」ロジックを適用する。累計スナップショット・sinceLastPush差分の
# いずれもagentId単位で保持する（バックグラウンドで複数pushをまたいで追記され続けるサブエージェント
# があっても、既存の単調性保証がそのまま効き二重計上・過小計上が起きないようにするため）。
# レポート表示はagentIdごとに1行とする方針のため、agentType単位での合算は行わない（issue #34、
# 「同じagentTypeを複数回起動してもどのagentがどれだけ使ったか見えない」というフィードバックにより
# agentType単位の合算表示から変更）。`agentType`・`description`（`meta.json`の値。表示ラベル用）は
# スナップショット・sinceLastPushの両方に付与して保存する。
#
# _usage_aggregate_transcript / _usage_merge_state 本体は無改造のまま、agentId を「疑似session_id」、
# agentId別の累計を「疑似sinceLastPush」としてラップして渡すことで、既存の差分計算ロジックを
# そのまま再利用する。
_usage_merge_agent_state() {
  local existing="$1" agent_id="$2" agent_type="$3" description="$4" current="$5" branch="$6"

  local pseudo_existing
  pseudo_existing="$(printf '%s' "$existing" | jq -c --arg agentId "$agent_id" '
    {
      sessions: {($agentId): (.agents[$agentId] // {})},
      sinceLastPush: (.sinceLastPush.subagents[$agentId]
        // {tokensByModel: {}, toolCalls: {}, turns: 0, activeSeconds: 0})
    }
  ')"

  local merged
  merged="$(_usage_merge_state "$pseudo_existing" "$current" "$agent_id" "$branch")"

  jq -n --argjson existing "$existing" --argjson merged "$merged" \
    --arg agentId "$agent_id" --arg agentType "$agent_type" --arg description "$description" '
    $existing
    | .agents[$agentId] = ($merged.sessions[$agentId] + {agentType: $agentType, description: $description})
    | .sinceLastPush.subagents[$agentId] = ($merged.sinceLastPush + {agentType: $agentType, description: $description})
  '
}

# コピー済みディレクトリ（_usage_sync_session_logsの戻り値）配下のサブエージェントtranscriptを
# 列挙し、1ファイルずつ _usage_aggregate_transcript で集計→_usage_merge_agent_state で
# existing へ畳み込む。サブエージェントが1件も無ければexistingをそのまま返す。
_usage_aggregate_and_merge_subagents() {
  local existing="$1" log_dir="$2" branch="$3"
  local subagents_dir="${log_dir}/subagents"

  if [ ! -d "$subagents_dir" ]; then
    printf '%s' "$existing"
    return 0
  fi

  local f
  for f in "$subagents_dir"/agent-*.jsonl; do
    [ -e "$f" ] || continue
    local agent_id agent_type description meta_file current
    agent_id="$(basename "$f" .jsonl)"
    agent_id="${agent_id#agent-}"
    meta_file="${f%.jsonl}.meta.json"
    if [ -f "$meta_file" ]; then
      agent_type="$(jq -r '.agentType // "unknown"' "$meta_file" 2>/dev/null || echo "unknown")"
      # description: Agent/Taskツール起動時に渡された説明文（レポートの行ラベルに使う）。
      # 実データ確認済み: meta.jsonにagentTypeと併せて記録されている。無ければ空文字のまま扱う。
      description="$(jq -r '.description // ""' "$meta_file" 2>/dev/null || echo "")"
    else
      agent_type="unknown"
      description=""
    fi
    [ -n "$agent_type" ] || agent_type="unknown"

    current="$(_usage_aggregate_transcript "$f" "$branch")"
    existing="$(_usage_merge_agent_state "$existing" "$agent_id" "$agent_type" "$description" "$current" "$branch")"
  done

  printf '%s' "$existing"
}

# 指定ブランチ・セッションのtranscriptを集計し、状態ファイル（.claude/usage-state/<branch>.json）の
# sinceLastPush へ「前回このセッションで記録した累計との差分」を加算して保存する。更新後の状態JSONを
# stdoutへ出力する。呼び出し元は post-push-usage-report.sh（PostToolUse, git push検知）。
# transcript_pathが存在しない場合は何も出力せず終了コード1を返す。
#
# 集計前に _usage_sync_session_logs でメイン・サブエージェント両方のtranscriptを
# .claude/session-logs/ 配下へコピーし、以降の集計はすべてこのローカルコピーを対象に行う
# （PR #29レビュー指摘対応）。全件再パース＋スナップショット差分方式そのものは変更しない
# （activeSecondsの単調性保証が「毎回全件を時系列で走査し直す」ことを前提にしているため）。
sync_usage_state() {
  local repo_root="$1" branch="$2" session_id="$3" transcript_path="$4"

  if [ ! -f "$transcript_path" ]; then
    return 1
  fi

  local log_dir
  log_dir="$(_usage_sync_session_logs "$repo_root" "$branch" "$session_id" "$transcript_path")"

  local current
  current="$(_usage_aggregate_transcript "${log_dir}/main.jsonl" "$branch")"

  local state_dir="${repo_root}/.claude/usage-state"
  mkdir -p "$state_dir"
  local safe_branch
  safe_branch="$(_usage_safe_branch_name "$branch")"
  local state_file="${state_dir}/${safe_branch}.json"

  local existing="{}"
  if [ -f "$state_file" ]; then
    existing="$(cat "$state_file")"
  fi

  local new_state
  new_state="$(_usage_merge_state "$existing" "$current" "$session_id" "$branch")"
  new_state="$(_usage_aggregate_and_merge_subagents "$new_state" "$log_dir" "$branch")"

  printf '%s' "$new_state" > "$state_file"
  printf '%s' "$new_state"
}

# post-push-usage-report.sh がMRへの投稿成功後に呼ぶ、sinceLastPushのゼロ初期化。
# 状態JSON全体（state）を受け取り、sinceLastPushをゼロ初期化・lastPostedAtを現在時刻に更新した
# 新しい状態JSONをstdoutへ返す（呼び出し元がstate_fileへ書き戻す）。他のフィールド（sessions,
# agents等）はそのまま保持する。
#
# post-push-usage-report.sh本体からロジックを切り出した理由: インラインjqのままだと
# tests/test_usage_tracking.shから直接検証できず、「pushでsinceLastPushを積算→投稿成功でリセット
# →次のpushでは差分のみが積算される」という一連の流れ（issue #34のpush差分バグの回帰テスト）を
# 実運用と全く同じリセットロジックで再現できないため。
_usage_reset_since_last_push() {
  local state="$1"
  printf '%s' "$state" | jq \
    --arg postedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.sinceLastPush = {tokensByModel: {}, toolCalls: {}, turns: 0, activeSeconds: 0, subagents: {}} | .lastPostedAt = $postedAt'
}

# サブエージェントレポート用: 前回pushからの差分が0（tokensByModel全モデル・toolCalls・
# activeSecondsのいずれも0）のagentIdを `sinceLastPush.subagents` から除外して返す（issue #34、
# 「差分0のagentはレポートに出力しない」というフィードバックへの対応）。トークンテーブル本体で
# 既に行っている「4項目とも0のモデル行は表示しない」という間引きと同じ考え方を、agent単位に適用した
# もの。post-push-usage-report.shのテーブル描画・稼働時間参考値等の集計は、この関数の出力に対して
# 行う。
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
