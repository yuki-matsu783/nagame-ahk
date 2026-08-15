#!/usr/bin/env bash
#
# Claude Code SessionStart hook（bash版）。
# 設計: dev-tools/docs/spec/issue-mr-workflow.md「セッション開始時の自動コンテキスト注入」,
#       dev-tools/docs/spec/shell-scripts.md
#
# セッション開始・resume・clear時（.claude/settings.jsonのmatcher参照）に、現在チェックアウトされて
# いるブランチに紐づくissue/MRの状態を取得し、追加コンテキストとしてコンテキストに注入する。
#
# 前提: `gh` CLI・`jq` がインストール・認証済みであること（未認証・未インストールの場合は
# 非侵襲的に失敗メッセージのみ返し、セッション開始はブロックしない）。
#
# 注意: SessionStart hookはTask tool経由のサブエージェント内でも発火する（公式ドキュメント確認済み）。
# サブエージェント実行時はstdinのJSONに`agent_id`が含まれるため、これを見て即終了する
# （メインセッションのコンテキストのみを汚す設計）。
#
# 注意（エラー方針）: PowerShell版の try/catch に相当する構造として、リスクのある処理は
# 関数化してコマンド置換 `$(...)` の中で呼ぶ（コマンド置換は必ずサブシェル＝別プロセスで実行される
# ため、`set -e` の「if の条件式の中では-eが一時停止する」というbashの仕様の影響を受けず、
# 内部で失敗したコマンドの時点で確実にサブシェルごと終了し、呼び出し元の if で失敗を検知できる。
# 詳細: dev-tools/docs/spec/shell-scripts.md「bashでのtry/catch相当の書き方」節）。

set -uo pipefail

write_additional_context() {
  local text="$1"
  jq -nc --arg text "$text" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $text}}'
}

raw="$(cat)"
agent_id=""
if [ -n "$raw" ]; then
  agent_id="$(printf '%s' "$raw" | jq -r '.agent_id // empty' 2>/dev/null || true)"
fi

# サブエージェント内実行では何もしない（agent_idはサブエージェント呼び出し時のみ付与される）
if [ -n "$agent_id" ]; then
  exit 0
fi

if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  exit 0
fi

# リスクのある本体処理。失敗した場合はこの関数のexit codeが非ゼロになり呼び出し元へ伝わる。
build_context() {
  set -euo pipefail
  cd "$CLAUDE_PROJECT_DIR"
  source "${CLAUDE_PROJECT_DIR}/dev-tools/src/vcs/Provider.sh"

  local branch
  branch="$(git branch --show-current 2>/dev/null || true)"
  local base_branch
  base_branch="$(get_workflow_config | jq -r '.defaultBaseBranch')"
  if [ -z "$branch" ] || [ "$branch" = "$base_branch" ]; then
    # 作業ブランチ未チェックアウト（mainブランチ上）のときは注入しない。
    # exit code 2 は「エラーではなく意図的に何も注入しない」を表す専用の合図
    # （呼び出し元はこのコードのときだけフォールバックメッセージも出さない）。
    exit 2
  fi

  local lines=()
  lines+=("## 現在の作業ブランチ情報 (SessionStart hook)")
  lines+=("- ブランチ: ${branch}")

  local issue_number
  if issue_number="$(get_issue_number_from_branch "$branch")"; then
    local issue
    issue="$(get_issue "$issue_number")"
    lines+=("- issue: #$(printf '%s' "$issue" | jq -r '.number') $(printf '%s' "$issue" | jq -r '.title') ($(printf '%s' "$issue" | jq -r '.url'))")
  else
    lines+=("- issue: 特定できず（ブランチ名がissue命名規則に一致しません）")
  fi

  local mr
  mr="$(get_mr_for_branch "$branch")"
  if [ -n "$mr" ]; then
    local draft_label
    if [ "$(printf '%s' "$mr" | jq -r '.isDraft')" = "true" ]; then
      draft_label="[Draft]"
    else
      draft_label="[Ready]"
    fi
    lines+=("- PR: #$(printf '%s' "$mr" | jq -r '.number') $(printf '%s' "$mr" | jq -r '.title') ${draft_label} ($(printf '%s' "$mr" | jq -r '.url'))")

    local mr_number comments_text ids_count
    mr_number="$(printf '%s' "$mr" | jq -r '.number')"
    if comments_text="$(get_mr_unresolved_comments "$mr_number" 2>/dev/null)"; then
      ids_count="$(printf '%s\n' "$comments_text" | grep -oE '^\[review unresolved threadId=[^ ]+' | sed -E 's/.*threadId=//' | sort -u | wc -l | tr -d ' ')"
      lines+=("- 未解決レビューコメント: ${ids_count}件")
    else
      lines+=("- 未解決レビューコメント: 取得に失敗しました")
    fi
  else
    lines+=("- PR: なし")
  fi

  printf '%s\n' "${lines[@]}"
}

if context_text="$(build_context)"; then
  write_additional_context "$context_text"
else
  rc=$?
  if [ "$rc" -ne 2 ]; then
    write_additional_context "(issue/MR情報の取得に失敗しました)"
  fi
fi

exit 0
