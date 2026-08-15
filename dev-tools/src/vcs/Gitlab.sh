#!/usr/bin/env bash
#
# GitLab固有の処理（`glab` CLIラッパー、bash版）。
# 設計: dev-tools/docs/spec/issue-mr-workflow.md, dev-tools/docs/spec/shell-scripts.md
#
# 単体でsourceせず、必ず dev-tools/src/vcs/Provider.sh 経由で使う
# （Provider.sh が get_provider の判定結果に応じてこのファイルの関数へディスパッチする）。
# 前提: `glab` CLIがインストール・認証済み（`glab auth login`）であること。
#
# 【未検証】このリポジトリのremoteはGitHubのみのため、以下は`glab`のドキュメントを元にした
# 実装であり実機での動作確認ができていない（PowerShell版Gitlab.ps1と同様の制約を引き継ぐ。
# dev-tools/docs/spec/issue-mr-workflow.md の「未決定事項・懸念点」参照）。GitLabリポジトリで
# 実際に使う前に動作確認すること。

gitlab_get_issue() {
  local number="$1"
  local issue title slug
  issue="$(glab issue view "$number" --output json)"
  title="$(printf '%s' "$issue" | jq -r '.title')"
  slug="$(to_slug "$title")"
  printf '%s' "$issue" | jq --arg slug "$slug" \
    '{number: .iid, title: .title, body: .description, url: .web_url, slug: $slug}'
}

gitlab_new_draft_merge_request() {
  local issue_number="$1" branch="$2" base_branch="$3" title="$4"
  local description
  description="$(printf 'Closes #%s\n\n(plan作成中。/issue-mr-flow describe で更新する)' "$issue_number")"

  if ! glab mr create --draft --source-branch "$branch" --target-branch "$base_branch" \
      --title "$title" --description "$description" --yes >/dev/null; then
    # baseとの差分（コミット）が無いブランチでは `glab mr create` が失敗する既知の制約
    # （dev-tools/docs/spec/issue-mr-workflow.md参照）。空コミットで解消して1回だけリトライする。
    # 【未検証】このリポジトリのremoteはGitHubのみのためGitLab側の実機確認はできていない。
    add_empty_commit_for_draft_mr
    if ! glab mr create --draft --source-branch "$branch" --target-branch "$base_branch" \
        --title "$title" --description "$description" --yes >/dev/null; then
      echo "glab mr create に失敗しました（空コミットでのリトライ後も失敗）" >&2
      return 1
    fi
  fi
  glab mr view "$branch" --output json --jq '.iid'
}

# discussion内のnoteをまとめて返す。既定では resolved: false（未解決）のnoteのみを対象とし、
# 対応済み（解決済み）は機械的に除外する。include_resolved=true 指定時は解決済みも含めた全件を返す。
# 個人メモ（individual_note）等 resolvable でないnoteは常に含める。
gitlab_get_mr_unresolved_comments() {
  local mr_number="$1" include_resolved="${2:-false}"
  local discussions
  discussions="$(glab api "projects/:id/merge_requests/${mr_number}/discussions")"

  printf '%s' "$discussions" | jq -r --argjson includeResolved "$include_resolved" '
    [
      .[] as $d
      | $d.notes[]
      | . as $n
      | ($n.resolvable and $n.resolved) as $isResolved
      | select(($isResolved | not) or $includeResolved)
      | "[" + (if $isResolved then "resolved" else "unresolved" end)
        + " threadId=" + ($d.id | tostring) + "] " + $n.author.username + ": " + $n.body
    ] | join("\n\n")
  '
}

# 指定したdiscussion（スレッド）に対応内容を返信する。スレッドの解決（resolved）はレビュアー側の
# 操作のためここでは行わない。【未検証】このリポジトリのremoteはGitHubのみのため実機確認できていない。
gitlab_add_mr_thread_reply() {
  local mr_number="$1" thread_id="$2" reply_body="$3"
  glab api "projects/:id/merge_requests/${mr_number}/discussions/${thread_id}/notes" \
    -X POST -f "body=${reply_body}" >/dev/null
}

# 指定ブランチに紐づくMRのJSONを返す（無ければ何も出力せず終了コード0）。途中引き継ぎ対応（resume）と、
# comments/describeサブコマンドでの「現在のブランチのMR番号取得」の共通実装として使う。
# 【未検証】このリポジトリのremoteはGitHubのみのため実機確認できていない。
gitlab_get_mr_for_branch() {
  local branch="$1"
  local json
  if ! json="$(glab mr view "$branch" --output json 2>/dev/null)"; then
    return 0
  fi
  printf '%s' "$json" | jq '{number: .iid, url: .web_url, isDraft: .work_in_progress, title: .title}'
}

gitlab_set_mr_description() {
  local mr_number="$1" body_file="$2"
  local description
  description="$(cat "$body_file")"
  glab mr update "$mr_number" --description "$description" >/dev/null
}

# MRへ新規コメントを1件投稿する（スレッド返信・レビューではない通常コメント）。
# 【未検証】このリポジトリのremoteはGitHubのみのため実機確認できていない。
gitlab_add_mr_comment() {
  local mr_number="$1" body_file="$2"
  local body
  body="$(cat "$body_file")"
  glab mr note "$mr_number" --message "$body" >/dev/null
}
