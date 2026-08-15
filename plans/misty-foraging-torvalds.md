# レビューコメントへの返信機能 + 対応済み除外フィルタ

## Context

PR #4のレビュー対応を進める中で、ユーザーから2つの追加要望があった
（設計は `dev-tools/docs/spec/issue-mr-workflow.md`「レビューコメントへの返信」節に承認済み）。

1. レビュー対応が完了したら、各コメントへ対応内容を返信できるようにする。
2. `Get-MrUnresolvedComments` を拡張し、対応済み（解決済み）レビューを既定で機械的に除外、
   必要なときだけ全件取得できるようにする。

**スレッドの解決（resolved）操作自体は行わない**（レビュアー側の操作のため。ユーザー明示の方針）。
本機能は「返信する」until のみを行い、解決マークは引き続き人間が行う。
`Get-MrUnresolvedComments` の除外は、その人間による解決マーク（`isResolved`）を判定に使う
（既存の実装がすでにこの判定をしているため、除外ロジック自体は変更不要。`-IncludeResolved`
スイッチを追加するのみ）。

`gh api graphql` のスキーマintrospection（読み取り専用のクエリで確認済み、副作用なし）により、
返信に使うmutationを確認した:

```graphql
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
    comment { id }
  }
}
```

`AddPullRequestReviewThreadReplyInput` の必須フィールドは `pullRequestReviewThreadId: ID!` と
`body: String!`（`gh api graphql` introspectionで確認済み）。

## 実装内容

### 1. `dev-tools/src/vcs/Github.ps1`

- `GitHub-GetMrUnresolvedComments`:
  - `[switch]$IncludeResolved` パラメータを追加。
  - GraphQLクエリの `reviewThreads.nodes` に `id` フィールドを追加。
  - フィルタ条件を `if ($thread.isResolved -and -not $IncludeResolved) { continue }` に変更。
  - 出力の各行に `threadId=<id>` と解決状態（`resolved`/`unresolved`）を含める
    （例: `[review unresolved threadId=PRRT_xxx path:line] author: body`）。
- `GitHub-AddMrThreadReply -MrNumber <n> -ThreadId <id> -ReplyBody <text>`（新規）:
  - 上記mutationを `gh api graphql -f "query=..." -F "threadId=$ThreadId" -F "body=$ReplyBody"` で実行。
  - `$MrNumber` は他プロバイダとのインターフェース統一のため受け取るが、GitHub実装では未使用。

### 2. `dev-tools/src/vcs/Gitlab.ps1`

- `GitLab-GetMrUnresolvedComments`:
  - `[switch]$IncludeResolved` パラメータを追加。
  - フィルタ条件を同様に変更し、出力に `threadId=<discussion.id>` と解決状態を含める。
- `GitLab-AddMrThreadReply -MrNumber <n> -ThreadId <id> -ReplyBody <text>`（新規、未検証）:
  - `glab api "projects/:id/merge_requests/$MrNumber/discussions/$ThreadId/notes" -X POST -f "body=$ReplyBody"`
    でdiscussionへnoteを追加する。

### 3. `dev-tools/src/vcs/Provider.ps1`

- `Get-MrUnresolvedComments` ディスパッチャに `[switch]$IncludeResolved` を追加し、
  `-IncludeResolved:$IncludeResolved` として両実装へ引き渡す。
- `Add-MrThreadReply -MrNumber <n> -ThreadId <id> -ReplyBody <text>`（新規ディスパッチャ）を追加。

### 4. `.claude/skills/issue-mr-flow/SKILL.md`

- `comments` サブコマンド:
  - 引数 `all` を受け付け、指定時は `Get-MrUnresolvedComments -IncludeResolved` を呼ぶ旨を追記。
  - 手順3に「対応が完了したコメントには `reply` サブコマンドで対応内容を返信する」旨を追記。
- `reply <threadId> <対応内容>`（新規サブコマンド）:
  1. 現在のブランチに紐づくMR番号を取得する（`comments` 手順1と同じ）。
  2. `Add-MrThreadReply -MrNumber <n> -ThreadId <threadId> -ReplyBody <対応内容>` を実行する。
  3. スレッドの解決（resolved）はレビュアー側の操作であり、本コマンドでは行わない旨を明記する。
- 全体フロー表の該当行（9・14）に「対応済みコメントは `reply` で返信する」旨を軽く追記する。

## 影響範囲

変更: `dev-tools/src/vcs/Github.ps1`, `dev-tools/src/vcs/Gitlab.ps1`, `dev-tools/src/vcs/Provider.ps1`,
`.claude/skills/issue-mr-flow/SKILL.md`

（`dev-tools/docs/spec/issue-mr-workflow.md` は既に更新・承認済み。今回はコードとSKILL.mdの実装のみ）

## 検証方法

1. **構文チェック**: `Provider.ps1` を dot-source し、`Get-MrUnresolvedComments` / `Add-MrThreadReply` /
   `GitHub-AddMrThreadReply` が読み込めることを確認する。
2. **`-IncludeResolved` の実機確認**: PR #4に対して `Get-MrUnresolvedComments -MrNumber 4` と
   `Get-MrUnresolvedComments -MrNumber 4 -IncludeResolved` を実行し、後者の方が件数が多い
   （または既に全件解決済みなら同数）ことを確認する。出力に `threadId=` が含まれることを確認する。
3. **`Add-MrThreadReply` の実機確認**: 取得した実在のthreadIdに対して実際に返信を投稿し、
   GitHub UI（または `gh api graphql` での再取得）で返信が反映されていることを確認する
   （書き込みを伴うため、実行前にユーザーに実行内容を伝える）。
4. **GitLab側**: `glab` 未インストールのため実行確認は行わない（既存の制約と同様）。

## worklog

`worklog/20260815_misty-foraging-torvalds.md` に追記して進める（新規作成しない）。
