#!/usr/bin/env bash
#
# Claude Code PostToolUse hook（git push検知、/compact実施を促すメッセージ注入）。
# 設計: plans/silly-puzzling-ember.md（issue #11）→ dev-tools/docs/spec/issue-mr-workflow.md
#
# .claude/settings.json 側で matcher: "Bash|PowerShell" と、各エントリの if フィールド
# （"Bash(git push*)" / "PowerShell(git push*)"）によって、tool_input のコマンドが
# git push を含む場合のみ起動される（マッチしなければClaude Code側でプロセスが起動されず、
# 通常のBash/PowerShell利用への性能影響は無い）。if フィルタはベストエフォートのため、
# 本スクリプト側でも念のため command 文字列を正規表現で再チェックする
# （検知ロジックは post-push-usage-report.sh と同一パターン）。
#
# post-push-usage-report.sh と責務を分離した別スクリプト（使用量集計の投稿先はMRコメントだが、
# 本スクリプトはユーザーへの直接的な呼びかけであり、伝達手段・関心事が異なるため）。
# 伝達手段は session-start.sh の write_additional_context と同じ
# `hookSpecificOutput.additionalContext` 方式（stdoutへJSON出力→コンテキストへ注入→
# エージェントが応答に反映）を PostToolUse で使う。
#
# 注意（エラー方針）: 本体処理は `main` 関数にまとめ、`( main )` のように実サブシェル（丸括弧）の
# 中で呼ぶことで、内部で失敗したコマンドの時点で確実にサブシェルごと終了させる（bashの
# 「if/||の条件式の中では-eが一時停止する」という仕様の影響を受けないようにするため。詳細:
# dev-tools/docs/spec/shell-scripts.md「bashでのtry/catch相当の書き方」節）。失敗はすべて
# 握りつぶし、git push自体はブロックしない。

set -uo pipefail

CONTEXT_MESSAGE='ユーザにMRレビュー実施を促すメッセージを注入するフックです。また、前回のcompact実施から一定期間経過している場合、/compactの実施をAskUserQuestionで確認してください。'
COMPACT_PROMPT_MESSAGE='メッセージ例: MRのレビューをお願いします。/compactを実施をしていただくと、レビュー中にコンテキストを圧縮して今後の作業が効率的になる可能性があります'

write_additional_context() {
  local text="$1"
  jq -nc --arg text "$text" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $text}}'
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
  # サブエージェント内実行では何もしない（post-push-usage-report.shと同じガード）
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

  local branch base_branch
  branch="$(git branch --show-current 2>/dev/null || true)"
  base_branch="$(get_workflow_config | jq -r '.defaultBaseBranch')"
  [ -n "$branch" ] && [ "$branch" != "$base_branch" ] || exit 0

  local mr
  mr="$(get_mr_for_branch "$branch")"
  [ -n "$mr" ] || exit 0

  write_additional_context "$CONTEXT_MESSAGE $COMPACT_PROMPT_MESSAGE"
}

( main ) || true

exit 0
