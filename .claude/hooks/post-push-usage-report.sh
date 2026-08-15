#!/usr/bin/env bash
#
# Claude Code PostToolUse hook（git push検知、bash版）。
# 設計: plans/groovy-zooming-balloon.md（issue #15）→ dev-tools/docs/spec/issue-mr-workflow.md,
#       dev-tools/docs/spec/shell-scripts.md（issue #6、bash化）
#
# .claude/settings.json 側で matcher: "Bash|PowerShell" と、各エントリの if フィールド
# （"Bash(git push*)" / "PowerShell(git push*)"）によって、tool_input のコマンドが
# git push を含む場合のみ起動される（マッチしなければClaude Code側でプロセスが起動されず、
# 通常のBash/PowerShell利用への性能影響は無い）。if フィルタはベストエフォートのため、
# 本スクリプト側でも念のため command 文字列を正規表現で再チェックする。
#
# 投稿前に、自分自身で .claude/hooks/lib/UsageTracking.sh の sync_usage_state を呼んで
# 状態を最新化する（トークン数・ツール実行回数・assistant応答回数のいずれも、このタイミングで
# transcriptとの差分を計算する）。これにより、当該ターンの途中でgit pushが実行されるケース
# （例: 最初のpushがブランチ作成・調査・実装と同じターン内で行われる場合）でも、その時点までに
# transcriptへ書き出し済みの内容を漏れなく反映できる。
#
# `sinceLastPush` を読み、MRへ新規コメントとして投稿する（レビューではない通常コメントのため、
# レビュー合否判定には影響しない）。投稿に成功したら `sinceLastPush` をリセットする。失敗時は
# 状態を変更せず握りつぶす（次のpush時に繰り越されるだけで、git push自体をブロックしない）。
#
# 注意（エラー方針）: 本体処理は `main` 関数にまとめ、`( main )` のように実サブシェル（丸括弧）の
# 中で呼ぶことで、内部で失敗したコマンドの時点で確実にサブシェルごと終了させる（bashの
# 「if/||の条件式の中では-eが一時停止する」という仕様の影響を受けないようにするため。詳細:
# dev-tools/docs/spec/shell-scripts.md「bashでのtry/catch相当の書き方」節）。失敗はすべて
# 握りつぶし、git push自体はブロックしない。

set -uo pipefail

fmt_num() {
  # 3桁ごとにカンマを挿入する（PowerShell版の "{0:N0}" 相当）
  printf '%d' "$1" | sed -E ':a; s/([0-9])([0-9]{3})(,|$)/\1,\2\3/; ta'
}

main() {
  set -euo pipefail

  local raw
  raw="$(cat)"
  [ -n "$raw" ] || exit 0

  local hook_input
  hook_input="$(printf '%s' "$raw" | jq -c '.' 2>/dev/null)" || exit 0
  [ -n "$hook_input" ] || exit 0

  local agent_id
  agent_id="$(printf '%s' "$hook_input" | jq -r '.agent_id // empty')"
  # サブエージェント内実行では何もしない（SessionStart hookと同じガード。並行書き込みによる
  # 状態ファイル競合を避ける意味もある）
  [ -z "$agent_id" ] || exit 0

  [ -n "${CLAUDE_PROJECT_DIR:-}" ] || exit 0

  local tool_name
  tool_name="$(printf '%s' "$hook_input" | jq -r '.tool_name // empty')"
  if [ "$tool_name" != "Bash" ] && [ "$tool_name" != "PowerShell" ]; then
    exit 0
  fi

  local command
  command="$(printf '%s' "$hook_input" | jq -r '.tool_input.command // empty')"
  if [ -z "$command" ] || ! printf '%s' "$command" | grep -qiE 'git[[:space:]]+push'; then
    exit 0
  fi

  cd "$CLAUDE_PROJECT_DIR"
  source "${CLAUDE_PROJECT_DIR}/dev-tools/src/vcs/Provider.sh"
  source "${CLAUDE_PROJECT_DIR}/.claude/hooks/lib/UsageTracking.sh"

  local branch base_branch
  branch="$(git branch --show-current 2>/dev/null || true)"
  base_branch="$(get_workflow_config | jq -r '.defaultBaseBranch')"
  [ -n "$branch" ] && [ "$branch" != "$base_branch" ] || exit 0

  local session_id transcript_path repo_root
  session_id="$(printf '%s' "$hook_input" | jq -r '.session_id // empty')"
  transcript_path="$(printf '%s' "$hook_input" | jq -r '.transcript_path // empty')"
  repo_root="$(get_repo_root)"

  local safe_branch state_dir state_file state=""
  safe_branch="$(printf '%s' "$branch" | sed -E 's/[^a-zA-Z0-9_-]/_/g')"
  state_dir="${repo_root}/.claude/usage-state"
  state_file="${state_dir}/${safe_branch}.json"

  # 投稿判定の前に、その時点までtranscriptへ書き出し済みの内容を状態へ反映する
  # （ターンの途中でのpushでも、初回pushなどで記録漏れが起きないようにするための同期）
  if [ -n "$session_id" ] && [ -n "$transcript_path" ]; then
    state="$(sync_usage_state "$repo_root" "$branch" "$session_id" "$transcript_path" || true)"
  fi

  if [ -z "$state" ]; then
    [ -f "$state_file" ] || exit 0
    state="$(cat "$state_file")"
  fi

  if [ "$(printf '%s' "$state" | jq 'has("sinceLastPush")')" != "true" ]; then
    exit 0
  fi
  local usage
  usage="$(printf '%s' "$state" | jq -c '.sinceLastPush')"

  # 合計が0なら投稿しない（初回push・使用量が積み上がっていないpush対策）
  local total
  total="$(printf '%s' "$usage" | jq '[.tokensByModel[] | (.input // 0) + (.output // 0) + (.cacheCreate // 0) + (.cacheRead // 0)] | add // 0')"
  [ "$total" != "0" ] || exit 0

  local mr
  mr="$(get_mr_for_branch "$branch")"
  [ -n "$mr" ] || exit 0
  local mr_number
  mr_number="$(printf '%s' "$mr" | jq -r '.number')"

  # --- コメント本文の組み立て ---
  local tmp_file
  tmp_file="$(mktemp)"
  {
    echo "## セッション使用量レポート（自動投稿・前回pushからの差分）"
    echo ""
    echo "> このコメントはClaude Codeによる自動投稿です。**レビューの合否判定には使用しないでください。**"
    echo ""
    echo "- ブランチ: ${branch}"
    echo "- assistant応答回数: $(printf '%s' "$usage" | jq -r '.turns')"
    echo ""
    echo "| モデル | Input | Output | Cache Write | Cache Read |"
    echo "|---|---:|---:|---:|---:|"
    local model
    for model in $(printf '%s' "$usage" | jq -r '.tokensByModel | keys[]' | sort); do
      local m input_v output_v create_v read_v
      m="$(printf '%s' "$usage" | jq -c --arg model "$model" '.tokensByModel[$model]')"
      input_v="$(printf '%s' "$m" | jq -r '.input // 0')"
      output_v="$(printf '%s' "$m" | jq -r '.output // 0')"
      create_v="$(printf '%s' "$m" | jq -r '.cacheCreate // 0')"
      read_v="$(printf '%s' "$m" | jq -r '.cacheRead // 0')"
      echo "| ${model} | $(fmt_num "$input_v") | $(fmt_num "$output_v") | $(fmt_num "$create_v") | $(fmt_num "$read_v") |"
    done
    echo ""
    local tool_summary
    tool_summary="$(printf '%s' "$usage" | jq -r '.toolCalls | to_entries | sort_by(.key) | map("\(.key): \(.value)") | join(", ")')"
    if [ -n "$tool_summary" ]; then
      echo "**ツール実行回数**: ${tool_summary}"
      echo ""
    fi
    echo "---"
    echo "Claude Codeより: 自動投稿（post-push-usage-report.sh による集計。"
    echo "transcriptの非公開フォーマットに依存したベストエフォートの集計のため、目安として扱ってください）"
  } > "$tmp_file"

  add_mr_comment "$mr_number" "$tmp_file"
  rm -f "$tmp_file"

  # 投稿成功時のみ sinceLastPush をリセットする（失敗時は次回pushへ繰り越す。
  # add_mr_commentが失敗した場合はここに到達せず、set -e により main ごと中断される）
  local reset_state
  reset_state="$(printf '%s' "$state" | jq \
    --arg postedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.sinceLastPush = {tokensByModel: {}, toolCalls: {}, turns: 0} | .lastPostedAt = $postedAt')"
  mkdir -p "$state_dir"
  printf '%s' "$reset_state" > "$state_file"
}

( main ) || true

exit 0
