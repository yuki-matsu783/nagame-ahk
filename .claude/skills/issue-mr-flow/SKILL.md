---
name: issue-mr-flow
description: GitHub/GitLabのissueを起点に開発を進めるときに使う。issue内容の取得、feature-<issue番号>-<内容>ブランチとDraft MRの作成、MRレビューコメントの取得、plan/worklogをもとにしたMR description更新をステップ単位のサブコマンドで行う。plan作成・実装・reflectそのものは既存の実装フロー（docs-workflow.md, ahk-implement）に委ねる。
---

# issue駆動MRワークフロー支援

このスキルは `dev-tools/docs/spec/issue-mr-workflow.md` の実装であり、`.claude/rules/docs-workflow.md`
の「実装フロー（必須）」・`.claude/rules/git-workflow.md` を置き換えるものではない。issue取得・
ブランチ/MR作成・レビューコメント取得・MR description更新という、フローの「起点」と「MRとのやり取り」
だけを自動化する。plan作成・設計・実装・reflectそのものは既存ルールにそのまま従うこと。

裏側の実処理は `dev-tools/src/vcs/Provider.ps1`（GitHub/GitLabの差異を吸収する共通関数群）に実装されている。
各サブコマンドの手順内で、必要に応じて以下でdot-sourceして使う。

```powershell
. dev-tools\src\vcs\Provider.ps1
```

プロジェクト固有のパス設定（ブランチ命名規則・`plans/` 等の場所）はリポジトリ直下の `.mrworkflow.json`
から読む（`Get-WorkflowConfig`）。他リポジトリへ移植する場合はこのファイルの値を書き換えるだけでよい。

## サブコマンド

呼び出しは `/issue-mr-flow <サブコマンド> [引数]` の形。

### `start <issue番号>` — issue取得・ブランチ/MR作成（ワークフロー手順2〜4）

1. `Get-Issue -Number <issue番号>` でissueのtitle/body/urlを取得し、内容をユーザーに提示する。
   続けて `Test-IssueSections -Body <issue.Body>` を呼び、標準4見出し
   （目的・現状・期待する動作・受け入れ条件。`.github/ISSUE_TEMPLATE/task.md` /
   `.gitlab/issue_templates/task.md` 参照）の過不足を確認する。欠けている見出しがあれば
   「issue本文に以下の見出しがありません: ...」とユーザーに警告する（処理は止めず、そのまま次へ進む）。
2. `.mrworkflow.json` の `branchPrefixTemplate` から算出されるブランチ名
   （既定 `feature-<issue番号>-<slug>`）が既にローカル/リモートに存在するか確認する。
   - 存在しなければ: `New-IssueBranch -IssueNumber <n> -Title <issue.Title>` でブランチを作成・checkout・push、
     続けて `New-DraftMergeRequest -IssueNumber <n> -Branch <branch> -Title <issue.Title>` でDraft MRを作成する。
   - 既に存在すれば（セッション再開）: `Sync-Branch -Branch <branch>` でfetch・checkoutのみ行う。
3. 取得したissue内容をもとに、ここから先は `.claude/rules/docs-workflow.md` の実装フロー（設計ドキュメント
   作成→承認→planモード）に進む旨をユーザーに案内する。

### `comments` — MRレビューコメントの取得（ワークフロー手順8）

1. 現在のブランチに紐づくMR番号を取得する（GitHub: `gh pr view --json number --jq .number`、
   GitLab: `glab mr view --output json --jq .iid`）。
2. `Get-MrUnresolvedComments -MrNumber <n>` で未解決コメントを取得し、そのまま提示する。
3. 提示した内容をもとに、既存の実装フローに従って `plans/<plan名>.md` を修正する（この修正作業自体は
   本スキルの対象外。通常の編集で行う）。

### `describe` — MR descriptionの更新（ワークフロー手順10・13）

1. 現在のブランチに対応する `plans/<plan名>.md`（と、あれば `worklog/日付_<plan名>.md` の要点）を読む。
2. 以下のテンプレートでMR description本文を組み立て、一時ファイルへ書き出す。

   ```markdown
   Closes #<issue番号>

   ## Plan

   <plans/<plan名>.md の内容、またはその要約>

   ## 実装状況

   <worklogの「うまくいったこと」等から、現時点までの実装内容の要約。plan段階では「未着手」>
   ```

3. 現在のブランチに紐づくMR番号を取得し（`comments` の手順1と同じ）、
   `Set-MrDescription -MrNumber <n> -BodyFile <一時ファイル>` で反映する。

### `sync` — セッション再開（ワークフロー手順4の再開版）

新しいセッションで作業を再開するときに使う。対象ブランチ名を引数に取り、
`Sync-Branch -Branch <branch>` を呼ぶだけの単純なコマンド。引数省略時は現在のブランチ名を使う。

## 前提

- `gh` CLI（GitHubの場合）または `glab` CLI（GitLabの場合）がインストール・認証済みであること。
  認証情報自体は各CLIの既存ログイン状態に依存し、本スキル側では管理しない。
- リポジトリ直下に `.mrworkflow.json` があること（無い場合は `dev-tools/src/vcs/Provider.ps1` の
  既定値が使われる）。
- issueは `.github/ISSUE_TEMPLATE/task.md`（GitHub）/ `.gitlab/issue_templates/task.md`（GitLab）の
  テンプレートに沿って「目的・現状・期待する動作・受け入れ条件」を記載しておくことが望ましい
  （必須ではなく、`start` サブコマンドが欠落を警告する）。
