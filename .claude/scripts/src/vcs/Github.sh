#!/usr/bin/env bash
#
# GitHub固有の処理（`gh` CLIラッパー、bash版）。
# 設計: .claude/scripts/docs/spec/issue-mr-workflow.md, .claude/scripts/docs/spec/shell-scripts.md
#
# 単体でsourceせず、必ず .claude/scripts/src/vcs/Provider.sh 経由で使う
# （Provider.sh が get_provider の判定結果に応じてこのファイルの関数へディスパッチする）。
# 前提: `gh` CLIがインストール・認証済み（`gh auth login`）であること。

github_get_issue() {
  local number="$1"
  local issue title slug
  issue="$(gh issue view "$number" --json number,title,body,url)"
  title="$(printf '%s' "$issue" | jq -r '.title')"
  slug="$(to_slug "$title")"
  printf '%s' "$issue" | jq --arg slug "$slug" \
    '{number: .number, title: .title, body: .body, url: .url, slug: $slug}'
}

# タイトル・本文からissueを新規作成する。作成後は `github_get_issue` で正規化した
# JSON（number/title/body/url/slug）を返す（get_issueと同じ形にすることで呼び出し側の扱いを揃える）。
github_new_issue() {
  local title="$1" body="$2"
  local url number
  url="$(gh issue create --title "$title" --body "$body")"
  number="$(printf '%s' "$url" | grep -oE '[0-9]+$')"
  if [ -z "$number" ]; then
    echo "gh issue create の出力からissue番号を取得できませんでした: $url" >&2
    return 1
  fi
  github_get_issue "$number"
}

github_new_draft_merge_request() {
  local issue_number="$1" branch="$2" base_branch="$3" title="$4"
  local body
  body="$(printf 'Closes #%s\n\n(plan作成中。/issue-mr-flow describe で更新する)' "$issue_number")"

  if ! gh pr create --draft --base "$base_branch" --head "$branch" --title "$title" --body "$body" >/dev/null; then
    # baseとの差分（コミット）が無いブランチでは `gh pr create` が失敗する既知の制約
    # （.claude/scripts/docs/spec/issue-mr-workflow.md参照）。空コミットで解消して1回だけリトライする。
    add_empty_commit_for_draft_mr
    if ! gh pr create --draft --base "$base_branch" --head "$branch" --title "$title" --body "$body" >/dev/null; then
      echo "gh pr create に失敗しました（空コミットでのリトライ後も失敗）" >&2
      return 1
    fi
  fi
  gh pr view "$branch" --json number --jq '.number'
}

# レビュースレッド＋通常のissueコメントをまとめて返す。既定では未解決（isResolved: false）の
# スレッドのみを対象とし、対応済み（解決済み）は機械的に除外する。include_resolved=true 指定時は
# 解決済みスレッドも含めた全件を返す。resolved/unresolvedの概念を持たない通常コメントは常に含める。
github_get_mr_unresolved_comments() {
  local mr_number="$1" include_resolved="${2:-false}"
  local query result

  # gh api graphqlの{owner}/{repo}プレースホルダはクエリ文字列中には展開されず、
  # -F フィールドの値としてのみ機能する（`gh api graphql --help` のGraphQL例を参照）。
  # そのため owner/repo もGraphQL変数として宣言し、-F 経由で渡す。
  query="$(cat <<'EOF'
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          path
          line
          comments(first: 50) { nodes { author { login } body diffHunk } }
        }
      }
      comments(first: 100) { nodes { author { login } body } }
    }
  }
}
EOF
)"

  result="$(gh api graphql -F "owner={owner}" -F "repo={repo}" -F "number=$mr_number" -f "query=$query")"

  printf '%s' "$result" | jq -r --argjson includeResolved "$include_resolved" '
    def thread_lines:
      .data.repository.pullRequest.reviewThreads.nodes[]
      | select((.isResolved | not) or $includeResolved)
      | . as $t
      | $t.comments.nodes[]
      | (
          "[review " + (if $t.isResolved then "resolved" else "unresolved" end)
          + " threadId=" + $t.id
          + " " + (if $t.path then ($t.path + ":" + (($t.line // "") | tostring)) else "(場所不明)" end)
          + "] " + .author.login + ": " + .body
        )
        + (if .diffHunk then ("\n--- diff ---\n" + .diffHunk) else "" end);
    def comment_lines:
      .data.repository.pullRequest.comments.nodes[]
      | "[comment] " + .author.login + ": " + .body;
    [thread_lines, comment_lines] | join("\n\n")
  '
}

# 指定したレビュースレッドに対応内容を返信する。スレッドの解決（resolved）はレビュアー側の
# 操作のためここでは行わない。mr_numberはプロバイダ間のインターフェース統一のため受け取るが、
# GitHub実装ではスレッドIDがグローバルに一意なため未使用。
github_add_mr_thread_reply() {
  local mr_number="$1" thread_id="$2" reply_body="$3"
  local mutation
  mutation="$(cat <<'EOF'
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
    comment { id }
  }
}
EOF
)"
  gh api graphql -F "threadId=$thread_id" -F "body=$reply_body" -f "query=$mutation" >/dev/null
}

# 指定ブランチに紐づくPRのJSONを返す（無ければ何も出力せず終了コード0）。途中引き継ぎ対応（resume）と、
# comments/describeサブコマンドでの「現在のブランチのMR番号取得」の共通実装として使う。
github_get_mr_for_branch() {
  local branch="$1"
  local json
  if ! json="$(gh pr view "$branch" --json number,url,isDraft,title 2>/dev/null)"; then
    return 0
  fi
  printf '%s' "$json" | jq '{number: .number, url: .url, isDraft: .isDraft, title: .title}'
}

github_set_mr_description() {
  local mr_number="$1" body_file="$2"
  gh pr edit "$mr_number" --body-file "$body_file" >/dev/null
}

# MRへ新規コメントを1件投稿する（スレッド返信・レビューではない通常コメント）。
github_add_mr_comment() {
  local mr_number="$1" body_file="$2"
  gh pr comment "$mr_number" --body-file "$body_file" >/dev/null
}
