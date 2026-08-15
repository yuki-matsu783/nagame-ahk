# issue駆動MRワークフロー支援

## 背景・目的

AIエージェント（Claude Code）がissueを起点に開発を進める際、以下の定型作業を毎回人手で組み立てているとコストが高い。

- issueの内容取得
- ブランチ・MR（Pull Request / Merge Request）の作成
- plan〜レビュー往復（人間のコメント取得→plan修正）の繰り返し
- 作業内容に応じたMR descriptionの更新
- reflect（`plans/` `worklog/` の内容を `docs/spec/` `docs/adr/` へ反映）後のクリーンアップ

これをGitHub・GitLabどちらのリポジトリでも同じ手順で回せるように、ステップ単位で呼び出す
Claude Codeスキルと、その裏側でGitHub/GitLabの差異を吸収するスクリプト群を整備する。

既存の実装フロー（[docs-workflow.md](../../../.claude/rules/docs-workflow.md) の「実装フロー（必須）」、
[git-workflow.md](../../../.claude/rules/git-workflow.md)）はそのまま踏襲し、本機能はその起点（issue取得・
ブランチ作成）とMRとのやり取り（description更新・レビューコメント取得）を自動化する薄い層を追加するもの。
plan作成そのもの・設計/実装そのものは、AIエージェントが既存ルールに従って行う（本機能が肩代わりしない）。

## 仕様

### 実行モデル

ユーザー要望どおり、ステップ単位のスラッシュコマンド（Claude Codeスキル）として提供する。
常駐エージェントによる自動ポーリング・自動承認は行わない。各ステップは人間が意図したタイミングで
明示的に呼び出す（「合意まで繰り返す」の終了判定＝レビューを打ち切って次工程に進む判断は、常に人間が行う）。

### コンポーネント構成

```
.mrworkflow.json                    # リポジトリ固有設定（他リポジトリへ移植する際はこれだけ差し替える）
.github/ISSUE_TEMPLATE/
└── task.md                         # GitHub用issueテンプレート（目的・現状・期待する動作・受け入れ条件）
.gitlab/issue_templates/
└── task.md                         # GitLab用issueテンプレート（同上）
dev-tools/src/vcs/
├── Provider.ps1                    # git remote からGitHub/GitLabを判定し、共通関数をディスパッチ
├── Github.ps1                      # gh CLIラッパー
└── Gitlab.ps1                      # glab CLIラッパー
.claude/skills/issue-mr-flow/
└── SKILL.md                        # ステップ実行のオーケストレーション手順書
```

- **`Provider.ps1`**: `git remote get-url origin` のホスト名（`github.com` / `gitlab.*`）でプロバイダを判定し、
  共通インターフェース関数を `Github.ps1` / `Gitlab.ps1` の対応関数へディスパッチする。呼び出し側
  （スキル・他スクリプト）はプロバイダを意識しない。
- **`.mrworkflow.json`**（リポジトリ直下、Git管理下）: ブランチ命名規則やパス（`plans/` 等）など
  プロジェクト固有の値を切り出す。他リポジトリへ移植する場合はこのファイルの値を書き換えるだけで済む
  ようにする。nagame-ahk用の値は以下「設定項目」に記載。
- **`.claude/skills/issue-mr-flow/SKILL.md`**: 現在のブランチ・issue番号・`plans/` `worklog/` の有無・
  MRの有無などから「今どの段階か」を判定し、次に何をすべきかをAIエージェントに指示する。実処理は
  `Provider.ps1` 経由のスクリプト呼び出しに委譲し、plan作成・実装そのものは既存の
  `docs-workflow.md` / `.claude/skills/ahk-implement/SKILL.md` の手順にそのまま乗る。

### 提供関数（`Provider.ps1` 経由の共通インターフェース）

| 関数 | 内容 | GitHub実装 | GitLab実装 |
|---|---|---|---|
| `Get-Issue -Number <n>` | issueのtitle/body/labelsを取得 | `gh issue view` | `glab issue view` |
| `New-IssueBranch -IssueNumber <n> -Title <slug>` | `<branchPrefixTemplate>` に従いブランチを作成しcheckout、リモートpush | `git switch -c` + `git push` | 同左 |
| `New-DraftMergeRequest -IssueNumber <n> -Branch <b> -Title <t>` | issueに紐づくDraft PR/MRを作成（bodyは仮テンプレート、後続の `Set-MrDescription` で上書き前提。`-Title` はissueタイトルをそのまま渡す） | `gh pr create --draft` | `glab mr create --draft` |
| `Get-MrUnresolvedComments -MrNumber <n>` | 未解決のレビューコメント／スレッドを取得しテキストへ整形 | `gh api` (review comments) | `glab api` (discussions) |
| `Set-MrDescription -MrNumber <n> -BodyFile <path>` | PR/MRのdescriptionを指定ファイル内容で上書き | `gh pr edit --body-file` | `glab mr update --description` |
| `Sync-Branch` | 現在のブランチをfetch、必要ならcheckout（新しいセッションでの再開用） | `git fetch` + `git checkout` | 同左 |
| `Test-IssueSections -Body <text>` | issue本文に「目的／現状／期待する動作／受け入れ条件」の4見出しが揃っているか確認し、欠けている見出し名の配列を返す（プロバイダ非依存） | — | — |

### ステップ対応表

ユーザー提示のワークフローと、担当（人間／`/issue-mr-flow <サブコマンド>`／既存ルール）の対応。

| # | ワークフロー上のステップ | 担当 |
|---|---|---|
| 1 | 人間がissueを作る | 人間（GitHub/GitLab UI。issueテンプレートで目的・現状・期待する動作・受け入れ条件を記載） |
| 2 | 新しいセッションでissueの内容を取得する | `/issue-mr-flow start <issue番号>`（`Get-Issue` → `Test-IssueSections` で標準4項目の有無を警告） |
| 3 | issueからMRとブランチを作る（`feature-<issue番号>-内容説明`） | 同上（`New-IssueBranch` → `New-DraftMergeRequest`） |
| 4 | 作成したブランチをfetch, checkout | 同上（新規作成時はそのままcheckout済み。再開時は `Sync-Branch`） |
| 5 | planする | 既存ルール（Claude Codeのplanモード。`plans/` へ出力） |
| 6 | git commit, push | 通常のgit操作（AIエージェントが実行） |
| 7 | MRで人間がレビュー、コメントする | 人間（GitHub/GitLab UI） |
| 8 | MRのレビュー内容を取得し、planを修正する | `/issue-mr-flow comments`（`Get-MrUnresolvedComments`）→ plan修正は既存ルール |
| 9 | 5〜8を合意まで繰り返す | 人間が繰り返し呼び出しを判断 |
| 10 | planをもとにMRのdescriptionを修正する | `/issue-mr-flow describe`（`Set-MrDescription`） |
| 11 | 設計・開発をしてドキュメントや実装を更新する | 既存ルール（`docs-workflow.md` の実装フロー） |
| 12 | git commit, push | 通常のgit操作 |
| 13 | 作業内容をもとにMRのdescriptionを修正する | `/issue-mr-flow describe` |
| 14 | MRで人間がレビュー、コメントする | 人間 |
| 15 | 合意まで13〜14を繰り返す | 人間が繰り返し呼び出しを判断 |
| 16 | plans, worklogsを必要なドキュメントに反映する | 既存ルール（reflect：`docs/spec/` `docs/adr/`） |
| 17 | git commit, push | 通常のgit操作 |
| 18 | MRで人間がレビュー、コメントする | 人間 |
| 19 | 合意まで16〜18を繰り返す | 人間が繰り返し呼び出しを判断 |
| 20 | plan, worklogを削除する | 既存ルール（reflect） |
| 21 | git commit, push | 通常のgit操作 |
| 22 | 人間がマージする | 人間 |

`/issue-mr-flow` のサブコマンドは `start` `comments` `describe` `sync` の4つに絞り、plan作成・実装・reflect
そのものは既存ルール（スキル `ahk-implement` を含む）に委ねる。

### ブランチ命名

`<branchPrefixTemplate>`（既定 `feature-{issue}-{slug}`）に従い、issue番号をそのまま連番として使う
（別途の採番管理はしない）。`{slug}` はissueタイトルを英数字・ハイフンへ簡易変換したもの。

### Issueテンプレート標準化

issue本文の書き方を標準化し、ワークフローの起点（ステップ1・2）の情報の粒度を揃える。人間がissueを
作る際は、以下4項目を見出し（`## `）付きで記載することを標準とする。

- **目的**: このissueで解決したい課題・達成したいこと
- **現状**: 現在の状態・困っていること
- **期待する動作**: 対応後にどうなっていてほしいか
- **受け入れ条件**: このissueが「完了」と判断できる具体的な条件（箇条書き）

これをGitHub/GitLab双方のissueテンプレート機能で起票時に差し込む。

- **`.github/ISSUE_TEMPLATE/task.md`**: GitHubの[Issueテンプレート（Markdown形式）](https://docs.github.com/ja/communities/using-templates-to-encourage-useful-issues-and-pull-requests/manually-creating-a-single-issue-template-for-your-repository)。
  YAML front matter（`name` / `about`）＋4見出しの記入欄で構成する。GitHubのissue作成画面で
  テンプレートとして選択できる。
- **`.gitlab/issue_templates/task.md`**: GitLabの[Description templates](https://docs.gitlab.com/user/project/description_templates/)。
  front matter無しの同内容のMarkdown。GitLabのissue作成画面の「Choose a template」から選択できる。
- どちらもMarkdownテンプレートであり、必須項目としての強制はできない（GitHub Issue Formsの
  ような`required`指定は使わない。見出しごと削除して起票することも可能）。強制ではなく
  「標準の見出しを用意して迷わず書けるようにする」ことが目的。

`/issue-mr-flow start` 側の対応: `Get-Issue` で取得したissue本文に4見出し
（`## 目的` / `## 現状` / `## 期待する動作` / `## 受け入れ条件`）が揃っているかを
`Provider.ps1` の `Test-IssueSections` でチェックし、欠けている見出しがあれば警告として提示する
（処理は止めない。テンプレートを使わず手動で作られた既存issueにも同じチェックが働く）。

## 影響範囲

新規:
- `dev-tools/src/vcs/Provider.ps1`
- `dev-tools/src/vcs/Github.ps1`
- `dev-tools/src/vcs/Gitlab.ps1`
- `.mrworkflow.json`（リポジトリ直下）
- `.claude/skills/issue-mr-flow/SKILL.md`
- `.github/ISSUE_TEMPLATE/task.md`（GitHub用issueテンプレート）
- `.gitlab/issue_templates/task.md`（GitLab用issueテンプレート）
- `dev-tools/docs/spec/issue-mr-workflow.md`（本ドキュメント）

変更:
- `dev-tools/docs/README.md`（本機能のspecへのリンクを追加。reflect時）
- `dev-tools/src/vcs/Provider.ps1`（`Test-IssueSections` 追加）
- `.claude/skills/issue-mr-flow/SKILL.md`（`start` サブコマンドに標準4項目の警告ステップを追加）

## 設定項目

`.mrworkflow.json`（nagame-ahk向けの初期値）

```jsonc
{
  "branchPrefixTemplate": "feature-{issue}-{slug}",
  "defaultBaseBranch": "main",
  "plansDir": "plans",
  "worklogDir": "worklog",
  "specDirs": ["docs/spec", "dev-tools/docs/spec"],
  "adrDirs": ["docs/adr", "dev-tools/docs/adr"]
}
```

## 未決定事項・懸念点

- **gh / glab の導入前提**: 動作確認したこのマシンには `gh` `glab` のどちらもインストールされていない
  ことを確認済み。実装後、README等に導入手順（インストール・`gh auth login` / `glab auth login`）を
  案内する必要がある。認証情報自体はスクリプト側では管理せず、各CLIの既存ログイン状態に依存する。
- **GitLab側の動作未検証**: このリポジトリの実remoteはGitHubのみのため、`Gitlab.ps1` はAPI仕様を
  調べた上での実装となり、実機での動作確認ができない。実装時にGitLab側のテスト方法（別リポジトリ用意等）
  を検討する。
- **issueとMRのリンク方法の統一**: GitHub（`Closes #n` 等のキーワード）とGitLab（`Closes #n` は同様に
  対応、ただしMR説明文の書式作法が異なる）の差異を、`New-DraftMergeRequest` 内でどう統一表現するか。
- **未解決コメントの判定基準**: `Get-MrUnresolvedComments` で「未解決」をどう定義するか（GitHubには
  Draft PRのレビュースレッドresolved/unresolvedの概念があるが、単純なコメントには無い）。GitHub/GitLab
  双方のAPI差異を含め実装時に確定する。
- **他リポジトリへの移植性の検証**: `.mrworkflow.json` による切り出しで足りるか、実際に他リポジトリへ
  導入してみないと確認できない。今回はnagame-ahk上での実装・検証にとどめる。
- **全角文字のみのissueタイトルのスラッグ化**: `ConvertTo-Slug` はASCII英数字のみを残す簡易実装のため、
  「開発フローを変える」のような全角文字のみのタイトルは空文字となり `issue` にフォールバックする
  （実機確認: issue #3 で確認済み）。ブランチ名は `feature-<issue番号>-issue` のように番号のみで
  区別される形になるが、番号自体が一意なため実害はない。より説明的なスラッグが必要になった場合は
  ローマ字変換等の対応を別途検討する。
