---
title: issue駆動MRワークフロー支援
type: spec
description: AIエージェントがissue起点で開発を進める際の定型作業（issue取得・ブランチ/MR作成・レビュー往復等）を支援する仕組みの仕様
tags: [issue-mr-flow, workflow, spec]
keywords: [provider-sh, github連携, gitlab連携, セッション開始hook, 使用量集計, draft-pr, 途中引き継ぎ]
---

# issue駆動MRワークフロー支援

## 背景・目的

AIエージェント（Claude Code）がissueを起点に開発を進める際、以下の定型作業を毎回人手で組み立てているとコストが高い。

- issueの内容取得
- ブランチ・MR（Pull Request / Merge Request）の作成
- plan〜レビュー往復（人間のコメント取得→plan修正）の繰り返し
- 作業内容に応じたMR descriptionの更新
- 設計反映（`plans/` `worklog/` の内容を `docs/spec/` `docs/ddr/` へ反映）後のクリーンアップ

これをGitHub・GitLabどちらのリポジトリでも同じ手順で回せるように、ステップ単位で呼び出す
Claude Codeスキルと、その裏側でGitHub/GitLabの差異を吸収するスクリプト群を整備する。

当初は「既存の実装フロー（`docs-workflow.md`, `git-workflow.md`）を踏襲し、本機能はその起点と
MRとのやり取りだけを自動化する薄い層」として設計したが、PR #4のレビューを経て方針を変更した。
`docs-workflow.md` の「実装フロー（必須）」と `git-workflow.md` の手順（ブランチ運用・worklogと
設計反映・PR・マージ）の**順序立ったフロー部分**を `.claude/skills/issue-mr-flow/SKILL.md` に統合し、
そちらを**唯一の実装フロー定義**とした。今後はごく小さな変更を除くあらゆるタスクをissue起点で
進める前提とする。`docs-workflow.md` / `git-workflow.md` はドキュメントの置き場所・ライフサイクルや
ブランチ命名規則といった参照情報のみを残す。詳細は
[.claude/scripts/docs/ddr/0002-issue-mr-flowへの実装フロー統合.md](../ddr/0002-issue-mr-flowへの実装フロー統合.md) 参照。

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
.claude/scripts/src/vcs/
├── Provider.sh                     # git remote からGitHub/GitLabを判定し、共通関数をディスパッチ
├── Github.sh                       # gh CLIラッパー
└── Gitlab.sh                       # glab CLIラッパー
.claude/skills/issue-mr-flow/
└── SKILL.md                        # ステップ実行のオーケストレーション手順書
.claude/agents/
└── issue-mr-resume.md              # 途中引き継ぎ用の状態調査サブエージェント（resumeから起動）
.claude/hooks/
├── session-start.sh                 # セッション開始時のissue/MR状態自動注入（SessionStart hook）
├── post-push-usage-report.sh        # git push検知時のトークン使用量集計＋MR自動コメント投稿（PostToolUse hook）
├── post-push-compact-prompt.sh      # git push検知時に/compact実施を促すメッセージ注入（PostToolUse hook）
└── lib/
    └── UsageTracking.sh              # 集計ロジック（sync_usage_state）
```

上記は全てbash製（`.sh`）。issue #6でPowerShell版（`.ps1`）から移行し、issue #24で
`dev-tools/`（AI・人間共用の開発補助ツール置き場）から`.claude/scripts/`（AI専用スクリプト置き場）へ
移動した。設計方針・移行の経緯・git bash特有の注意点は [shell-scripts.md](shell-scripts.md) を参照。

- **`Provider.sh`**: `git remote get-url origin` のホスト名（`github.com` / `gitlab.*`）でプロバイダを判定し、
  共通インターフェース関数を `Github.sh` / `Gitlab.sh` の対応関数へディスパッチする。呼び出し側
  （スキル・他スクリプト）はプロバイダを意識しない。関数はJSON文字列をstdoutへ出力し、呼び出し側は
  `jq` でフィールドを取り出す設計（例: `get_issue 6 | jq -r '.title'`）。
- **`.mrworkflow.json`**（リポジトリ直下、Git管理下）: ブランチ命名規則やパス（`plans/` 等）など
  プロジェクト固有の値を切り出す。他リポジトリへ移植する場合はこのファイルの値を書き換えるだけで済む
  ようにする。nagame-ahk用の値は以下「設定項目」に記載。
- **`.claude/skills/issue-mr-flow/SKILL.md`**: issue起票からマージまでの**唯一の実装フロー定義**。
  現在のブランチ・issue番号・`plans/` `worklog/` の有無・MRの有無などから「今どの段階か」を判定し、
  次に何をすべきかをAIエージェントに指示する。実処理は `Provider.sh` 経由のスクリプト呼び出しに
  委譲し、設計ドキュメント作成・plan作成・実装の詳細手順（AHK機能実装の場合）は
  `.claude/skills/ahk-implement/SKILL.md` に委ねる。

### 提供関数（`Provider.sh` 経由の共通インターフェース）

| 関数 | 内容 | GitHub実装 | GitLab実装 |
|---|---|---|---|
| `get_issue <n>` | issueのtitle/body/labelsを取得（JSON） | `gh issue view` | `glab issue view` |
| `new_issue_branch <n> <slugSource>` | `<branchPrefixTemplate>` に従いブランチを作成しcheckout、リモートpush。`<slugSource>` はslug化対象のテキストであり、生issueタイトルである必要はない（`.claude/skills/issue-mr-flow/SKILL.md` の `start` サブコマンドではAIエージェントが生成した英語の意訳フレーズを渡す。詳細: [0010-ブランチslugの意訳生成はAIエージェントが行う.md](../ddr/0010-ブランチslugの意訳生成はAIエージェントが行う.md)） | `git switch -c` + `git push` | 同左 |
| `new_draft_merge_request <n> <branch> <title> [<base>]` | issueに紐づくDraft PR/MRを作成（bodyは仮テンプレート、後続の `set_mr_description` で上書き前提。`<title>` はissueタイトルをそのまま渡す） | `gh pr create --draft` | `glab mr create --draft` |
| `get_mr_unresolved_comments <n> [true]` | レビューコメント／スレッドを取得しテキストへ整形（スレッドID・ファイルパス・行番号・diffを含む）。既定（第2引数省略）では未解決のスレッドのみを返し、対応済み（解決済み）スレッドは機械的に除外する。第2引数に `true` を渡すと解決済みも含めた全件を返す | `gh api graphql` (review threads) | `glab api` (discussions) |
| `add_mr_thread_reply <n> <threadId> <text>` | 指定スレッドに対応内容を返信する（スレッドの解決＝resolvedはレビュアー側の操作のため本関数では行わない） | `gh api graphql`（reply mutation） | `glab api`（note追加） |
| `set_mr_description <n> <bodyFile>` | PR/MRのdescriptionを指定ファイル内容で上書き | `gh pr edit --body-file` | `glab mr update --description` |
| `add_mr_comment <n> <bodyFile>` | PR/MRへ新規コメントを1件投稿（スレッド返信・レビューではない通常コメント） | `gh pr comment --body-file` | `glab mr note --message` |
| `sync_branch <branch>` | 現在のブランチをfetch、必要ならcheckout（新しいセッションでの再開用） | `git fetch` + `git checkout` | 同左 |
| `test_issue_sections <body>` | issue本文に「目的／現状／期待する動作／受け入れ条件」の4見出しが揃っているか確認し、欠けている見出し名を1行1件でstdoutへ出力する（プロバイダ非依存） | — | — |
| `get_issue_number_from_branch [<branch>]` | ブランチ名を `branchPrefixTemplate` に照らしてissue番号を抽出する（省略時は現在のブランチ）。マッチすればstdoutへ出力し終了コード0、マッチしなければ終了コード1（プロバイダ非依存） | — | — |
| `get_mr_for_branch <branch>` | 指定ブランチに紐づくPR/MRの番号・URL・タイトル・Draft状態を取得する（JSON。無ければ何も出力せず終了コード0） | `gh pr view <branch>` | `glab mr view <branch>` |
| `get_branch_work_files` | 現在のブランチ固有（`<defaultBaseBranch>` に無い）の `plans/` `worklog/` ファイル一覧を返す（プロバイダ非依存） | — | — |
| `build_issue_body <purpose> <current> <expected> <acceptance>` | 標準4見出し（目的・現状・期待する動作・受け入れ条件）に沿ってissue本文を組み立てる（プロバイダ非依存。issue #25） | — | — |
| `new_issue <title> <body>` | タイトル・本文からissueを新規作成し、`get_issue`と同じ形（number/title/body/url/slug）のJSONを返す（issue #25） | `gh issue create` → URLから番号抽出 → `github_get_issue` | `glab issue create` → URLから番号抽出 → `gitlab_get_issue` |

### 全体フロー

issue起票からマージまでの詳細な手順（担当・順序）は
[.claude/skills/issue-mr-flow/SKILL.md](../../../.claude/skills/issue-mr-flow/SKILL.md)（唯一の実装フロー定義）
に一本化した。本specとの内容重複・ドリフトを避けるため、ここでは表を持たない
（詳細は[0002-issue-mr-flowへの実装フロー統合.md](../ddr/0002-issue-mr-flowへの実装フロー統合.md)参照）。

`/issue-mr-flow` のサブコマンドは `start` `comments` `reply` `describe` `sync` `resume` の6つに絞り、
設計ドキュメント作成・plan作成・実装・設計反映・AIアセット改善そのものは
`.claude/skills/issue-mr-flow/SKILL.md` の該当ステップ（スキル `ahk-implement` を含む）に委ねる。

### レビューコメントへの返信

対応が完了したレビューコメントに対して、対応内容を返信する。スレッドの解決（resolved）は
レビュアー側が行う操作のため、本機能では行わない。

- `add_mr_thread_reply <n> <threadId> <text>` で、指定スレッドへ対応内容を
  返信する。`threadId` は `get_mr_unresolved_comments` の出力に含まれるスレッドIDを使う。
- `get_mr_unresolved_comments` は既定（第2引数省略）で未解決スレッドのみを返す（レビュアーが
  解決済みにしたものは機械的に除外される）。再確認等で解決済みも含めた全件が必要な場合は
  第2引数に `true` を指定する。
- `/issue-mr-flow` 側では、`comments` サブコマンドに `all` 引数を追加して `true` を
  指定できるようにし、対応完了時に呼ぶ `reply <threadId> <対応内容>` サブコマンドを新設する。
- **完了合図の確認**: 人間から「レビューOK」等の完了合図を受けても、それだけを根拠に次のステップへ
  進まない。`comments all`（`get_mr_unresolved_comments <n> true`）で全スレッドを再取得し、`unresolved` が残っていれば
  人間に再確認を取ってから次に進む（`reply` は返信のみで解決は行わないため、返信済みでも
  `unresolved` のまま残ることがある）。詳細は `.claude/skills/issue-mr-flow/SKILL.md` の
  「レビュー完了合図の確認」節を参照。

### 途中引き継ぎ対応（resume）

`start <issue番号>` / `sync <branch>` はどちらも「このセッションで既に現在地確認が済んでいる」
ことが前提のコマンドであり、別の人（別セッション）が途中から作業を引き継ぐ場合、AIエージェント
自身が「今どのissue／ブランチ／PRの、どの段階か」を特定する手段が無かった（PR #4レビュー指摘）。
`git branch --show-current` でブランチ名自体は機械的に取得できてしまうため、「情報の既知・未知」
を発動条件にすると読み手によって解釈がぶれる（実際に、ブランチ名が判明していることを理由に
resumeを省略してしまう事故が発生した）。そのため発動条件は「このセッションで現在地確認
（`resume`/`start`）を済ませたか」という機械的な基準で判定する。

`resume`（引数なし）は、専用サブエージェント `.claude/agents/issue-mr-resume.md` を起動し、
現在チェックアウトされているブランチだけを手がかりに以下を機械的に収集・報告させる
（情報収集・突き合わせは調査作業であり、その過程（試行錯誤・大量の生ログ）でメイン会話の
コンテキストを汚さないよう、読み取り専用の別エージェントに分離する）。

1. `git branch --show-current` で現在のブランチ名を取得する（`<defaultBaseBranch>` 上、または
   ブランチが特定できない場合は、その旨を伝えて `start <issue番号>` を促し終了する）。
2. `get_issue_number_from_branch` でブランチ名からissue番号を抽出し、`get_issue` でissue内容を取得する
   （抽出できなければ「命名規則に一致しないブランチです」と警告しつつ以降を続行する）。
3. `get_mr_for_branch` で対応するPR/MRの有無・番号・URL・Draft状態を取得する。
4. PR/MRがあれば `get_mr_unresolved_comments <n> true` で全件取得し、未解決件数を集計する。
5. `get_branch_work_files` で、このブランチ固有の `plans/` `worklog/` ファイルを列挙する
   （`<defaultBaseBranch>` との差分から求めるため、削除済み＝設計反映済みの判別にも使える）。
6. `HANDOFF.md` の内容を読む。
7. 1〜6を「現在地サマリ」としてまとめ、呼び出し元（メインのAIエージェント）に返す。**HANDOFF.mdの
   記述と実際の状態（PR有無・未解決コメント件数等）に矛盾があれば、それも指摘する**
   （例: HANDOFF.mdは「PR未作成」と書いてあるが実際はPRが存在する、等）。

呼び出し元は、このサマリをもとに全体フロー33ステップのうちどこから再開すべきかを判断し、
人間に提案する（この判断自体はサブエージェントの役割ではなく、呼び出し元が行う）。

`comments` / `describe` サブコマンドの「現在のブランチに紐づくMR番号を取得する」手順は、
重複実装を避けるため `get_mr_for_branch` に統一する。

### マージ後の取り残しクリーンアップ

人間がレビュー後にそのままMR/PRをマージするなど、flow-id 31（`plans/` `worklog/`の削除・
`HANDOFF.md`のリセット）の実施前にマージが完了してしまうことがある（issue #28, PR #29の
セッションで実際に発生）。この場合、タスク固有の`plans/`・`worklog/`ファイルと作業途中のままの
`HANDOFF.md`が`main`へ残ってしまい、`docs-workflow.md`の運用（`worklog/`はsquash mergeで
`main`に残さない設計）と矛盾する。

この状態に気づいた場合、`main`への直接コミットではなく、新しいクリーンアップ用ブランチと
PRで対処する（`main`はレビューを経ないままの直接変更を避ける対象のため）。issue番号を持たない
一回限りの対応のため、`.mrworkflow.json`のブランチ命名規則には従わず`chore/cleanup-<説明>`
のような名前を使ってよい。手順の詳細は
`.claude/skills/issue-mr-flow/SKILL.md`の「PRがflow-id 31実施前にマージされてしまった場合の対処」
節を参照。

### セッション開始時の自動コンテキスト注入（SessionStart hook）

`resume` は人間・AIエージェントが明示的に呼び出す必要があり、機械的に実行されない
（issue #5指摘）。これをClaude CodeのSessionStart hookとして自動化し、セッション開始・
resume・clear時に毎回、現在ブランチのissue/MR状態をコンテキストへ自動注入する。

- **コンポーネント**: `.claude/hooks/session-start.sh`（bash版。issue #6でPowerShell版から移行）＋
  `.claude/settings.json` の `hooks.SessionStart` 設定。
- **matcher**: `startup|resume|clear` に限定する。`compact`（コンテキスト圧縮のたびに`gh` API
  呼び出しが走るのを避ける）と `fork`（今回はスコープ外）は対象外とする。
- **実行シェル**: exec form（`args`指定）で `"bash"` を呼ぶ（フルパス直書きはしない。他環境への
  移植性を優先）。ただしこのマシンではPATHの優先順位次第で素の`"bash"`がWSL起動用スタブ
  （`C:\Windows\System32\bash.exe`）に解決されてしまうため、システム環境変数（`Machine`スコープ）
  の`Path`へgit bashの`bin`をSystem32より前に来る位置で追加するセットアップが別途必要
  （ユーザー環境変数に追加するだけでは効果が無い。詳細:
  [shell-scripts.md](shell-scripts.md)「Claude Code hookの起動コマンド」）。
- **サブエージェントでの抑止**: 公式ドキュメント上、SessionStart hookはTask tool経由の
  サブエージェント内でも発火する（`agent_id`/`agent_type`がstdin JSONに追加される場合のみ
  判別可能）。そのためmatcherでは実現できず、スクリプト冒頭でstdinの`agent_id`の有無を見て
  即終了する実装とした（受け入れ条件「サブエージェント起動時には実行されず」に対応）。
- **情報収集**: `resume`（`issue-mr-resume`サブエージェント）と同じ`Provider.sh`の関数
  （`get_issue_number_from_branch` / `get_issue` / `get_mr_for_branch` / `get_mr_unresolved_comments`）を
  再利用する。hookはサブエージェントを起動できないため、同種の情報収集ロジックを持つ独立スクリプト
  として実装した。表示内容は「ブランチ／issue／PR（Draft状態含む）／未解決レビューコメント件数」に
  絞り、`get_branch_work_files`によるplan/worklogファイル一覧や`HANDOFF.md`の内容表示は含めない
  （それらは`resume`の役割のまま維持し、hookは軽量な自動通知に留める）。
- **出力形式**: `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<text>"}}`
  形式のJSONをstdoutへ返す。
- **フォールバック方針**: `main`ブランチ上（作業ブランチ未チェックアウト）では注入しない。
  `gh`未認証・API失敗等、情報収集に失敗した場合もセッション開始をブロックせず、短い失敗メッセージ
  のみを返す（best-effort。詳細な原因調査は人間が手動で行う）。

### Draft PR作成失敗時の自動リトライ

`new_draft_merge_request` は `new_issue_branch` 直後（baseとの差分がまだ無い状態）で呼ぶと
`gh pr create` / `glab mr create` が失敗する既知の制約があった。コマンドの失敗を検知した
場合、共通処理 `add_empty_commit_for_draft_mr`（空コミット+push）を実行してから1回だけ自動リトライする
（それでも失敗すればエラーを返す）。詳細・却下案は
[0005-DraftPR作成失敗時は空コミットで自動リトライする.md](../ddr/0005-DraftPR作成失敗時は空コミットで自動リトライする.md)
参照。

### 対応工数レポート（PostToolUse hook, git push検知）

issue #15「作業にかかったトークンなどの情報をMRのコメントに記載する」への対応として、
Claude Codeの対応工数（モデル別トークン数・ツール実行回数・assistant応答回数・稼働時間）をMRへ
自動投稿する。issue #28で、稼働時間（かかった時間）の記録・表示を追加した。

- **投稿トリガー**: `git push` 成功時に、前回投稿からの差分をMRへ新規コメントとして投稿する
  （毎ターン投稿やコメントのupsertではない）。
- **記録範囲**: モデル別トークン数（input/output/cache write/cache read。**既知の過小カウント要因
  あり**。詳細は「未決定事項・懸念点」参照）＋ツール実行回数＋assistant応答回数＋稼働時間
  （`activeSeconds`。下記「稼働時間の算出方法」参照）＋skill呼び出し・Agent呼び出し・
  ユーザーへの質問の詳細テーブル（issue #37で追加。下記「呼び出し・質問の詳細記録」参照）。
  推定コスト(USD)・ファイルdiff・プロンプト本文（Agent呼び出しの`prompt`列を除く）は対象外。
  - **ツール実行回数は「実際に呼び出されたツールの集計」であり、利用可能な全ツール種別の固定
    カタログではない**（PR #29レビュー指摘）。[ツールリファレンス](https://code.claude.com/docs/en/tools-reference)
    に載っている多数のツールのうち、そのpush間隔で一度も呼び出されなかったツールは単純に
    行として現れない（0件のツールを列挙する設計にはしていない。トークン数のモデル別テーブルで
    全項目0の行を表示しないようにした対応と同じ考え方）。
  - **直接の子（depth 1）サブエージェント（`Task`/`Agent`ツール等で起動される別セッション）の
    使用量は別集計として反映する**（PR #29レビュー指摘。当初は対象外としていたが後日追加対応した。
    詳細は下記「サブエージェントの使用量記録」参照）。サブエージェントがさらに起動するネストした
    サブエージェント（depth 2以降）は対象外。
- **稼働時間の算出方法（gapベースのidle検出＋tail buffer）**: 単純な「セッション開始〜最終メッセージ」
  の経過時間では、`AskUserQuestion`等での人間の回答待ちや応答終了後の次指示待ちのような
  「作業していない時間」を含んでしまう（PR #29レビュー指摘）。同種の課題を扱う参考実装
  （`claude-work-timer`, `claude-code-time-tracking`。いずれもClaude Code transcriptから実働時間を
  算出するOSS）を調査し、共通して採用されている「gapベースのidle検出＋セグメント末尾のtail buffer」
  方式を採用した。
  - `IDLE_GAP_THRESHOLD_SECONDS`（既定300秒=5分）: 集計対象entry（`gitBranch`一致・assistant）を
    時系列順に走査し、直前entryとの`.timestamp`差（gap）がこの閾値**未満**なら稼働時間へそのまま
    加算する。閾値**以上**（ちょうど閾値も含む）のgapは「人間の入力待ち」とみなし、gap自体は
    加算しない（区間＝セグメントが1つ閉じる）。
  - `TAIL_BUFFER_SECONDS`（既定30秒。`claude-work-timer`の既定値を踏襲）: セグメントが閉じるたびに
    末尾へこの秒数を加算する（応答を読む・確認する等、次のgapとしては現れない実作業時間の補完）。
    走査完了時点で、集計対象entryが1件以上あれば「現在末尾の（まだ閉じていない）セグメント」に対し
    同様に1回加算する。これにより、entryが1件しかないセッションでも稼働時間が0にならない。
    - この「末尾セグメントの暫定クローズ」による加算は、次回pushで同じセッションのtranscriptが
      伸びて再集計されると「実際のgap＋新しい末尾へのtail buffer」に置き換わる。置き換え後の値は
      常に元の値以上になるため、`activeSeconds`（セッション開始からの累計稼働秒数）は再集計を
      繰り返しても単調非減少であり続け、既存の累計差分パターン（後述）に影響しない。
  - **`fromdateiso8601`は使わない**（開発機のjq（Windowsネイティブ版jq 1.6）が`strptime`/`mktime`を
    実装しておらず`strptime/1 not implemented on this platform`で失敗するため。実機確認済み）。
    代わりに`strptime`/`mktime`に依存しない自前実装（`days_from_civil`アルゴリズムによる
    四則演算のみのISO8601→epoch秒変換、`UsageTracking.sh`の`epoch_from_iso8601`）を使う。
    一般的な注意事項として`.claude/rules/shell-script-style.md`「JSON操作」節にも追記した。
  - **既知の制約（目安であることの根拠）**: 閾値未満の短い待機（人間がすぐ返信した場合等）は
    稼働時間に混入しうる、閾値以上の長時間ツール実行（大きめのビルド等）は稼働時間から漏れうる、
    tail bufferは固定値のため実際の読了時間との過不足がありうる。「目安」である旨をレポート・
    このドキュメントに明記する（既存のトークン集計と同じ扱い）。
  - **`activeSeconds`は、issue #37で他フィールドが新規行diff方式（後述）へ移行した後も、
    唯一「累計値 - 前回スナップショット」という差分計算方式のまま残っている**（`current -
    prevSession値`、前回スナップショット無しなら`current - 0`、下限0）。セッションごとの永続状態
    （`sessions[<sessionId>]`）には`lastActiveSeconds`のみを保存する（`turns`等、他フィールドの
    旧スナップショット`lastTokens`/`lastTools`/`lastAssistantCount`はissue #37で新規行diff方式へ
    移行したのに伴い不要になり削除した）。
  - 複数セッション・複数プロジェクトが同時進行した場合の区間重複除去（overlap dedup。参考実装が
    持つ機能）は、本対応のスコープ外（単一ブランチ・単一セッションの範囲で完結する対応工数レポート
    のため）。将来必要になった場合に別issueで検討する。
- **サブエージェントの使用量記録**（PR #29レビュー指摘）: `Task`/`Agent`ツール等で起動される
  サブエージェント（直接の子、depth 1）のトークン・ツール使用量を、メインセッションとは独立した
  レポートセクションとして記録する。
  - **発見方法**: 実機調査により、サブエージェントを起動したセッションでは、メインtranscript
    （`<sessionId>.jsonl`）と同階層に**同名ディレクトリ**（`<sessionId>/`）が作られ、その中の
    `subagents/agent-<agentId>.jsonl`（＋同名`.meta.json`。`agentType`等を含む）にメインtranscript
    と同一スキーマ（`type`, `gitBranch`, `message.usage`, `message.content[].type=="tool_use"`,
    `timestamp`）でサブエージェントの活動が記録されていることを確認した。`${transcript_path%.jsonl}/subagents/`
    を列挙することで発見する。
  - **session-logsローカルコピー方式**（PR #29レビュー指摘）: 集計対象を毎回`~/.claude/projects`
    配下の外部パスから直接読むのではなく、`git push`検知のたびにメイン・サブエージェント両方の
    transcriptを`usage/session-logs/<safeBranch>/<sessionId>/`（gitignore対象）へコピーしてから、
    そのローカルコピーを対象に集計する。`~/.claude/projects`という非公開・ユーザープロファイル配下の
    揮発性のあるパスへ直接依存し続けるのを避け、pushのたびにリポジトリ内へスナップショットを
    退避しておくことで、調査・デバッグ時に状態ファイル（`usage/state/`）と同じ場所で
    生ログを参照できるようにする狙い。
  - **`usage/`ディレクトリへの移設**（issue #37）: `session-logs`/状態ファイルは元々`.claude/`配下
    （`.claude/session-logs/`, `.claude/usage-state/`）に置いていたが、`.claude/`はAIエージェント
    自体の設定・ルール置き場という性格が強く、対応工数レポートのローカル作業状態を置くのは
    筋が悪いという指摘を受け、プロジェクトルート直下の新規`usage/`ディレクトリ
    （`usage/session-logs/`, `usage/state/`）へ移設した。`.gitignore`も旧2行から`/usage/`1行へ統合。
  - **行オフセットベースの差分パースへの移行（issue #37）**: 当初（PR #29時点）は「全件再パース＋
    スナップショット差分方式そのものは変更しない」（`activeSeconds`のgapベースtail buffer計算・
    単調性保証が「毎回全件を時系列で走査し直す」ことを前提にしており、オフセット方式にすると
    単調性証明が崩れるリスクが大きいと判断したため）としていたが、issue #37でこの判断を一部覆した。
    詳細は下記「新規行diff方式への移行（issue #37）」および
    [DDR 0006の追記](../ddr/0006-対応工数レポートはtranscript自前パースで実装する.md)を参照。
  - **`agentId`単位のスナップショット・表示**（issue #34で変更）: 累計スナップショットは`agentId`
    単位で状態ファイルの`agents[<agentId>]`に保存し、既存の`sessions[<sessionId>]`と全く同じ
    「current - prevSnapshot（下限0）」ロジックを適用する（バックグラウンドで複数pushをまたいで
    追記され続けるサブエージェントがあっても二重計上・過小計上が起きない）。
    `sinceLastPush.subagents[<agentId>]`も同じく`agentId`単位で差分を保持し、レポートにも
    `agentId`ごとに1行を表示する。
    - **当初は`agentType`単位で合算していたが、issue #34で`agentId`単位（起動したagentごとに1行）
      へ変更した**: 同じ`agentType`（例: `Explore`）を複数回起動した場合に合算されてしまい、
      「どのagentがどれだけ使ったか」が見えないというフィードバックを受けたため。`agents[<agentId>]`・
      `sinceLastPush.subagents[<agentId>]`のいずれにも、表示ラベル用に`agentType`と`description`
      （`meta.json`の`description`フィールド。サブエージェント起動時の説明文）を付与して保存する。
    - **差分0のagentはレポートに表示しない**（issue #34の追加指示）: `_usage_filter_nonzero_subagents`
      で、`tokensByModel`・`toolCalls`・`activeSeconds`のいずれも差分0のagentIdをレポート表示直前に
      除外する（表示用フィルタであり、状態ファイル側の`agents`/`sinceLastPush.subagents`自体からは
      削除しない）。同じ考え方で、ツール実行回数の集計（メイン・サブエージェント双方）も差分0の
      ツールはキーごと表示しないようにしている（元々「記録範囲」節で意図していた挙動だが、
      `_usage_merge_state`のtoolCalls集計が過去に一度でも使われたツールなら差分0でもキーを作る
      実装だったため、意図通りに動いていなかった不具合がissue #34で見つかり修正した）。
  - **稼働時間はメインの「対応工数」行には合算しない**: サブエージェント自身のgapベース稼働時間は
    メインの`activeSeconds`とは別集計とし、レポートには参考値として別行で表示する（Taskツールの
    完了待ち区間とサブエージェント内の稼働区間が重複しうるため、単純合算するとwall clock時間より
    過大になりうる。この重複除去自体は未対応、詳細は「未決定事項・懸念点」参照）。
  - **ネストしたサブエージェント（depth 2以降）は対象外**: `meta.json`に`spawnDepth`フィールドが
    存在し理論上ネストがありうるが、実データでは`depth 1`のみ観測され、ネスト時のディレクトリ構造・
    スキーマも未確認のため対象外とした。
- **新規行diff方式への移行（issue #37）**: 「利用したツール数が明らかにずれている」という報告を
  受け、原因調査（実データのjq調査）で、同一セッションが複数回・複数ブランチにわたってresumeされると
  transcript JSONL上に同一行が複数回（異なる`gitBranch`ラベル付きで）出現することを確認した。
  従来の「毎回全件を再パースし、前回累計との差分（引き算）を計上する」方式では、セッションが
  新しいブランチで初めてpushされた際に前回スナップショットが存在せず、蓄積済みの全件がその新
  ブランチの初回差分として計上されてしまう不具合があった。
  - **採用方針**: `tokens`/`tools`/`turns`（assistant応答回数）/`skillCalls`/`agentCalls`/
    `askUserQuestions`は、**セッション単位でグローバルなカーソル**
    （`usage/state/session-cursors/<sessionId>.json`の`lastLineCount`。サブエージェントは
    `<agentId>.json`）が指す「前回処理済み行数以降の新規行のみ」を対象に集計し、そのまま
    `sinceLastPush`へ**単純加算**する（引き算方式は廃止）。カーソルは**ブランチに紐付けず**
    セッション単位で管理するため、セッションが別ブランチへresumeされても取りこぼし・二重計上が
    起きない。新規行が無ければ、session-logsへのコピー・状態更新自体をスキップする
    （issue本文が当初提案していた「差分がなければコピーしない」設計）。
  - **意図的に行わないこと（既知の限界）**: この方式は行の中身（重複かどうか・どの`gitBranch`
    ラベルが「正しい」か）を一切詮索せず、「一度数えた範囲は二度と数え直さない」という機械的な
    原則だけで動く。そのため、**resumeによってtranscript行が新しい物理位置に再度書き出された
    場合、その重複行自体は「新規行」としてそのまま計上されうる**（内容が重複していることを
    検出して除外する仕組みではない）。カーソル方式が確実に防ぐのは「同じ行を同じ位置から二重に
    読むこと」のみである。設計判断の経緯（uuidベースの重複排除案を検討したが、`uuid`は
    `parentUuid`チェーン上のノード識別子であり重複自体は異常ではないという判断で不採用とした
    こと）はDDR 0006の追記を参照。
  - **`activeSeconds`のみ従来方式を維持**: 上記「稼働時間の算出方法」に記載の通り、
    `activeSeconds`はgapベースの単調非減少性が「毎回全件を時系列で走査し直す」ことを前提にして
    いるため、新規行diffには移行せず、既存の全件再パース＋スナップショット差分方式のまま維持した。
    1回のpushで「新規行diffの集計」と「全件再パースによる`activeSeconds`算出」の両方を行う
    ハイブリッド構成になる。
- **呼び出し・質問の詳細記録**（issue #37）: 上記の新規行diff方式への移行と合わせて、
  メインセッションのtranscriptの新規行から以下3種の詳細情報を抽出し、`sinceLastPush`へ配列として
  追記する（サブエージェント自身が呼び出した分・ネストしたサブエージェントは対象外）。
  - `skillCalls`: `Skill` tool_useブロックから`{id, skill, args}`を抽出する。
  - `agentCalls`: `Agent` tool_useブロックから`{id, subagentType, description, prompt}`を抽出する
    （呼び出し時点の記録であり、対応するサブエージェントが完了しているかどうかは問わない。
    上記「サブエージェントの使用量記録」＝トークン/稼働時間の実績テーブルとは別集計）。
  - `askUserQuestions`: `type=="user"`エントリのtool_result本文（`"Your questions have been
    answered: \"Q\"=\"A\", ..."`形式。実データで確認済み）から、`"([^"]*)"="([^"]*)"`パターンで
    質問=回答ペアを正規表現抽出する。質問・回答の文字列自体にこのパターンと一致する部分文字列が
    含まれる場合は誤抽出しうる既知の制約（レアケースとして許容）。
  - レポートには、各配列が1件以上ある場合のみ「### skill呼び出し」「### Agent呼び出し」
    「### ユーザーへの質問」のテーブルとして表示する（0件セクションは表示しない、既存の
    トークンテーブル・ツール実行回数と同じ方針）。各セルはパイプ（`|`）をエスケープし改行は
    半角スペースへ変換する（表が崩れないようにするため。`description`列と同じ扱い）。
    `agentCalls`の`prompt`列は長文になりうるため300文字を超える場合は末尾を`…`で省略する。
- **コンポーネント**:
  - `.claude/hooks/lib/UsageTracking.sh`（共有ライブラリ、bash版。issue #6でPowerShell版から移行。
    issue #37で新規行diff方式へ全面的に書き換え）:
    `sync_usage_state <repoRoot> <branch> <sessionId> <transcriptPath>` が集計本体。まず
    `_usage_read_cursor`でセッション横断カーソル（`usage/state/session-cursors/<sessionId>.json`の
    `lastLineCount`）を読み、`_usage_aggregate_new_lines(transcriptPath, lastLineCount, branch)`
    （**常にtranscriptをファイルパスとして受け取り、jq内部で`inputs`によりファイル内容を読む**。
    詳細は下記の「重要な追加バグ修正」参照）が、カーソル位置以降の新規行のみを対象に
    `totalLines`（空行除く全行数）、`message.usage`（モデル別トークン数）、
    `message.content[].type=="tool_use"`（ツール名別呼び出し回数、および`Skill`/`Agent`ブロックからの
    `skillCalls`/`agentCalls`抽出）、該当エントリ件数（assistant応答回数）、`type=="user"`エントリの
    tool_result本文からの`askUserQuestions`抽出を1回のjq呼び出しの中で完結させて返す
    （`.gitBranch == <branch>` で絞り込み。詳細は上記「新規行diff方式への移行」
    「呼び出し・質問の詳細記録」参照）。`totalLines <= lastLineCount`（新規行が無い）なら、
    session-logsへのコピー・状態更新をスキップし既存状態をそのまま返す。新規行があれば、
    `_usage_sync_session_logs`で対象transcriptを`usage/session-logs/`へコピーしたうえで、
    `totalLines`以外のフィールドをそのまま「新規分（差分）」として使う。
    `_usage_merge_state`は引き算せずブランチ単位の状態ファイル（`usage/state/<branch>.json`、
    gitignore対象）の`sinceLastPush`へ単純加算・追記する。`activeSeconds`のみ別途
    `_usage_aggregate_transcript`（全件再パース。下記参照）で算出し、従来通り
    `sessions[sessionId].lastActiveSeconds`との差分（下限0）を計上する。**`.agents`
    （サブエージェントの累計スナップショット）は`_usage_merge_state`が管理するフィールドではないが、
    出力へそのまま引き継ぐ（issue #34で修正）。落とすと後続の`_usage_aggregate_and_merge_subagents`が
    毎回「前回スナップショット無し」として扱い、サブエージェント分の差分が常に全量再計上される
    不具合になる**。続けて`_usage_aggregate_and_merge_subagents`が`subagents/agent-*.jsonl`を
    列挙し、1ファイルずつ`agentId`単位のカーソル（`_usage_read_cursor`/`_usage_write_cursor`。
    メインと同じ`usage/state/session-cursors/`配下）を使って同じ`_usage_aggregate_new_lines`で
    新規行を集計し（新規行が無いagentはスキップ）、`_usage_merge_agent_state`（`agentId`単位の
    差分を`sinceLastPush.subagents[agentId]`へ保持しつつ、`activeSeconds`のみ
    `_usage_aggregate_transcript`の全件再パースで別途算出。`agentType`・`description`は
    `meta.json`から取得）で畳み込む。最後にメイン・サブエージェント両方のカーソルを
    `_usage_write_cursor`で更新する。投稿成功後のリセットは`_usage_reset_since_last_push`が担い
    （`sinceLastPush`をゼロ初期化。`skillCalls`/`agentCalls`/`askUserQuestions`も空配列へ、
    `agents`スナップショットは保持）、レポート表示直前の0件除外は`_usage_filter_nonzero_subagents`が
    担う（いずれもissue #34でテスト容易性のため関数化した）。`_usage_aggregate_transcript`
    （全件再パース）自体はissue #37以降`activeSeconds`算出専用として無改造のまま維持している
    （呼び出し元は戻り値のうち`.activeSeconds`のみを使う）。`_usage_safe_branch_name`はブランチ名の
    サニタイズ（状態ファイル名・session-logsディレクトリ名に使用）を担う共通ヘルパー。
    - **重要な追加バグ修正（issue #37、PR #47マージ前に発覚）**: `_usage_aggregate_new_lines`は
      当初、新規行の切り出し（別関数`_usage_read_new_lines`）とその集計を2段階に分け、切り出した
      パース済みJSON配列をシェル変数へ格納したうえで`--argjson`のコマンドライン引数としてjqへ
      渡す設計だった。しかしtranscriptの各行にはtool_use/tool_resultの生の入出力（Read/Bashの
      出力、Editの差分等）がそのまま含まれるため、新規行がわずか32件（約120KB）程度でもこの
      引数が肥大化し、Windowsのプロセス生成時のコマンドライン長上限（実測でおよそ32KB程度）を
      超えて`jq`の起動自体が`Argument list too long`（終了コード126）で失敗することが実データで
      判明した（対応工数レポートが投稿されなくなる不具合の直接原因）。両関数を1つに統合し、
      `_usage_aggregate_transcript`と同じ安全なパターン（ファイルパスを渡し`inputs`で読ませる）に
      統一して解消した。一般的な注意事項として
      [`.claude/rules/shell-script-style.md`「JSON操作」節](../../.claude/rules/shell-script-style.md)
      にも追記した。
    - **付随して見つかったバグ2件**: (1) userメッセージの`message.content`は、人間が直接入力した
      シンプルなテキストの場合は content-blockの配列ではなく単一の文字列のまま格納されることが
      実データで確認された。`.[]`でイテレートする既存コードはこの場合`Cannot iterate over string`で
      例外になるため、配列の場合のみ中身を返すjqヘルパー`content_blocks`を追加して防いだ。
      (2) 状態ファイル（`usage/state/<branch>.json`）が空／不正なJSONに壊れた状態のまま
      `_usage_merge_state`の`--argjson existing`へ渡ると、`jq`が不正なJSONとして必ず失敗し、
      **一度壊れると以降ずっと投稿できなくなる**（実際に0バイトの状態ファイルとカーソルだけが
      進んだ状態を確認した）。`sync_usage_state`が状態ファイルを読む箇所で内容の妥当性を
      （空文字列チェック→`jq -e .`の順で）検証し、無効なら`{}`（状態なし）へフォールバックする
      自己回復ロジックを追加した。詳細な経緯は
      [DDR 0006の追記](../ddr/0006-対応工数レポートはtranscript自前パースで実装する.md)を参照。
  - `.claude/hooks/post-push-usage-report.sh`（`PostToolUse` hook、bash版）: `.claude/settings.json` の
    matcher `Bash|PowerShell` と `if: "Bash(git push*)"` / `if: "PowerShell(git push*)"` により
    `git push` を含むコマンド実行後のみ発火する（マッチしなければプロセス起動自体が行われず、
    通常のBash/PowerShell利用への性能影響は無い）。投稿要否判定の前に自分で `sync_usage_state` を
    呼んで状態を最新化してから投稿する（ターンの途中でのpushでも記録漏れが起きないようにするため）。
    `sinceLastPush` が全て0（メイン＋サブエージェント双方のトークン合計で判定）なら投稿しない。
    `get_mr_for_branch` でMRが無ければ投稿しない。投稿成功後のみ `_usage_reset_since_last_push`で
    `sinceLastPush` をリセットする（失敗時は次回pushへ繰り越す。git push自体はブロックしない）。
    hookの起動コマンドは`"bash"`（PATH解決に依存。詳細: [shell-scripts.md](shell-scripts.md)）。
    コメント本文には`fmt_duration`（秒→`H時間M分`/`M分`形式）で整形した「対応工数（目安・入力待ち
    時間を除く）」の行、`skillCalls`/`agentCalls`/`askUserQuestions`がそれぞれ1件以上あれば
    「### skill呼び出し」「### Agent呼び出し」「### ユーザーへの質問」の詳細テーブル（issue #37。
    詳細は上記「呼び出し・質問の詳細記録」参照）、および`_usage_filter_nonzero_subagents`適用後の
    サブエージェント分が1件以上あれば「### サブエージェント」セクション（`agentId`×モデルの
    1行テーブル。エージェント種別・説明・モデル別トークン、ツール実行回数合計、稼働時間参考値）を
    含める。テーブル描画で`agentId`・モデル名・配列インデックス等をfor変数として使うループには、
    Windowsネイティブjqのコマンド置換CR混入対策（`.claude/rules/shell-script-style.md`
    「文字コード」節参照）として`tr -d '\r'`を挟む。
  - `.claude/settings.json`: `hooks.PostToolUse` を追加。
  - `.gitignore`: `/usage/`（issue #37で`/.claude/usage-state/`, `/.claude/session-logs/`の2行から
    統合。詳細は上記「`usage/`ディレクトリへの移設」参照）。
- **`Stop` hookは使わない**: 当初は `Stop`（1ターン完了時に発火）でも同じ集計処理を呼び、
  ターン数カウント専用の役割を持たせていたが、(1) `post-push-usage-report.sh` 自身が呼ぶだけで
  十分、(2) `Stop`依存のカウントは「そのターンのStopがまだ発火していない状態でのpush」で
  過少カウントになる、ことが分かったため廃止した。代わりに「assistant応答回数」を
  トークン・ツール回数と同じtranscript差分方式で算出する。
- **投稿内容の位置づけ**: コメント本文冒頭に「このコメントはClaude Codeによる自動投稿です。
  レビューの合否判定には使用しないでください。」と明記する（`add_mr_comment` は通常コメントであり
  レビューではないため、そもそも承認状態に影響しない。issue #15の受け入れ条件に対応）。
- **フッターの免責事項説明文は初回投稿のみ表示**（issue #28, PR #29レビュー指摘）: 集計方法や
  既知の過小カウント要因（トークン数の項参照）を説明する詳しめのフッター文（`Claude Codeより:
  自動投稿（post-push-usage-report.sh による集計。...）`の段落）は、同じMRへ毎回のpushで
  繰り返し投稿されると冗長になるため、そのブランチ（MR）に対して**過去に投稿成功したことがあるか**
  （状態ファイルの`lastPostedAt`の有無、投稿前時点の値で判定）で分岐し、初回投稿時のみ表示する。
  冒頭の「レビューの合否判定には使用しないでください」という短い注記は、投稿ごとの判別のために
  必要なため毎回表示する。
- **制約: スクリプト経由の`git push`は検知されない**: 投稿トリガーの判定は、Bash/PowerShell
  ツールへ渡された`tool_input.command`文字列が`git push`で始まるかどうかの前方一致マッチ
  （`.claude/settings.json`の`if: "Bash(git push*)"` / `if: "PowerShell(git push*)"`）に依存する。
  そのため、`git push`をラップしたスクリプト（`bash deploy.sh`等）や、gitのエイリアス、他言語の
  subprocess経由でpushした場合は`tool_input.command`自体に`git push`という文字列が現れず、
  hookプロセスが起動されないため検知できない。そのため、git pushをラップしたスクリプトを作成することやgit pushコマンドを前方一致マッチにHITしないような形式で実行することを**禁止**する。投稿対象は使用量レポート（参考情報）のみでpush
  自体をブロックする機能ではないため、影響は該当push分の投稿が漏れることに留まる（次回、検知条件に
  一致するpush時に`sinceLastPush`が繰り越されて投稿される）。より厳密な検知（`PreToolUse`と
  `PostToolUse`のペアでref状態を比較する等）も検討可能だが、全Bash/PowerShell呼び出しへ処理が
  追加され性能影響とのトレードオフになるため、対応しない。
- **設計判断の詳細・却下案**（`transcript` JSONL自前パースの採用理由、`gitBranch` フィルタの理由、
  `Stop` hookを廃止した経緯）は
  [0006-対応工数レポートはtranscript自前パースで実装する.md](../ddr/0006-対応工数レポートはtranscript自前パースで実装する.md)
  参照。

### /compact実施の呼びかけ（PostToolUse hook, git push検知）

issue #11「git pushイベントを検知してcompactする」への対応として、MRレビュー待ちに入るタイミング
（`git push`後）でコンテキストが肥大化しがちという課題に対し、`/compact`実施のタイミングを
逃さないよう気づきを与える。

- **検知ロジック**: 「対応工数レポート」節の`post-push-usage-report.sh`と同一パターン
  （`agent_id`/`tool_name`/`tool_input.command`の`git[[:space:]]+push`判定、
  `CLAUDE_PROJECT_DIR`確認、`get_workflow_config`でbase branch上のpushを除外、
  `get_mr_for_branch`でMRが無いブランチ（レビュー対象が無い）を除外）を流用する。
- **伝達手段は対応工数レポートと異なる**: 投稿先がMRコメントの対応工数レポートに対し、本機能は
  「セッション開始時の自動コンテキスト注入（SessionStart hook）」節の`session-start.sh`と同じ
  `hookSpecificOutput.additionalContext`方式（stdoutへJSON出力→コンテキストへ注入→エージェントが
  応答に反映）を使い、対話中のユーザーへ直接呼びかける。出力形式:
  `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"<text>"}}`。
  メッセージは固定文（「MRのレビューをお願いします。/compactを実施をしていただくと、レビュー中に
  コンテキストを圧縮して今後の作業が効率化になる可能性があります」）で、動的な値は使わない。
- **`post-push-usage-report.sh`とは別ファイル**（`.claude/hooks/post-push-compact-prompt.sh`）とし、
  責務を混在させない（使用量集計とcompact促しは関心事が異なる）。`.claude/settings.json`の
  `hooks.PostToolUse[0].hooks`へ、既存の対応工数レポート用エントリと並べて2エントリ
  （`if: "Bash(git push*)"` / `"PowerShell(git push*)"`）を追加した。
- **エラー方針・実行シェルは既存hookと同様**: `main`関数＋`( main ) || true`＋`exit 0`
  （git push自体をブロックしない）、起動コマンドは`"bash"`（PATH解決に依存する制約は
  「セッション開始時の自動コンテキスト注入」節と同じ）。
- **`PostToolUse`での`additionalContext`実地検証**: このリポジトリで`additionalContext`方式の
  前例は`SessionStart`のみだったため実装後に実地検証した。実際の`git push`実行により、次のターンで
  `<system-reminder>PostToolUse:Bash hook additional context: ...</system-reminder>`が注入され
  期待通り動作することを確認済み（issue #11対応セッション）。
- **制約は「対応工数レポート」節と共通**: 「スクリプト経由の`git push`は検知されない」制約が
  同様に適用される（検知ロジックを流用しているため）。

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

`/issue-mr-flow start` 側の対応: `get_issue` で取得したissue本文に4見出し
（`## 目的` / `## 現状` / `## 期待する動作` / `## 受け入れ条件`）が揃っているかを
`Provider.sh` の `test_issue_sections` でチェックし、欠けている見出しがあれば警告として提示する
（処理は止めない。テンプレートを使わず手動で作られた既存issueにも同じチェックが働く）。

### issue作成（AIエージェント代行・スクリプト実行）（issue #25）

issueはGitHubのUIからしか作成できず、標準4見出し（目的・現状・期待する動作・受け入れ条件）に
沿ったissueを、スクリプト実行やAIエージェント経由で作成する手段が無かった。「Issueテンプレート
標準化」節で定めた4見出しの**作成**側を、既存の`get_issue`（取得）と対称的な構造で追加した。

- **`build_issue_body`**: 4見出しでissue本文を組み立てる純粋関数（外部コマンド呼び出し無し）。
  `test_issue_sections`と組み合わせて使うことで、組み立てた本文が常に4見出しを満たすことを
  スクリプト内で検証できる。
- **`new_issue` / `github_new_issue` / `gitlab_new_issue`**: `new_draft_merge_request`等と同じ
  ディスパッチパターンで実装。`gh issue create` / `glab issue create`はissue番号を含んだJSONを
  直接返さずissue URLのみを出力するため、出力URL末尾から`grep -oE '[0-9]+$'`で番号を抽出し、
  `github_get_issue`/`gitlab_get_issue`を呼んで`get_issue`と同じ形（number/title/body/url/slug）に
  正規化する（呼び出し側が取得・作成のどちらの戻り値も同じ形で扱えるようにするため）。番号抽出に
  失敗した場合はエラーメッセージを出して`return 1`する。
- **`.claude/scripts/src/create-issue.sh`（新規CLIスクリプト）**: `--title`/`--purpose`/`--current`/
  `--expected`/`--acceptance`の5フラグ（すべて必須）を受け取り、`build_issue_body`→
  `test_issue_sections`（安全網）→`new_issue`の順に呼び出す。標準出力に作成結果のJSONを返す。
  人間が直接実行することも、AIエージェントが呼び出すことも想定する。
- **`.claude/skills/issue-create/SKILL.md`（新規スキル）**: `issue-mr-flow`のflow-id 1
  （issue起票、本来は人間の担当）をAIエージェントが代行するための独立スキル。ユーザーの依頼内容から
  5項目（タイトル＋4見出し）を埋め、内容が不足していれば質問で補い（勝手に創作しない）、ユーザーに
  提示して明示的な確認を得たうえで`create-issue.sh`を実行する。issue作成後のブランチ・Draft MR
  作成（flow-id 2〜3）は対象外とし、`/issue-mr-flow start <issue番号>`に委ねる。
  `issue-mr-flow/SKILL.md`のflow-id 1担当セルに、このスキルへの導線を一言追記した。
  `issue-mr-flow`のサブコマンドとして追加しなかった理由・却下案は
  [0011-issue作成は独立スキルとして新設する.md](../ddr/0011-issue作成は独立スキルとして新設する.md)
  参照。
- **GitHub/GitLab両実装**: 他の`gitlab_*`関数群と同様、GitLab側（`gitlab_new_issue`）はこのリポジトリの
  remoteがGitHubのみのため実機未検証（「未決定事項・懸念点」の既存項目と同じ制約）。
- **実機検証（GitHub）**: `create-issue.sh`を実際に実行してissue #38を作成し、4見出し構成で
  正しく作成されることを確認した。検証用issueのため確認後にクローズ済み。

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
- `dev-tools/docs/README.md`（本機能のspecへのリンクを追加。設計反映時）
- `dev-tools/src/vcs/Provider.ps1`（`Test-IssueSections` 追加、`Github.ps1`のgraphqlクエリ修正）
- `.claude/skills/issue-mr-flow/SKILL.md`（`start` サブコマンドに標準4項目の警告ステップを追加。
  その後、docs-workflow.md/git-workflow.mdの実装フロー統合により全体フローの唯一の定義に変更）
- `.claude/rules/docs-workflow.md` / `.claude/rules/git-workflow.md`（実装フロー部分を削除し、
  参照情報のみを残す形に縮小）
- `.claude/skills/ahk-implement/SKILL.md`（issue-mr-flowから呼ばれるサブフローという位置づけに変更）
- `AGENTS.md`（issue-mr-flow/SKILL.mdへのポインタを追加）

新規（追加分）:
- `dev-tools/docs/ddr/0002-issue-mr-flowへの実装フロー統合.md`

変更（追加分）:
- `dev-tools/src/vcs/Provider.ps1`（`Add-MrThreadReply` 追加、`Get-MrUnresolvedComments` に
  `-IncludeResolved` 追加）
- `dev-tools/src/vcs/Github.ps1` / `Gitlab.ps1`（返信のmutation/API呼び出しを追加）
- `.claude/skills/issue-mr-flow/SKILL.md`（`comments` に `all` 引数、`reply` サブコマンドを新設。
  「レビュー完了合図の確認」節を追加）

新規（設計反映時）:
- `dev-tools/docs/ddr/0003-レビュースレッド解決は自動化しない.md`

新規（追加分・途中引き継ぎ対応）:
- `.claude/agents/issue-mr-resume.md`（状態調査サブエージェント）

変更（追加分・途中引き継ぎ対応）:
- `dev-tools/src/vcs/Provider.ps1`（`Get-IssueNumberFromBranch`, `Get-MrForBranch`,
  `Get-BranchWorkFiles` を追加）
- `dev-tools/src/vcs/Github.ps1` / `Gitlab.ps1`（`GitHub-GetMrForBranch` / `GitLab-GetMrForBranch` を追加）
- `.claude/skills/issue-mr-flow/SKILL.md`（`resume` サブコマンドを新設。`comments` / `describe` の
  MR番号取得手順を `Get-MrForBranch` に統一）

新規（追加分・issue #5 SessionStart hook対応）:
- `.claude/hooks/session-start.ps1`（セッション開始時の自動コンテキスト注入スクリプト）

変更（追加分・issue #5 SessionStart hook対応）:
- `.claude/settings.json`（`hooks.SessionStart` を追加）
- `dev-tools/docs/spec/issue-mr-workflow.md`（本セクション追加）
- `.claude/skills/issue-mr-flow/SKILL.md`（全体フローを再構成。`docs/spec/`への設計ドキュメント
  作成・承認を独立ステップとして持つのをやめ、Planモードでの実行手順作成に一本化。plan合意〜実装
  着手の間にコンテキスト削減のためのセッションclearステップを新設。ステップ数は23のまま。
  「フローが進むごとにHANDOFF.mdに現在の状況を反映する」運用ルールを追加）

新規（追加分・issue #5 レビュー対応時の文字コード修正）:
- `.claude/rules/powershell-encoding.md`（PowerShellスクリプト・コマンドの文字コード注意事項）

変更（追加分・issue #5 レビュー対応時の文字コード修正）:
- `dev-tools/src/vcs/Provider.ps1`（dot-source直後にコンソール入出力エンコーディングをUTF-8へ切り替え）
- `.claude/skills/issue-mr-flow/SKILL.md`（「詳細ルールへのポインタ」に
  `.claude/rules/powershell-encoding.md` を追加）

新規（追加分・issue #15 Draft PR自動リトライ＋対応工数レポート）:
- `.claude/hooks/lib/UsageTracking.ps1`（集計ロジック）
- `.claude/hooks/post-push-usage-report.ps1`（PostToolUse hook）
- `dev-tools/docs/ddr/0005-DraftPR作成失敗時は空コミットで自動リトライする.md`
- `dev-tools/docs/ddr/0006-対応工数レポートはtranscript自前パースで実装する.md`

変更（追加分・issue #15 Draft PR自動リトライ＋対応工数レポート）:
- `dev-tools/src/vcs/Provider.ps1`（`Add-EmptyCommitForDraftMr`, `Add-MrComment` を追加）
- `dev-tools/src/vcs/Github.ps1` / `Gitlab.ps1`（`New-DraftMergeRequest` 実装に失敗時リトライを追加、
  `GitHub-AddMrComment` / `GitLab-AddMrComment` を追加）
- `.claude/settings.json`（`hooks.PostToolUse` を追加）
- `.gitignore`（`/.claude/usage-state/` を追加）
- `.claude/rules/directory-structure.md`（`.claude/hooks/` `.claude/hooks/lib/` をツリーに追加、
  hookスクリプトのBOM要件を配置の指針に追記）
- `.claude/rules/powershell-encoding.md`（新規`.ps1`作成時のBOM変換・構文検証コマンド例を追記）

新規（追加分・issue #6 スクリプトのbash化）:
- `dev-tools/src/vcs/Provider.sh` `Github.sh` `Gitlab.sh`
- `dev-tools/src/build.sh`
- `.claude/hooks/session-start.sh` `.claude/hooks/post-push-usage-report.sh`
- `.claude/hooks/lib/UsageTracking.sh`
- `tests/test_external_command_server.sh`
- `tests/test_vcs_provider.sh`（bash版Provider.shの純粋ロジックに対する単体テスト。新設）
- `dev-tools/docs/spec/shell-scripts.md`（bash化の設計方針）
- `.claude/rules/shell-script-style.md`（bashスクリプトの規約）

変更（追加分・issue #6 スクリプトのbash化）:
- 上記に対応する全`.ps1`ファイルを削除（`dev-tools/src/vcs/{Provider,Github,Gitlab}.ps1`,
  `dev-tools/src/build.ps1`, `.claude/hooks/session-start.ps1`,
  `.claude/hooks/post-push-usage-report.ps1`, `.claude/hooks/lib/UsageTracking.ps1`,
  `tests/test_external_command_server.ps1`）
- `.claude/settings.json`（hookの`command`を`powershell.exe`から`bash`へ変更。PATH解決に依存する
  ため、開発機ごとに「PATHへのgit bash追加＋順序調整」のセットアップが別途必要）
- `.claude/skills/issue-mr-flow/SKILL.md`（コード例・関数名をbash/snake_case版に更新、
  前提に`jq`を追加）
- `dev-tools/docs/spec/distribution.md`（`build.ps1`→`build.sh`）
- `tests/README.md`（対象スクリプトの更新、単体テストの追加）
- `.claude/rules/directory-structure.md`（`.sh`配置ルール・jq前提を追記）
- `.claude/rules/powershell-encoding.md`（「PowerShellを直接書く場合のみ適用」である旨を明確化）

新規（追加分・issue #28 対応工数レポートの稼働時間記録）:
- `tests/test_usage_tracking.sh`（`UsageTracking.sh`の`_usage_aggregate_transcript`/
  `_usage_merge_state`に対する単体テスト。新設）

変更（追加分・issue #28 対応工数レポートの稼働時間記録）:
- `.claude/hooks/lib/UsageTracking.sh`（`IDLE_GAP_THRESHOLD_SECONDS`/`TAIL_BUFFER_SECONDS`定数、
  gapベースの`activeSeconds`集計ロジック、`strptime`/`mktime`に依存しない自前実装
  `epoch_from_iso8601`を追加）
- `.claude/hooks/post-push-usage-report.sh`（`fmt_duration`、レポート本文への
  「対応工数（目安・入力待ち時間を除く）」行を追加。レビュー往復で、トークン数の既知の過小カウント
  要因を説明するフッター文の追加、および`is_first_post`判定によるフッター表示の初回投稿限定化も追加）
- `dev-tools/docs/spec/issue-mr-workflow.md`（本セクション「稼働時間の算出方法」を追加、
  「未決定事項・懸念点」に稼働時間の誤差要因・overlap dedup未対応・トークン数の過小カウント要因を
  追記、「投稿内容の位置づけ」にフッター初回投稿限定の挙動を追記）
- `dev-tools/docs/ddr/0006-対応工数レポートはtranscript自前パースで実装する.md`（マージ済みDDRの
  ため既存内容は変更せず、トークン数の過小カウント問題に関する「追記」セクションを追加）
- `tests/README.md`（`test_usage_tracking.sh`の行を追加）
- `.claude/rules/shell-script-style.md`（Windowsネイティブjqの`strptime`/`mktime`未実装という
  一般的な制約を「JSON操作」節に追記）
- `.claude/hooks/post-push-usage-report.sh`（レビュー往復で、モデル別トークンテーブルから
  `<synthetic>`等の全項目0の行を除外する対応を追加）
- `dev-tools/docs/spec/issue-mr-workflow.md`（本セクション「記録範囲」に、ツール実行回数が
  「実際に呼び出されたツールのみの集計」であり全ツール種別の固定カタログではない旨、および
  サブエージェント内部の呼び出しは含まれない旨を追記）

新規（追加分・PR #29レビュー指摘: サブエージェント使用量記録＋session-logsコピー方式）:
- `.claude/session-logs/`（`git push`検知時にメイン・サブエージェントtranscriptをコピーする先。
  gitignore対象のためリポジトリには含まれない）

変更（追加分・PR #29レビュー指摘: サブエージェント使用量記録＋session-logsコピー方式）:
- `.claude/hooks/lib/UsageTracking.sh`（`_usage_safe_branch_name`ヘルパー切り出し、
  `_usage_sync_session_logs`（メイン・サブエージェントtranscriptのローカルコピー）、
  `_usage_merge_agent_state`（`agentId`単位のスナップショット差分を`agentType`単位で集約）、
  `_usage_aggregate_and_merge_subagents`（コピー済みディレクトリからの集計・マージ）を追加。
  `_usage_aggregate_transcript`/`_usage_merge_state`本体は無改造のまま再利用）
- `.claude/hooks/post-push-usage-report.sh`（投稿要否判定の`total`計算にサブエージェント分を
  含める、「### サブエージェント」セクションの追加、`sinceLastPush`リセット時の
  `subagentsByType: {}`追加）
- `.gitignore`（`/.claude/session-logs/`を追加）
- `tests/test_usage_tracking.sh`（`_usage_merge_agent_state`/`_usage_sync_session_logs`/
  `_usage_aggregate_and_merge_subagents`の単体テストを追加。疑似`~/.claude/projects`ツリーを
  `$TMPDIR`配下に自作して検証、実ホームディレクトリには触れない）
- `tests/README.md`（対象関数の追記）
- `dev-tools/docs/spec/issue-mr-workflow.md`（本セクション「記録範囲」の更新、新規サブセクション
  「サブエージェントの使用量記録」追加、「コンポーネント」の関数一覧更新、「未決定事項・懸念点」の
  追記）
- `dev-tools/docs/ddr/0006-対応工数レポートはtranscript自前パースで実装する.md`（マージ済みDDRの
  ため既存内容は変更せず、session-logsコピー方式・`agentId`/`agentType`二段設計に関する
  「追記」セクションを追加）

新規（追加分・issue #11 /compact実施の呼びかけ）:
- `.claude/hooks/post-push-compact-prompt.sh`（PostToolUse hook）

変更（追加分・issue #11 /compact実施の呼びかけ）:
- `.claude/settings.json`（`hooks.PostToolUse[0].hooks`へ`post-push-compact-prompt.sh`用の
  2エントリを追加。既存の対応工数レポート用エントリは維持）
- `dev-tools/docs/spec/issue-mr-workflow.md`（本セクション「/compact実施の呼びかけ」を追加、
  「コンポーネント構成」ツリーに`post-push-compact-prompt.sh`を追加）
- `dev-tools/src/vcs/Provider.sh`（`new_issue_branch`内の`git fetch`/`git switch`/`git push`の
  標準出力を`/dev/null`へ捨てるよう修正。従来は`git push -u`の出力が呼び出し元の
  `branch="$(new_issue_branch ...)"`という`$(...)`キャプチャへ混入し、branch変数が複数行文字列に
  なる不具合があった（本issue対応セッションで実際に踏み、手動リカバリ済み。`add_empty_commit_for_draft_mr`
  と同じ`>/dev/null`パターンで解消。flow-id 17のAIアセット改善で対応））

変更（追加分・issue #34: サブエージェント使用量記録のpush差分バグ修正・agent単位表示化）:
- `.claude/hooks/lib/UsageTracking.sh`
  - `_usage_merge_state`の戻り値に`.agents`のpassthroughを追加（push差分バグ本体の修正。
    詳細は本ファイル「サブエージェントの使用量記録」節参照）。
  - `_usage_merge_agent_state`のスキーマを`agentType`合算（`sinceLastPush.subagentsByType`）から
    `agentId`単位（`sinceLastPush.subagents`、`description`引数を追加）へ変更。
  - `_usage_reset_since_last_push`（投稿成功後のリセット処理の切り出し）、
    `_usage_filter_nonzero_subagents`（差分0のagent除外）を新規追加。
- `.claude/hooks/post-push-usage-report.sh`
  - サブエージェントテーブルを`agentType`合算の1行から`agentId`単位の1行（エージェント種別・
    説明・モデル別トークン）表示へ変更。表示直前に`_usage_filter_nonzero_subagents`を適用。
  - メイン・サブエージェント双方のツール実行回数表示に`map(select(.value > 0))`を追加し、
    差分0のツールをキーごと非表示化（レビュー往復で判明した追加のユーザー指示への対応）。
  - リセット処理を`_usage_reset_since_last_push`呼び出しに置き換え。
  - 主トークンテーブル・サブエージェントagentId/モデルの3ループに`tr -d '\r'`を追加
    （Windowsネイティブjqのコマンド置換CR混入バグの回避。実装時に新規発見）。
- `tests/test_usage_tracking.sh`（新スキーマに合わせて`_usage_merge_agent_state`関連テストを
  書き換え、`_usage_reset_since_last_push`/`_usage_filter_nonzero_subagents`の単体テスト、
  `sync_usage_state`を通しで呼ぶpush差分の回帰テスト（push→リセット→次pushは差分0→追記後は
  差分のみ）を追加。25件→39件）
- `.claude/rules/shell-script-style.md`（「文字コード」節に、Windowsネイティブjqのコマンド置換
  経由でのCR混入について追記。ファイルリダイレクト時の既知の挙動と同根だが、
  `for x in $(... | jq -r ...)`のようなループで2件以上の要素があると最後の要素以外にCRが
  付いたまま渡ることを新たに確認したもの）
- `dev-tools/docs/spec/issue-mr-workflow.md`（本セクション「サブエージェントの使用量記録」
  「コンポーネント」を`agentId`単位表示・関数構成の変更に合わせて更新。本エントリを追加）

新規（追加分・issue #25 issue作成スクリプト・スキル）:
- `dev-tools/src/create-issue.sh`（標準4見出しでissueを作成するCLIスクリプト）
- `.claude/skills/issue-create/SKILL.md`（issue起票をAIエージェントが代行する独立スキル）

変更（追加分・issue #25 issue作成スクリプト・スキル）:
- `dev-tools/src/vcs/Provider.sh`（`build_issue_body`、`new_issue`ディスパッチを追加）
- `dev-tools/src/vcs/Github.sh`（`github_new_issue`を追加）
- `dev-tools/src/vcs/Gitlab.sh`（`gitlab_new_issue`を追加。未検証）
- `.claude/skills/issue-mr-flow/SKILL.md`（flow-id 1担当セルに`issue-create`スキルへの導線を追記）
- `tests/test_vcs_provider.sh`（`build_issue_body`の単体テストを追加）
- `dev-tools/docs/spec/issue-mr-workflow.md`（「提供関数」に`build_issue_body`/`new_issue`を追加、
  新規サブセクション「issue作成（AIエージェント代行・スクリプト実行）」を追加、本エントリを追加）

新規（追加分・issue #37 対応工数レポートの集計ロジック修正・詳細テーブル追加）:
- `usage/`（`.claude/session-logs/`・`.claude/usage-state/`の移設先。`usage/session-logs/`,
  `usage/state/`（`usage/state/session-cursors/`にセッション横断カーソルを保持）。gitignore対象の
  ためリポジトリには含まれない）

変更（追加分・issue #37 対応工数レポートの集計ロジック修正・詳細テーブル追加）:
- `.claude/hooks/lib/UsageTracking.sh`（全面書き換え。`_usage_read_new_lines`/
  `_usage_aggregate_new_lines`（新規行diff集計、`skillCalls`/`agentCalls`/`askUserQuestions`抽出）、
  `_usage_read_cursor`/`_usage_write_cursor`（セッション横断カーソル管理）を追加。
  `_usage_merge_state`をdelta加算＋`activeSeconds`のみ差分方式へ変更。`_usage_merge_agent_state`/
  `_usage_aggregate_and_merge_subagents`も`agentId`単位のカーソル管理を組み込んで書き換え。
  `_usage_aggregate_transcript`自体は`activeSeconds`算出専用として無改造のまま維持）
- `.claude/hooks/post-push-usage-report.sh`（「### skill呼び出し」「### Agent呼び出し」
  「### ユーザーへの質問」の3テーブルを追加。`state_dir`のパスを`usage/state`へ更新）
- `.gitignore`（`/.claude/usage-state/`, `/.claude/session-logs/`の2行を`/usage/`1行へ統合）
- `tests/test_usage_tracking.sh`（新方式に合わせて全面書き換え。66件）
- `dev-tools/docs/ddr/0006-対応工数レポートはtranscript自前パースで実装する.md`（マージ済みDDRの
  ため既存内容は変更せず、行オフセットベースの差分パースへの移行・`usage/`ディレクトリ移設に関する
  「追記」セクションを追加）
- `.claude/rules/directory-structure.md`（ツリーへ`usage/`を追加）
- `dev-tools/docs/spec/issue-mr-workflow.md`（本セクション「記録範囲」「稼働時間の算出方法」
  「session-logsローカルコピー方式」を更新、新規サブセクション「新規行diff方式への移行」
  「呼び出し・質問の詳細記録」を追加、「コンポーネント」の関数一覧を更新、本エントリを追加）

変更（追加分・issue #37 続き: PR #47マージ前に発覚したjq argv長制限バグの修正）:
- `.claude/hooks/lib/UsageTracking.sh`（`_usage_read_new_lines`/`_usage_aggregate_new_lines`の
  2関数構成を1関数（常にtranscriptをファイルパスとして受け取りjq内で`inputs`により読む設計）へ
  統合し、大きな新規行データをコマンドライン引数として渡すことによる`Argument list too long`
  失敗を解消。あわせて、userメッセージの`message.content`が配列でなく文字列の場合に
  `Cannot iterate over string`で例外になる別のバグ（jqヘルパー`content_blocks`で修正）、
  および状態ファイルが破損（空／不正なJSON）した場合に恒久的に集計不能になる問題
  （`sync_usage_state`に自己回復ロジックを追加）も同時に修正）
- `tests/test_usage_tracking.sh`（新シグネチャに合わせて既存テストを書き換え、巨大ペイロード・
  文字列content・状態ファイル破損の3件の回帰テストを追加。71件）
- `.claude/rules/shell-script-style.md`（「JSON操作」節に、大きなJSONを`--argjson`等の
  コマンドライン引数としてjqへ渡さない一般的な注意事項を追記）
- `dev-tools/docs/spec/issue-mr-workflow.md`（本セクション「コンポーネント」に本バグ修正の
  詳細を追記、本エントリを追加）
- `dev-tools/docs/ddr/0006-対応工数レポートはtranscript自前パースで実装する.md`（マージ済みDDRの
  ため既存内容は変更せず、本バグ修正に関する追記セクションを追加）

変更（追加分・issue #43 開発フローに「調査」サイクルを追加）:
- `.claude/skills/issue-mr-flow/SKILL.md`（全体フローを23ステップから33ステップへ再構成。
  Planモードでの実行手順作成（旧flow-id 4）の前段に、作業サイクルと対称な「調査」サイクル
  （調査計画作成→合意→commit→レビュー→ループ→describe→調査実施→commit→describe→レビュー→
  ループ、新flow-id 4〜14）を新設し、以降を「調査結果をもとに」作業計画を作る形に書き換えて
  新flow-id 15以降へスライドさせた。調査計画・調査結果は別ファイルに分けず、既存の
  `plans/<plan名>.md`に章立てで含める（後述のDDR参照）。あわせて`start`/`resume`サブコマンドの
  案内文言、`flow-id 21実施前にマージされてしまった場合の対処`見出し・本文（→`flow-id 31`）、
  「レビュー完了合図の確認」見出しの対象flow-id列挙（→8・14・19・25・30）を更新）
- `HANDOFF.md`（「注」の誤記（35→33ステップ）を修正。フロー進捗状況テーブル自体の33行化は、
  本タスクが旧23ステップの運用下で進行中のため、次タスクへのリセット時（新flow-id 31）に行う）
- `.claude/rules/docs-workflow.md`（「フロー進捗状況」表の対応ステップ数（23→33）、ループ範囲の
  例示（7〜8, 11〜15, 16〜20 →7〜8, 10〜14, 18〜19, 21〜25, 26〜30）、同一ループ内ステップの
  組み合わせ例（14と15→13と14）を更新）
- `.claude/rules/git-workflow.md`（コミット運用節のcommitポイントflow-id列挙を
  「6/12/18/22」→「6/11/17/22/28/32」に更新）
- `.claude/skills/commit/SKILL.md`（frontmatter `description` および本文中のcommitポイント
  flow-id列挙を「6/12/18/22」→「6/11/17/22/28/32」に更新。2箇所）
- `dev-tools/docs/spec/issue-mr-workflow.md`（本セクション「全体フロー23ステップ」表現・
  `flow-id 21`参照（→`flow-id 31`）を更新、本エントリを追加）

変更（issue #24 dev-toolsをAI専用/人間専用に分離）:
- AIエージェントが能動的に利用するスクリプト・設計書一式を `dev-tools/` から `.claude/scripts/` へ
  移動した（`git mv`で履歴保持）。
  - `.claude/scripts/src/`: `vcs/Provider.sh` `Github.sh` `Gitlab.sh`, `create-commit.sh`,
    `create-issue.sh`, `archive-reentrant-plan.sh`, `extract-frontmatter.sh`
  - `.claude/scripts/docs/spec/`: `issue-mr-workflow.md`（本ドキュメント）, `shell-scripts.md`,
    `extract-frontmatter.md`
  - `.claude/scripts/docs/ddr/`: `0002`〜`0012`
  - `dev-tools/`には人間専用のexe配布ビルド関連（`src/build.sh`, `docs/spec/distribution.md`,
    `docs/ddr/0001-*.md`）のみ残した。
- 上記移動に伴い、本ドキュメント・`.claude/skills/*/SKILL.md`・`.claude/hooks/*.sh`・
  `.claude/rules/*.md`・`tests/*.sh`内のパス参照を新パスへ一括更新した（「## 仕様」節の現在の
  記述のみ更新し、本「## 影響範囲」節の過去エントリは変更当時の記録として書き換えていない）。
  `.mrworkflow.json`のデフォルト値（`specDirs`/`ddrDirs`）に`.claude/scripts/docs/{spec,ddr}`を追加。
- `.claude/rules/directory-structure.md`（`dev-tools/`の説明を「人間専用の開発補助ツール」に修正、
  ツリー図に`.claude/scripts/`を追加）
- `.claude/rules/markdown-frontmatter.md`（`ddr`/`spec`/`guide`行に`.claude/scripts/docs/`配下の
  新パスを追加）
- `.claude/agents/issue-mr-resume.md`（旧PowerShell版`Provider.ps1`前提の記述を、現行bash版
  `Provider.sh`のsnake_case関数へ全面書き換え）
- `DEVELOPERS.md`（`build.ps1`→`build.sh`の実行コマンド表記を修正）
- `.claude/rules/powershell-encoding.md`（既に現存しない`Provider.ps1`の仕組みを説明していた節を削除）
- 詳細な調査・作業計画は `plans/delegated-gathering-frog.md` 参照。

## 設定項目

`.mrworkflow.json`（nagame-ahk向けの初期値）

```jsonc
{
  "branchPrefixTemplate": "feature-{issue}-{slug}",
  "defaultBaseBranch": "main",
  "plansDir": "plans",
  "worklogDir": "worklog",
  "specDirs": ["docs/spec", "dev-tools/docs/spec", ".claude/scripts/docs/spec"],
  "ddrDirs": ["docs/ddr", "dev-tools/docs/ddr", ".claude/scripts/docs/ddr"]
}
```

## 決定済み事項（旧・未決定事項）

- **issueとMRのリンク方法**: GitHub/GitLab双方とも `New-DraftMergeRequest` の本文に
  `Closes #<issue番号>` をそのまま使う（両プロバイダとも同じキーワード構文で自動クローズに対応するため、
  差異吸収は不要だった）。
- **未解決コメントの判定基準**: GitHubは `reviewThreads.isResolved`、GitLabは
  `discussion.notes[].resolved`（`resolvable` なnoteのみ対象）をそれぞれ真偽値として使う。
  `Get-MrUnresolvedComments` はこれを既定の除外条件、`-IncludeResolved` で無視する条件として使う。
- **返信本文のテンプレート**: `Add-MrThreadReply` の `-ReplyBody` は呼び出し側（AIエージェント）が
  組み立てた自由文をそのまま渡す。関数側で定型の接頭辞等は付けない。
- **スレッドの解決（resolved）操作**: `Add-MrThreadReply` は返信のみ行い、解決マークは付けない
  （レビュアー側の操作という位置づけ）。かわりに、人間からの完了合図を受けた際は
  `Get-MrUnresolvedComments -IncludeResolved` で再確認してから次のステップへ進む運用にした。
  背景・却下案は
  [.claude/scripts/docs/ddr/0003-レビュースレッド解決は自動化しない.md](../ddr/0003-レビュースレッド解決は自動化しない.md)
  参照。
- **AI返信のアイデンティティ表示**: `Add-MrThreadReply` の投稿者アカウントはAI/人間で分離できない
  （`gh`/`glab` CLIは人間の認証情報を使うため）。かわりに返信本文の先頭に `Claude Codeより:` の
  署名行を必ず付ける運用ルールを `reply` サブコマンド手順に追加した。botアカウントによる
  投稿者分離は規模超過のため見送り。背景・却下案は
  [.claude/scripts/docs/ddr/0004-AI返信は署名で識別しbotアカウント分離は見送る.md](../ddr/0004-AI返信は署名で識別しbotアカウント分離は見送る.md)
  参照。
- **SessionStart hookの実装言語はPowerShell**（issue #6で覆した過去の決定）: issue #5対応時点では
  Bashスクリプトへの置き換え（`gh`/`git`/`jq`がUTF-8をそのまま扱えるため、Windows PowerShell 5.1
  特有のコードページ問題を根本的に回避できる）も検討したが、`Provider.ps1`が持つGitHub/GitLab差異
  吸収ロジックを別言語で二重実装するコストが見合わないと判断し却下していた。issue #6で
  `Provider.ps1`自体を`Provider.sh`へbash化したことで二重実装の懸念が解消され、`session-start.ps1`
  含む全スクリプトをbash化した（詳細: [shell-scripts.md](shell-scripts.md)）。コードページ問題は
  bash化により根本的に発生しなくなった（当時`Provider.ps1`側で行っていた対策は`Provider.sh`では不要）。
- **SessionStart hookでのサブエージェント抑止方法**: 公式ドキュメント確認の結果、SessionStart hookは
  matcher（`startup`/`resume`/`clear`等）で区別してもTask tool経由のサブエージェント内で発火する
  ことが判明した。そのためmatcherでの抑止は不可能と判断し、スクリプト側でstdin JSONの`agent_id`
  フィールドの有無を見て早期終了する実装とした。
- **SessionStart hookのmatcher範囲**: `startup|resume|clear` に限定し、`compact`（頻度が高く`gh` API
  呼び出しのコストが無視できない）と `fork`（今回のissueのスコープ外）は対象外とした。
- **Windows PowerShell 5.1の文字コード対策はルールでなくスクリプト側で強制する**（issue #6で
  `Provider.ps1`自体が`Provider.sh`へ置き換わったため、本項の対策は過去のものとなった。教訓・
  判断基準としての記録として残す）: issue #5対応中に、
  日本語Windowsのシステムコードページ（cp932）起因の文字化け・構文エラーを2種類実機で確認した
  （`gh`出力の誤読によるJSON構文エラー、`Get-Content`のエンコーディング未指定によるレビュー返信の
  文字化け）。当初は「呼び出し側が`-Encoding UTF8`を書く」という運用ルールでの対応を考えたが、
  書き忘れに依存する対策は同じ事故を再発させかねないとの指摘を受け、`Provider.ps1`側で機械的に
  保証する方式に変更した。`Provider.ps1`のdot-source直後に、(1) `[Console]::OutputEncoding`/
  `InputEncoding`をUTF-8へ切り替え（外部コマンドとのI/Oを保護）、(2) `$PSDefaultParameterValues`で
  `Get-Content`/`Set-Content`/`Add-Content`/`Out-File`の既定エンコーディングをUTF-8へ切り替え
  （呼び出し側が`-Encoding`を省略しても安全）を行う。ワイルドカード`'*:Encoding'`は他コマンドレットの
  `-Encoding`パラメータ定義と衝突し警告が出たため、対象コマンドレットを個別に指定した。
  `Provider.ps1`をdot-sourceしない独立スクリプト（`.claude/hooks/session-start.ps1`等）向けの
  注意事項のみ、`.claude/rules/powershell-encoding.md` に残した。
- **`New-DraftMergeRequest` はbaseとの差分（コミット）が無いブランチでは失敗する→空コミットで
  自動リトライする**: `New-IssueBranch`直後はbaseとの差分がまだ無いため`gh pr create` /
  `glab mr create`が失敗する（issue #5対応時に実機確認、当初は手動回避のみでissue #15対応まで
  未解消だった）。`$LASTEXITCODE`で失敗を検知し、空コミット+pushで1回だけ自動リトライする方式で
  解消した。背景・却下案は
  [0005-DraftPR作成失敗時は空コミットで自動リトライする.md](../ddr/0005-DraftPR作成失敗時は空コミットで自動リトライする.md)
  参照。
- **対応工数のトークン集計方式**: transcript JSONLの自前パース以外に確実な取得手段が
  無いことを確認した上で採用した。非公開フォーマットへの依存リスクは、失敗の握りつぶし・
  「目安」である旨の明記で吸収する。`entry.gitBranch`でのフィルタにより、複数ブランチを跨いだ
  セッションでの他ブランチ分混入を防ぐ。詳細・却下案は
  [0006-対応工数レポートはtranscript自前パースで実装する.md](../ddr/0006-対応工数レポートはtranscript自前パースで実装する.md)
  参照。
- **対応工数の集計方式（tools/tokens/turns）はセッション横断カーソルによる新規行diff方式**
  （issue #37）: 「毎回全件再パース＋前回累計との引き算」方式が抱えていた「セッションが新しい
  ブランチで初めてpushされた際の過去分の再計上」バグへの対応として、当初検討したuuidベースの
  重複排除案（不採用）を経て、セッション単位でグローバルなカーソル（ブランチに紐付けない
  `usage/state/session-cursors/<sessionId>.json`）による新規行diff＋単純加算方式を採用した。
  `activeSeconds`のみ単調非減少性を保つため従来の全件再パース方式を維持する。設計判断の経緯・
  却下案は
  [0006-対応工数レポートはtranscript自前パースで実装する.md](../ddr/0006-対応工数レポートはtranscript自前パースで実装する.md)
  の追記を参照。

## 未決定事項・懸念点

- **GitLab側の動作未検証**: このリポジトリの実remoteはGitHubのみのため、`Gitlab.sh`（`gitlab_get_mr_unresolved_comments`
  の解決済み含む分岐、`gitlab_add_mr_thread_reply` を含む。issue #6でbash化したが未検証の構造は
  PowerShell版から変わっていない）はAPI仕様を調べた上での実装となり、実機での動作確認ができていない。
  GitLab側のテスト方法（別リポジトリ用意等）は今後の課題。
- **他リポジトリへの移植性の検証**: `.mrworkflow.json` による切り出しで足りるか、実際に他リポジトリへ
  導入してみないと確認できない。今回はnagame-ahk上での実装・検証にとどめる。
- **（issue #22で対応済み）全角文字のみのissueタイトルのスラッグ化**: `to_slug`（旧
  `ConvertTo-Slug`）はASCII英数字のみを残す簡易実装のため、「開発フローを変える」のような全角文字
  のみのタイトルは空文字となり `issue` にフォールバックしていた（実機確認: issue #3 で確認済み）。
  `to_slug`自体は変更せず、`start`サブコマンド実行時にAIエージェントがissueタイトルの意味を汲んだ
  英語の意訳フレーズを生成し`new_issue_branch`へ渡す方式で対応した（詳細:
  [0010-ブランチslugの意訳生成はAIエージェントが行う.md](../ddr/0010-ブランチslugの意訳生成はAIエージェントが行う.md)）。
- **`ahk-implement` スキルの非issueタスクでの扱い**: 今回の統合で `ahk-implement` は独立した
  最上位エントリーポイントではなく `issue-mr-flow` から呼ばれるサブフローという位置づけに変更した。
  「issueを起票しないごく小さな変更」は `git-workflow.md` の適用範囲の例外（main直接コミット許容）で
  引き続き扱えるが、実際に非issueタスクの需要が残るかどうかは運用しながら見極める。
- **`resume` の「現在地」判定の精度**: `get_branch_work_files` は `<defaultBaseBranch>` との差分で
  plan/worklogファイルを推定するヒューリスティックであり、複数issueを1ブランチで扱う等の
  変則的な運用では正しく機能しない可能性がある。本プロジェクトの通常運用（1ブランチ1issue）を
  前提とする。
- **（issue #6でbash化に伴い解消）`github_get_issue` は `gh` 失敗時に分かりにくい例外を出す**:
  PowerShell版（`GitHub-GetIssue`）では `gh issue view` が失敗した場合の`$LASTEXITCODE`チェックが無く、
  `ConvertFrom-Json` に空入力が渡って`$issue`が`$null`のまま`ConvertTo-Slug -Text $issue.title`が
  呼ばれ、`ParameterBindingValidationException`という原因の分かりにくい例外になっていた
  （issue #5対応時のSessionStart hook検証で実機確認）。bash版は`set -euo pipefail`により
  `gh issue view`自体の失敗時点で`gh`の元のエラーメッセージのまま関数が終了するため、この問題は
  発生しない。
- **SessionStart hookの実機（新規Claude Codeセッション）での動作確認が未実施**: 疑似stdin JSONを
  使った単体テストでは期待通りの挙動を確認したが、実際のセッション開始時にコンテキストへ反映される
  ことは本対応内では未確認。次回以降のセッション開始時に確認する。
- **新規行diff方式（issue #37）は、resumeによって新しい物理位置に再度書き出された重複行までは
  除外しない**: セッション横断カーソルが確実に防ぐのは「同じ行を同じ位置から二重に読むこと」のみで
  あり、「重複した内容が新しい位置（カーソルより後ろ）に現れること」までは防げない（意図的な設計。
  上記「新規行diff方式への移行」参照）。実際にどの程度の頻度・規模で重複が発生するかは実データでの
  継続観測が必要。
- **transcript JSONLの非公開フォーマット依存**: 対応工数レポート機能は、Claude Code非公開の
  内部フォーマットである`transcript_path`のJSONLを自前パースしている。将来のバージョンで形式が
  変わった場合、集計が0件になる（ベストエフォート設計のため実害は対応工数が記録されなく
  なるのみ）。詳細は
  [0006-対応工数レポートはtranscript自前パースで実装する.md](../ddr/0006-対応工数レポートはtranscript自前パースで実装する.md)
  参照。
- **トークン数（`tokensByModel`）は既知の過小カウント要因を持つ**（PR #29レビュー指摘、issue #28）:
  外部調査（[Claude Code JSONL logs undercount tokens](https://gille.ai/en/blog/claude-code-jsonl-logs-undercount-tokens/)）
  によると、Claude Codeのtranscript JSONLはストリーミング応答の開始時点で`usage.input_tokens`等に
  プレースホルダー値（0または1）を書き込み、応答完了後もその値を実際のトークン数へ更新しない
  ケースがあり、結果としてinput側で最大100〜174倍、output側で最大10〜17倍の過小カウントが
  観測されたと報告されている（キャッシュ関連フィールドはAPIレスポンス初期段階で確定するため
  影響を受けにくいとされる）。本機能はこの`transcript_path`を唯一の情報源として自前パースしている
  ため、同じ制約をそのまま引き継ぐ。稼働時間（`activeSeconds`）はトークン数ではなく
  `.timestamp`の差分のみを使うため、この過小カウント問題の影響を受けない（トークン数とは独立した
  精度特性を持つ）。回避策は確立されていない（ステータスバー等、他の情報源を使う代替案は
  transcriptの自前パースという設計方針自体を変えることになり、本機能のスコープ外）。レポート・
  ドキュメント双方で「目安」である旨を明記することで対応する（下記コンポーネント節、
  および`post-push-usage-report.sh`のコメント本文フッター参照）。
- **セッション（transcriptファイル）を跨いだ集計は未対応**: `/resume`等で新しいtranscriptファイルに
  切り替わった場合、旧セッション分の使用量との合算は行わない（新しい`session_id`として
  ゼロから集計が始まる）。
- **状態ファイル書き込みの排他制御が無い**: 複数のClaude Codeセッションが同一ブランチに対して
  同時にhookを発火させた場合、`usage/state/<branch>.json`（issue #37で`.claude/usage-state/`から
  移設）への読み書きにロックが無いため、一方の更新が失われる可能性がある（レースコンディション）。
  単一開発者が同一作業ディレクトリで複数セッションを同時実行する運用は想定しにくいため許容している。
- **ネストしたサブエージェント（depth 2以降）は未対応・未検証**（PR #29レビュー指摘）:
  サブエージェントの`meta.json`には`spawnDepth`フィールドが存在し、理論上サブエージェントが
  さらにサブエージェントを起動するネストがありうるが、このリポジトリの実データでは`depth 1`のみ
  観測され、ネスト時のディレクトリ構造・スキーマ自体が未確認のため対象外とした。将来ネストした
  構造が実際に使われるようになった場合、`_usage_aggregate_and_merge_subagents`の再帰的な拡張を
  別途検討する。
- **サブエージェントの`activeSeconds`はメインと別集計であり重複除去はしていない**（PR #29レビュー
  指摘）: サブエージェント自身のgapベース稼働時間と、メインセッション側の「Taskツール完了待ち」の
  区間（閾値未満なら稼働時間としてそのまま加算される）が時間的に重複しうる。単純合算するとwall
  clock時間より過大になるため、レポート上は両者を合算せず、サブエージェント分は参考値として
  別行に表示するに留めている。
- **（issue #6でbash化に伴い解消）投稿コメント本文へのBOM混入**: PowerShell版では`Add-MrComment`が
  読む一時ファイルを`Set-Content -Encoding UTF8`（Windows PowerShell 5.1既定でBOM付与）で書き出して
  いたため、GitHub上のコメント本文先頭に不可視のBOM文字が入っていた（表示上の実害は無く許容して
  いた）。bash版（`add_mr_comment`）はheredoc/printfでファイルを書き出しBOMが付与されないため、
  この問題は発生しない。
- **稼働時間（`activeSeconds`）は目安であり、2方向の誤差要因がある**（issue #28）:
  `IDLE_GAP_THRESHOLD_SECONDS`（既定300秒）未満の短い待機（人間がすぐ返信した場合等）は稼働時間に
  混入しうる一方、閾値以上の長時間ツール実行（大きめのビルド等）は逆に稼働時間から漏れる。
  加えて`TAIL_BUFFER_SECONDS`（既定30秒）は固定値のため、実際の読了・確認時間との過不足が生じる。
  いずれもgapベースの閾値判定という設計上の単純化によるもので、トークン集計と同様「目安」として
  扱う（レポート本文のラベルにも明記）。
- **複数セッション・複数プロジェクト同時進行時の稼働時間の重複除去（overlap dedup）は未対応**
  （issue #28）: 参考実装（`claude-work-timer`/`claude-code-time-tracking`）は複数セッションが
  並行した場合の区間重複を除去する機能を持つが、本対応のスコープ（単一ブランチ・単一セッション）
  では扱わない。仮に同一ブランチで複数セッションを並行実行した場合、それぞれの`activeSeconds`が
  単純合算され、実際の稼働時間より過大になりうる。
- **（issue #25で追加した`gitlab_new_issue`にも従来からの制約が引き継がれる）GitLab側の動作未検証**:
  本ファイル冒頭の「GitLab側の動作未検証」と同じ制約（実remoteがGitHubのみのため未検証）が
  `gitlab_new_issue`にもそのまま適用される。
