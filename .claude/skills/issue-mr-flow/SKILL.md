---
name: issue-mr-flow
description: nagame-ahkの開発フロー全体（issue起票〜マージ）の唯一の実装フロー定義。新機能追加・既存動作の変更など、あらゆるタスクをissue起点で進めるときに使う。issue取得、feature-<issue番号>-<内容>ブランチとDraft MRの作成、レビューコメント取得、MR description更新をサブコマンドで行いつつ、設計ドキュメント作成・plan・実装・設計反映・AIアセット改善までの全ステップをこのファイルが定義する。
---

# issue駆動 開発フロー（唯一の実装フロー定義）

このファイルは `dev-tools/docs/spec/issue-mr-workflow.md` の実装であり、nagame-ahkにおける
**issue起票からマージまでの唯一の実装フロー定義**である。新機能追加・既存動作の変更など、
ごく小さな変更（誤字修正等。`.claude/rules/git-workflow.md` 参照）を除くあらゆるタスクは、
このファイルの手順で進める。

裏側の実処理は `dev-tools/src/vcs/Provider.ps1`（GitHub/GitLabの差異を吸収する共通関数群）に実装されている。
各ステップの手順内で、必要に応じて以下でdot-sourceして使う。

```powershell
. dev-tools\src\vcs\Provider.ps1
```

プロジェクト固有のパス設定（ブランチ命名規則・`plans/` 等の場所）はリポジトリ直下の `.mrworkflow.json`
から読む（`Get-WorkflowConfig`）。他リポジトリへ移植する場合はこのファイルの値を書き換えるだけでよい。

## 全体フロー

担当列: 「人間」＝人間の作業／「サブコマンド」＝下記「サブコマンド」節の `/issue-mr-flow <名前>`／
「エージェント」＝AIエージェントの通常操作（git操作・ファイル編集等）。

| # | ステップ | 担当 |
|---|---|---|
| 1 | issueを起票する（`.github/ISSUE_TEMPLATE/task.md` / `.gitlab/issue_templates/task.md` で目的・現状・期待する動作・受け入れ条件を記載） | 人間 |
| 2 | issueの内容を取得する | `start <issue番号>` |
| 3 | featureブランチ（`feature-<issue番号>-<slug>`）とDraft MRを作成する（既にあれば `sync` のみ） | `start` |
| 4 | Planモードで実行手順を作成する（`plans/` へ出力・コミット。このタイミングで `worklog/日付_<plan名>.md` を作成） | エージェント |
| 5 | Planに合意する | 人間 |
| 6 | commit, push する | エージェント |
| 7 | MRで再度planについてレビュー・コメントする | 人間 |
| 8 | レビュー内容を取得し、planを修正する。対応が完了したコメントには対応内容を返信する（7〜8を合意まで繰り返す） | `comments` / `reply` |
| 9 | planをもとにMR descriptionを更新する | `describe` |
| 10 | コンテキスト削減のためにセッションをcompactする | 人間 |
| 11 | planをもとに作業を進める、作業内容はworklogに更新する | エージェント |
| 12 | commit, push する | エージェント |
| 13 | 作業内容をもとにMR descriptionを更新する | `describe` |
| 14 | MRでレビュー・コメントする | 人間 |
| 15 | レビュー内容を取得し、実装・ドキュメントを修正する。対応が完了したコメントには対応内容を返信する（11〜15の作業ループを合意まで繰り返す） | `comments` / `reply` |
| 16 | 設計反映: `plans/` `worklog/` の内容を `docs/spec/` `docs/ddr/` へ反映する | エージェント |
| 17 | AIアセット改善: 作業中に気づいたルール・スキルの不備があれば `.claude/rules/` `.claude/skills/` `CLAUDE.md` `AGENTS.md` に反映する | エージェント |
| 18 | commit, push する | エージェント |
| 19 | MRでレビュー・コメントする | 人間 |
| 20 | レビュー内容を取得し、設計反映・AIアセットの内容を修正する。対応が完了したコメントには対応内容を返信する（16〜20を合意まで繰り返す） | `comments` / `reply` |
| 21 | `plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする | エージェント |
| 22 | commit, push して Draftを解除する | エージェント |
| 23 | マージする（squash merge。ブランチは削除してよい） | 人間 |

**`start` から着手する場合を除き、このセッションでこのフローのサブコマンドを初めて使う前には、
必ず先に `resume` を実行して「今どこにいるか」を特定する。** `git branch --show-current` 等で
ブランチ名やissue番号が判明していることは、`resume` を省略してよい理由にはならない。`resume` の
目的はブランチ名の特定ではなく、PR/MRの状態・未解決コメント件数・plan/worklogファイル・
HANDOFF.mdとの矛盾など、ブランチ名だけでは分からない「このセッションでまだ確認していない現在地
情報」を集約することにある。
**全体フローの各ステップが進むごとにHANDOFF.mdに現在の状況を反映する**

## サブコマンド

呼び出しは `/issue-mr-flow <サブコマンド> [引数]` の形。

### `start <issue番号>` — issue取得・ブランチ/MR作成（全体フロー2〜3）

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
3. 取得したissue内容をもとに、全体フロー4（Planモードでの実行手順作成）に進む旨をユーザーに案内する。

### `comments [all]` — MRレビューコメントの取得（全体フロー8・15）

1. `Get-MrForBranch -Branch (git branch --show-current)` で現在のブランチに紐づくMR番号を取得する。
2. `Get-MrUnresolvedComments -MrNumber <n>` で未解決コメントを取得し、そのまま提示する
   （ファイルパス・行番号・スレッドID・該当diffを含む）。対応済み（解決済み）のスレッドは既定で
   機械的に除外される。引数に `all` が指定された場合は `-IncludeResolved` を付けて呼び、
   解決済みも含めた全件を取得する。
3. 提示した内容をもとに、`plans/<plan名>.md` を修正する、または設計・実装を修正する
   （この修正作業自体は本スキルの対象外。通常の編集で行う）。対応が完了したコメントには、
   `reply` サブコマンドで対応内容を返信する。

### `reply <threadId> <対応内容>` — レビューコメントへの返信（全体フロー8・15）

1. `Get-MrForBranch -Branch (git branch --show-current)` で現在のブランチに紐づくMR番号を取得する
   （`comments` の手順1と同じ）。
2. 返信本文を組み立てる。**AIエージェントが返信する場合は、本文の先頭に必ず
   `Claude Codeより:` の署名行を付ける。** `gh` / `glab` CLIは人間のアカウントで認証
   されているため、GitHub/GitLab上の投稿者アカウントは人間のものとして表示される。誰が書いた
   返信かをレビュアーが判別できるよう、本文側で明示する（`Add-MrThreadReply` 関数は自由文を
   そのまま渡す設計のため、署名の付与は呼び出し側であるこの手順の責務とする）。
3. `Add-MrThreadReply -MrNumber <n> -ThreadId <threadId> -ReplyBody <署名付きの対応内容>` で、
   指定したスレッドに返信する。`threadId` は `comments` の出力に含まれる `threadId=...` を使う。
4. スレッドの解決（resolved）はレビュアー側の操作であり、本サブコマンドでは行わない。

### `describe` — MR descriptionの更新（全体フロー9・13）

1. 現在のブランチに対応する `plans/<plan名>.md`（と、あれば `worklog/日付_<plan名>.md` の要点）を読む。
2. 以下のテンプレートでMR description本文を組み立て、一時ファイルへ書き出す。

   ```markdown
   Closes #<issue番号>

   ## Plan

   <plans/<plan名>.md の内容、またはその要約>

   ## 実装状況

   <worklogの「うまくいったこと」等から、現時点までの実装内容の要約。plan段階では「未着手」>
   ```

3. `Get-MrForBranch -Branch (git branch --show-current)` で現在のブランチに紐づくMR番号を取得し
   （`comments` の手順1と同じ）、`Set-MrDescription -MrNumber <n> -BodyFile <一時ファイル>` で反映する。

### `sync` — セッション再開（全体フロー3の再開版）

対象ブランチ名を引数に取り、`Sync-Branch -Branch <branch>` を呼ぶだけの単純なコマンド。
引数省略時は現在のブランチ名を使う。`resume` や `start` で既にこのセッションの現在地確認が
済んでいる状態で、ブランチを最新化したいだけの場合に使う。**新しいセッションで最初に使う
サブコマンドとしては使わない**（新しいセッションの最初の一手は必ず `resume` から入る）。

### `resume` — 途中引き継ぎ（引数なし）

このセッションでまだ「今どこにいるか」（issue／ブランチ／PRの、どの段階か）を確認していない
状態で使う。別セッション・別担当者が途中から引き継ぐ場合に限らず、`start` 以外のサブコマンドを
このセッションで初めて使う前は常にここから入る（ブランチ名やissue番号が判明していても対象）。

1. Agentツールで `issue-mr-resume` サブエージェント（`.claude/agents/issue-mr-resume.md`）を起動する。
2. サブエージェントが返す「現在地サマリ」（ブランチ・issue・PR/MR・未解決コメント件数・
   ブランチ固有のplan/worklogファイル・HANDOFF.mdの内容、および矛盾・注意点）をそのまま
   ユーザーに提示する。
3. 提示した内容をもとに、全体フロー23ステップのうちどこから再開すべきかをAIエージェントが判断し、
   次にすべきことを提案する（この判断はサブエージェントではなく呼び出し元が行う）。
4. issue番号が特定できていればブランチ/MRの存在確認へ（`start` 手順2相当）、issueが特定できなければ
   ブランチ命名規則から外れている旨を伝えて `start <issue番号>` での対応を促す。

## レビュー完了合図の確認（全体フロー8・15・20）

人間から「レビューOK」「合意」等、レビューループを終えて次のステップに進んでよいという合図を
受けても、それだけを根拠に次のステップへ進んではいけない。**必ず `comments all`
（`Get-MrUnresolvedComments -IncludeResolved`）でスレッドを再取得し、`unresolved` のスレッドが
残っていないか確認する。**

- 残っていなければ、そのまま次のステップに進む。
- 残っていれば、その旨（対象スレッドと内容）を人間に伝えて再確認を取り、解消されるまで次の
  ステップには進まない（GitHub/GitLabのスレッド解決自体はレビュアー側の操作であり、`reply` は
  解決を行わないため、返信済みでも `unresolved` のまま残ることがある）。

## 詳細ルールへのポインタ

全体フローの各ステップに関わる詳細は、以下の既存ルールを参照する（このファイルは順序立った
フローの定義に専念し、内容の重複は避ける）。

- ドキュメントの置き場所・ライフサイクル（`plans/` `worklog/` `docs/spec/` `docs/ddr/` `HANDOFF.md`）:
  `.claude/rules/docs-workflow.md` の「ドキュメント運用」表
- ブランチ命名規則・squash mergeの方針: `.claude/rules/git-workflow.md`
- AHKコーディング規約・設計ドキュメントの章立て・実装時のコメント作法:
  `.claude/skills/ahk-implement/SKILL.md`, `.claude/rules/ahk-style.md`
- `Provider.ps1`経由のコマンド実行や`Get-Content`等でのテキストファイル読み書き時の文字コード注意事項:
  `.claude/rules/powershell-encoding.md`

## 前提

- `gh` CLI（GitHubの場合）または `glab` CLI（GitLabの場合）がインストール・認証済みであること。
  認証情報自体は各CLIの既存ログイン状態に依存し、本スキル側では管理しない。
- リポジトリ直下に `.mrworkflow.json` があること（無い場合は `dev-tools/src/vcs/Provider.ps1` の
  既定値が使われる）。
- issueは `.github/ISSUE_TEMPLATE/task.md`（GitHub）/ `.gitlab/issue_templates/task.md`（GitLab）の
  テンプレートに沿って「目的・現状・期待する動作・受け入れ条件」を記載しておくことが望ましい
  （必須ではなく、`start` サブコマンドが欠落を警告する）。
