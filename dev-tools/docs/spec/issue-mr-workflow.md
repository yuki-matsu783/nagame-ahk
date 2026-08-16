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
[dev-tools/docs/ddr/0002-issue-mr-flowへの実装フロー統合.md](../ddr/0002-issue-mr-flowへの実装フロー統合.md) 参照。

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
└── lib/
    └── UsageTracking.sh              # 集計ロジック（sync_usage_state）
```

上記は全てbash製（`.sh`）。issue #6でPowerShell版（`.ps1`）から移行した。設計方針・移行の経緯・
git bash特有の注意点は [shell-scripts.md](shell-scripts.md) を参照。

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
| `new_issue_branch <n> <title>` | `<branchPrefixTemplate>` に従いブランチを作成しcheckout、リモートpush | `git switch -c` + `git push` | 同左 |
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

呼び出し元は、このサマリをもとに全体フロー23ステップのうちどこから再開すべきかを判断し、
人間に提案する（この判断自体はサブエージェントの役割ではなく、呼び出し元が行う）。

`comments` / `describe` サブコマンドの「現在のブランチに紐づくMR番号を取得する」手順は、
重複実装を避けるため `get_mr_for_branch` に統一する。

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
  （`activeSeconds`。下記「稼働時間の算出方法」参照）。推定コスト(USD)・ファイルdiff・プロンプト本文・
  サブエージェント詳細往復は対象外。
  - **ツール実行回数は「実際に呼び出されたツールの集計」であり、利用可能な全ツール種別の固定
    カタログではない**（PR #29レビュー指摘）。[ツールリファレンス](https://code.claude.com/docs/en/tools-reference)
    に載っている多数のツールのうち、そのpush間隔で一度も呼び出されなかったツールは単純に
    行として現れない（0件のツールを列挙する設計にはしていない。トークン数のモデル別テーブルで
    全項目0の行を表示しないようにした対応と同じ考え方）。加えて、サブエージェント（`Task`/`Agent`
    ツール等で起動される別セッション）内部で行われたツール呼び出しは、そのサブエージェント自身の
    transcriptに記録され、本スクリプトが読むメインセッションの`transcript_path`には含まれないため、
    ここには反映されない（上記「サブエージェント詳細往復は対象外」の一部）。
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
  - `activeSeconds`は`assistantCount`と同じ「0始まりの累計値」という性質を持つため、
    `_usage_merge_state`側は既存の`turns`と全く同じ差分計算パターン（`current - prevSession値`、
    前回スナップショット無しなら`current - 0`、下限0）をそのまま流用する。セッションごとの永続状態
    （`sessions[<sessionId>]`）には`lastActiveSeconds`を`lastTokens`等と同様に保存する。
  - 複数セッション・複数プロジェクトが同時進行した場合の区間重複除去（overlap dedup。参考実装が
    持つ機能）は、本対応のスコープ外（単一ブランチ・単一セッションの範囲で完結する対応工数レポート
    のため）。将来必要になった場合に別issueで検討する。
- **コンポーネント**:
  - `.claude/hooks/lib/UsageTracking.sh`（共有ライブラリ、bash版。issue #6でPowerShell版から移行）:
    `sync_usage_state <repoRoot> <branch> <sessionId> <transcriptPath>` が集計本体。`transcript_path`
    のJSONLをjqで1行ずつパースし（不正な行・空行は無視するベストエフォート）、
    `.gitBranch == <branch>` のエントリのみを対象に、`message.usage`（モデル別トークン数）、
    `message.content[].type=="tool_use"`（ツール名別呼び出し回数）、該当エントリ件数
    （assistant応答回数）、および`.timestamp`のgapベース算出による稼働時間（`activeSeconds`。
    算出方法は上記「稼働時間の算出方法」参照）を集計する。前回このセッションで記録した累計との
    **差分**を、ブランチ単位の状態ファイル（`.claude/usage-state/<branch>.json`、gitignore対象）の
    `sinceLastPush` へ加算する（トークン・ツール回数・応答回数・稼働時間のいずれも同じ
    「差分を加算」方式）。
  - `.claude/hooks/post-push-usage-report.sh`（`PostToolUse` hook、bash版）: `.claude/settings.json` の
    matcher `Bash|PowerShell` と `if: "Bash(git push*)"` / `if: "PowerShell(git push*)"` により
    `git push` を含むコマンド実行後のみ発火する（マッチしなければプロセス起動自体が行われず、
    通常のBash/PowerShell利用への性能影響は無い）。投稿要否判定の前に自分で `sync_usage_state` を
    呼んで状態を最新化してから投稿する（ターンの途中でのpushでも記録漏れが起きないようにするため）。
    `sinceLastPush` が全て0なら投稿しない。`get_mr_for_branch` でMRが無ければ投稿しない。
    投稿成功後のみ `sinceLastPush` をリセットする（失敗時は次回pushへ繰り越す。git push自体は
    ブロックしない）。hookの起動コマンドは`"bash"`（PATH解決に依存。詳細:
    [shell-scripts.md](shell-scripts.md)）。コメント本文には`fmt_duration`（秒→`H時間M分`/`M分`
    形式）で整形した「対応工数（目安・入力待ち時間を除く）」の行を含める。
  - `.claude/settings.json`: `hooks.PostToolUse` を追加。
  - `.gitignore`: `/.claude/usage-state/` を追加。
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

## 設定項目

`.mrworkflow.json`（nagame-ahk向けの初期値）

```jsonc
{
  "branchPrefixTemplate": "feature-{issue}-{slug}",
  "defaultBaseBranch": "main",
  "plansDir": "plans",
  "worklogDir": "worklog",
  "specDirs": ["docs/spec", "dev-tools/docs/spec"],
  "ddrDirs": ["docs/ddr", "dev-tools/docs/ddr"]
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
  [dev-tools/docs/ddr/0003-レビュースレッド解決は自動化しない.md](../ddr/0003-レビュースレッド解決は自動化しない.md)
  参照。
- **AI返信のアイデンティティ表示**: `Add-MrThreadReply` の投稿者アカウントはAI/人間で分離できない
  （`gh`/`glab` CLIは人間の認証情報を使うため）。かわりに返信本文の先頭に `Claude Codeより:` の
  署名行を必ず付ける運用ルールを `reply` サブコマンド手順に追加した。botアカウントによる
  投稿者分離は規模超過のため見送り。背景・却下案は
  [dev-tools/docs/ddr/0004-AI返信は署名で識別しbotアカウント分離は見送る.md](../ddr/0004-AI返信は署名で識別しbotアカウント分離は見送る.md)
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

## 未決定事項・懸念点

- **GitLab側の動作未検証**: このリポジトリの実remoteはGitHubのみのため、`Gitlab.sh`（`gitlab_get_mr_unresolved_comments`
  の解決済み含む分岐、`gitlab_add_mr_thread_reply` を含む。issue #6でbash化したが未検証の構造は
  PowerShell版から変わっていない）はAPI仕様を調べた上での実装となり、実機での動作確認ができていない。
  GitLab側のテスト方法（別リポジトリ用意等）は今後の課題。
- **他リポジトリへの移植性の検証**: `.mrworkflow.json` による切り出しで足りるか、実際に他リポジトリへ
  導入してみないと確認できない。今回はnagame-ahk上での実装・検証にとどめる。
- **全角文字のみのissueタイトルのスラッグ化**: `to_slug`（旧`ConvertTo-Slug`）はASCII英数字のみを
  残す簡易実装のため、
  「開発フローを変える」のような全角文字のみのタイトルは空文字となり `issue` にフォールバックする
  （実機確認: issue #3 で確認済み）。ブランチ名は `feature-<issue番号>-issue` のように番号のみで
  区別される形になるが、番号自体が一意なため実害はない。より説明的なスラッグが必要になった場合は
  ローマ字変換等の対応を別途検討する。
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
  同時にhookを発火させた場合、`.claude/usage-state/<branch>.json`への読み書きにロックが無いため、
  一方の更新が失われる可能性がある（レースコンディション）。単一開発者が同一作業ディレクトリで
  複数セッションを同時実行する運用は想定しにくいため許容している。
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
