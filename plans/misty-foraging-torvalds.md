# issue駆動MRワークフロー支援の実装

## Context

`dev-tools/docs/spec/issue-mr-workflow.md`（承認済み）に基づき、GitHub/GitLab共通のissue駆動MR
ワークフロー支援（`.claude/skills/issue-mr-flow` ＋ 裏側の `dev-tools/src/vcs/*.ps1`）を実装する。

現状確認（実装前提として記録）:
- `gh` はインストール済み（v2.97.0）だが、このマシンでは **未認証**（`gh auth status` が
  `You are not logged into any GitHub hosts` を返す）。write系操作（ブランチ/MR作成、description
  更新）の実機検証は、ユーザー側で `gh auth login` を済ませた後に行う。
- `glab` は未インストール。設計doc記載どおり、GitLab側は実機検証なしでの実装となる。
- 現在のブランチ `3-開発フローを変える` は本タスク（issue #3 相当）に対応する既存ブランチであり、
  重複してブランチ/MRを新規作成しないよう、write系関数の実機テストは避ける（後述の検証方法参照）。

## 実装内容

### 1. `.mrworkflow.json`（リポジトリ直下）

設計doc記載の初期値をそのまま作成する。

### 2. `dev-tools/src/vcs/Provider.ps1`

- `Get-RepoRoot`: `git rev-parse --show-toplevel` でリポジトリルートを取得。
- `Get-WorkflowConfig`: リポジトリルートの `.mrworkflow.json` を読み込み、`ConvertFrom-Json` で返す
  （ファイルが無い場合は設計doc記載の値をデフォルトとして返す）。
- `Get-Provider`: `git remote get-url origin` のホスト名から `github` / `gitlab` を判定して返す
  （どちらでもなければ例外）。
- 本ファイル冒頭で `Github.ps1` / `Gitlab.ps1` を dot-source する（`$PSScriptRoot` 基準）。
- プロバイダ非依存の共通関数（`New-IssueBranch`, `Sync-Branch`）はここに実装する（git操作のみで
  gh/glabを使わないため）:
  - `New-IssueBranch -IssueNumber -Title`: `.mrworkflow.json` の `branchPrefixTemplate` に
    issue番号・スラッグ化したタイトルを埋め込みブランチ名を作る → `git fetch origin <defaultBaseBranch>`
    → `git switch -c <branch> origin/<defaultBaseBranch>` → `git push -u origin <branch>`。
  - `Sync-Branch -Branch`: `git fetch origin` → ローカルに無ければ `git checkout -b <branch> origin/<branch>`、
    あれば `git checkout <branch>` → `git pull --ff-only`。
- プロバイダ依存の4関数（`Get-Issue`, `New-DraftMergeRequest`, `Get-MrUnresolvedComments`,
  `Set-MrDescription`）は `Get-Provider` の結果に応じて `Github.ps1` / `Gitlab.ps1` 側の
  同名プレフィックス付き関数（例: `GitHub-GetIssue` / `GitLab-GetIssue`）へディスパッチする薄いラッパーとする。

### 3. `dev-tools/src/vcs/Github.ps1`（`gh` CLIラッパー）

- `GitHub-GetIssue -Number`: `gh issue view <n> --json number,title,body,url` をパースし、
  タイトルを英数字・ハイフンへ簡易変換した `Slug` を付与して返す。
- `GitHub-NewDraftMergeRequest -IssueNumber -Branch -BaseBranch`: issueのタイトルを流用し
  `gh pr create --draft --base <base> --head <branch> --title <title> --body "Closes #<n>"` を実行、
  作成されたPR番号を返す。
- `GitHub-GetMrUnresolvedComments -MrNumber`: `gh api graphql` でPRのreview threadsを取得し
  `isResolved:false` のスレッドのコメント本文のみを整形して返す（レビューでないissueコメントは
  常に含める）。
- `GitHub-SetMrDescription -MrNumber -BodyFile`: `gh pr edit <n> --body-file <path>`。

### 4. `dev-tools/src/vcs/Gitlab.ps1`（`glab` CLIラッパー、実機未検証）

- ファイル冒頭に「未検証（このリポジトリのremoteはGitHubのみのため）」旨のコメントを明記する。
- `GitLab-GetIssue -Number`: `glab issue view <n> -F json` 相当をパース。
- `GitLab-NewDraftMergeRequest -IssueNumber -Branch -BaseBranch`: `glab mr create --draft
  --source-branch <branch> --target-branch <base> --title <title> --description "Closes #<n>"`。
- `GitLab-GetMrUnresolvedComments -MrNumber`: `glab api` でdiscussionsを取得し `resolved: false`
  のものを整形。
- `GitLab-SetMrDescription -MrNumber -BodyFile`: `glab mr update <n> --description
  "$(Get-Content -Raw <BodyFile>)"`。

### 5. `.claude/skills/issue-mr-flow/SKILL.md`

`.claude/skills/ahk-implement/SKILL.md` と同じ体裁（frontmatter + 手順書）で、4サブコマンドの
使い方とオーケストレーション手順を記述する。

- `/issue-mr-flow start <issue番号>`: 未着手なら `Get-Issue` → `New-IssueBranch` →
  `New-DraftMergeRequest`。ブランチ/MRが既にあれば `Sync-Branch` のみ行い、issue内容を表示。
  その後は既存の実装フロー（`docs-workflow.md`）のplan作成ステップに進む旨を明記。
- `/issue-mr-flow comments`: 現在のブランチに紐づくMR番号を取得し `Get-MrUnresolvedComments` を
  実行、結果を提示。plan修正は既存フローに従う旨を明記。
- `/issue-mr-flow describe`: 現在の `plans/*.md` / `worklog/*.md` の内容からMR description案を
  組み立て `Set-MrDescription` で反映する（テンプレートも本ファイル内に定義）。
- `/issue-mr-flow sync`: 新しいセッションで再開する際に `Sync-Branch` を呼ぶだけの単純コマンド。

### 6. `dev-tools/docs/README.md`

`spec` 一覧に `issue-mr-workflow.md` へのリンクを追加する。

## 影響範囲（再掲・design docと同一）

新規: `.mrworkflow.json`, `dev-tools/src/vcs/Provider.ps1`, `dev-tools/src/vcs/Github.ps1`,
`dev-tools/src/vcs/Gitlab.ps1`, `.claude/skills/issue-mr-flow/SKILL.md`
変更: `dev-tools/docs/README.md`

## 検証方法

1. **構文チェック**: 各 `.ps1` を `powershell -NoProfile -Command ". <path>"` でdot-sourceし、
   パースエラーが出ないことを確認する（副作用のある関数はこの時点では呼び出さない）。
2. **read系の実機確認（GitHub）**: `gh auth login` 完了後、`Get-Issue -Number 3` を実行し、
   本タスクのissue #3の内容が取得できることを確認する（読み取りのみ、副作用なし）。
3. **write系（`New-IssueBranch` / `New-DraftMergeRequest` / `Set-MrDescription`）**: 現在のブランチが
   既にissue #3向けに存在するため、重複作成を避けてこのセッションでは実行しない。コードレビューと
   引数の妥当性確認に留め、実機確認が必要な場合はユーザー側で別issueを用意して行ってもらう。
4. **GitLab側**: `glab` 未インストールのため実行確認は行わない（設計docの未決定事項どおり）。

## worklog

本plan確定にあわせ `worklog/20260815_misty-foraging-torvalds.md` を作成し、以後の試行錯誤を記録する。

---

## 追加実装: Issueテンプレート標準化（Phase 2）

上記Phase 1（実装済み・未commit）に続く追加要望。`dev-tools/docs/spec/issue-mr-workflow.md`
「Issueテンプレート標準化」節（承認済み）に基づき、issue本文の「目的・現状・期待する動作・
受け入れ条件」4見出しを標準化する。

### Context

issueドリブンのワークフローにおいて、issue本文の情報粒度がまちまちだと `/issue-mr-flow start` で
取得した内容だけでは設計・plan作成に進みにくい。GitHub/GitLab双方のissueテンプレート機能で
4見出しの記入欄を用意し、あわせて `/issue-mr-flow start` 側で見出しの有無を機械的にチェック
（欠けていれば警告するのみで処理は止めない）できるようにする。

### 実装内容

1. **`.github/ISSUE_TEMPLATE/task.md`（新規）**
   - front matter（`name: タスク`, `about: 目的・現状・期待する動作・受け入れ条件を明記して起票する`,
     `title: ''`, `labels: ''`, `assignees: ''`）
   - 本文に `## 目的` `## 現状` `## 期待する動作` `## 受け入れ条件` の4見出しと、
     それぞれ用途を示すHTMLコメント（記入例）を用意する。

2. **`.gitlab/issue_templates/task.md`（新規）**
   - front matter無しで、1と同じ4見出し構成の本文のみ。

3. **`dev-tools/src/vcs/Provider.ps1`（変更）**
   - 標準見出し一覧を `$script:RequiredIssueSections = @("目的", "現状", "期待する動作", "受け入れ条件")`
     として定義。
   - `Test-IssueSections -Body <text>` を追加: `Body` を1行ずつ走査し、`(?m)^##\s*<見出し>\s*$`
     （マルチライン正規表現）にマッチしない見出しを欠落として配列で返す（プロバイダ非依存、
     `Github.ps1` / `Gitlab.ps1` に依存しない）。`Body` が空文字/未設定でも例外を出さない
     （`[AllowEmptyString()]`）。

4. **`.claude/skills/issue-mr-flow/SKILL.md`（変更）**
   - `start` サブコマンドの手順1（`Get-Issue` でissue内容取得）の直後に、
     `Test-IssueSections -Body $issue.Body` を呼び、欠けている見出しがあれば
     「issue本文に以下の見出しがありません: ...」という警告をユーザーに提示するステップを追加する
     （処理は継続する）。

### 影響範囲

新規: `.github/ISSUE_TEMPLATE/task.md`, `.gitlab/issue_templates/task.md`
変更: `dev-tools/src/vcs/Provider.ps1`, `.claude/skills/issue-mr-flow/SKILL.md`

### 検証方法

1. **構文チェック**: `Provider.ps1` を再度dot-sourceし、`Test-IssueSections` が読み込めることを確認する。
2. **単体動作確認**:
   - 4見出しすべて揃った本文 → 欠落なし（空配列）を返すこと。
   - issue #3 の実際の本文（見出し無し）→ 4見出しすべてが欠落として返ること。
3. **テンプレートの目視確認**: `.github/ISSUE_TEMPLATE/task.md` / `.gitlab/issue_templates/task.md` の
   Markdownとして破綻がないこと（見出し・front matterの構文）を確認する。実際にGitHub/GitLab UIの
   テンプレート選択に反映されるかまではこのセッションでは確認しない（pushが必要なため）。

### worklog

既存の `worklog/20260815_misty-foraging-torvalds.md` に追記する形で進める（同一branch・同一plan
ファイルの延長のため、新規worklogは作らない）。
