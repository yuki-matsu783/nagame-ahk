---
name: issue-mr-flow
description: nagame-ahkの開発フロー全体（issue起票〜マージ）の唯一の実装フロー定義。新機能追加・既存動作の変更など、あらゆるタスクをissue起点で進めるときに使う。issue取得、feature-<issue番号>-<内容>ブランチとDraft MRの作成、レビューコメント取得、MR description更新をサブコマンドで行いつつ、設計ドキュメント作成・plan・実装・設計反映・AIアセット改善までの全ステップをこのファイルが定義する。
title: issue駆動 開発フロー
type: skill
tags: [issue-mr-flow, workflow, skill]
keywords: [start, resume, sync, comments, reply, describe, draft-pr, 実装フロー, squash-merge, レビュー返信]
---

# issue駆動 開発フロー（唯一の実装フロー定義）

このファイルは `.claude/scripts/docs/spec/issue-mr-workflow.md` の実装であり、nagame-ahkにおける
**issue起票からマージまでの唯一の実装フロー定義**である。新機能追加・既存動作の変更など、
ごく小さな変更（誤字修正等。`.claude/rules/git-workflow.md` 参照）を除くあらゆるタスクは、
このファイルの手順で進める。

裏側の実処理は `.claude/scripts/src/vcs/Provider.sh`（GitHub/GitLabの差異を吸収する共通関数群。bash版。
設計: `.claude/scripts/docs/spec/shell-scripts.md`）に実装されている。各ステップの手順内で、必要に応じて
Bashツールで以下のようにsourceして使う。

```bash
source .claude/scripts/src/vcs/Provider.sh
```

各関数はJSON文字列をstdoutへ出力する設計のため、`jq`でフィールドを取り出す
（例: `get_issue 6 | jq -r '.title'`）。

プロジェクト固有のパス設定（ブランチ命名規則・`plans/` 等の場所）はリポジトリ直下の `.mrworkflow.json`
から読む（`get_workflow_config`）。他リポジトリへ移植する場合はこのファイルの値を書き換えるだけでよい。

## 全体フロー

担当列: 「人間」＝人間の作業／「サブコマンド」＝下記「サブコマンド」節の `/issue-mr-flow <名前>`／
「エージェント」＝AIエージェントの通常操作（git操作・ファイル編集等）。

| flow-id | ステップ | 担当 |
|---|---|---|
| 1 | issueを起票する（`.github/ISSUE_TEMPLATE/task.md` / `.gitlab/issue_templates/task.md` で目的・現状・期待する動作・受け入れ条件を記載） | 人間（AIが代行する場合は `issue-create` スキル） |
| 2 | issueの内容を取得する | `start <issue番号>` |
| 3 | featureブランチ（`feature-<issue番号>-<slug>`）とDraft MRを作成する（既にあれば `sync` のみ） | `start` |
| 4 | Planモードで**調査計画**を作成する（`plans/<plan名>.md`の「調査」章へ出力・コミット。このタイミングで `worklog/日付_<plan名>.md` を作成） | エージェント |
| 5 | 調査計画に合意する | 人間 |
| 6 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| 7 | MRで調査計画についてレビュー・コメントする。レビュー完了済み連絡をするまで以降の作業は行わない。 | 人間 |
| 8 | レビュー内容を取得し、調査計画を修正する。対応が完了したコメントには対応内容を返信する（7〜8を合意まで繰り返す） | `comments` / `reply` |
| 9 | 調査計画をもとにMR descriptionを更新する | `describe` |
| 10 | **調査を実施**し、結果を`plans/<plan名>.md`の「調査」章・worklogに記録する | エージェント |
| 11 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| 12 | 調査結果をもとにMR descriptionを更新する | `describe` |
| 13 | MRで調査結果についてレビュー・コメントする。レビュー完了済み連絡をするまで以降の作業は行わない。 | 人間 |
| 14 | レビュー内容を取得し、調査結果を修正する。対応が完了したコメントには対応内容を返信する（10〜14を合意まで繰り返す） | `comments` / `reply` |
| 15 | **調査結果をもとに**Planモードで**作業計画**を作成する（`plans/<plan名>.md`の「作業計画」章へ追記・コミット） | エージェント |
| 16 | 作業計画に合意する | 人間 |
| 17 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| 18 | MRで作業計画についてレビュー・コメントする。レビュー完了済み連絡をするまで以降の作業は行わない。 | 人間 |
| 19 | レビュー内容を取得し、作業計画を修正する。対応が完了したコメントには対応内容を返信する（18〜19を合意まで繰り返す） | `comments` / `reply` |
| 20 | 作業計画をもとにMR descriptionを更新する | `describe` |
| 21 | 作業計画をもとに作業を進める、作業内容はworklogに更新する | エージェント |
| 22 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| 23 | 作業内容をもとにMR descriptionを更新する | `describe` |
| 24 | MRでレビュー・コメントする。レビュー済み連絡をするまで以降の作業は行わない。 | 人間 |
| 25 | レビュー内容を取得し、実装・ドキュメントを修正する。対応が完了したコメントには対応内容を返信する（21〜25の作業ループを合意まで繰り返す） | `comments` / `reply` |
| 26 | 設計反映: `plans/` `worklog/` の内容を `docs/spec/` `docs/ddr/` へ反映する | エージェント |
| 27 | AIアセット改善: 作業中に気づいたルール・スキルの不備があれば `.claude/rules/` `.claude/skills/` `CLAUDE.md` `AGENTS.md` に反映する | エージェント |
| 28 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| 29 | MRでレビュー・コメントする。レビュー済み連絡をするまで以降の作業は行わない。 | 人間 |
| 30 | レビュー内容を取得し、設計反映・AIアセットの内容を修正する。対応が完了したコメントには対応内容を返信する（26〜30を合意まで繰り返す） | `comments` / `reply` |
| 31 | `plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする | エージェント |
| 32 | `commit`スキル経由でcommitし、push して Draftを解除する | エージェント |
| 33 | マージする（squash merge。ブランチは削除してよい） | 人間 |

セッションのcompactは任意のタイミングで行ってよく、特定のflow-idには割り当てない（コンテキストが
大きくなってきたと感じたタイミングで、人間の判断で `/compact` を実行すればよい）。

**`start` から着手する場合を除き、このセッションでこのフローのサブコマンドを初めて使う前には、
必ず先に `resume` を実行して「今どこにいるか」を特定する。** `git branch --show-current` 等で
ブランチ名やissue番号が判明していることは、`resume` を省略してよい理由にはならない。`resume` の
目的はブランチ名の特定ではなく、PR/MRの状態・未解決コメント件数・plan/worklogファイル・
HANDOFF.mdとの矛盾など、ブランチ名だけでは分からない「このセッションでまだ確認していない現在地
情報」を集約することにある。
**全体フローのflow-idが進むごとに、必ずどのflow-idまで完了したかをHANDOFF.mdに記載する**

## サブコマンド

呼び出しは `/issue-mr-flow <サブコマンド> [引数]` の形。

### `start <issue番号>` — issue取得・ブランチ/MR作成（全体フロー2〜3）

1. `get_issue <issue番号>` でissueのtitle/body/urlを取得し、内容をユーザーに提示する。
   続けて `test_issue_sections "$(get_issue <issue番号> | jq -r '.body')"` を呼び、標準4見出し
   （目的・現状・期待する動作・受け入れ条件。`.github/ISSUE_TEMPLATE/task.md` /
   `.gitlab/issue_templates/task.md` 参照）の過不足を確認する。欠けている見出しがあれば
   「issue本文に以下の見出しがありません: ...」とユーザーに警告する（処理は止めず、そのまま次へ進む）。
2. issue番号をキーに、既存ブランチの有無を確認する。`.mrworkflow.json` の `branchPrefixTemplate` の
   `{issue}` をissue番号に置換し `{slug}` 以降を `*` に置き換えたパターン
   （既定なら `feature-<issue番号>-*`）で `git branch --list "<pattern>"`（ローカル）・
   `git ls-remote --heads origin "<pattern>"`（リモート）を検索する。slug部分の内容は問わず、
   issue番号のprefix一致のみで判定する（次項の意訳フレーズはAIが都度生成するため非決定的であり、
   slugまで含めた完全一致では同一issueに対して重複してブランチ・Draft MRを作成しかねないため）。
   - 見つかった場合（セッション再開）: そのブランチ名をそのまま使い `sync_branch "<既存ブランチ名>"`
     でfetch・checkoutのみ行う。
   - 見つからない場合（新規作成）:
     a. issueタイトルの意味を汲んだ、ブランチslug用の英語フレーズを考える（3〜6語程度、
        スペース区切りの単語列でよい。kebab-case化・記号除去・小文字化は `to_slug` が行うため
        ここでは不要。直訳ではなく意訳でよい。例:「ブランチ名のslugをリッチにしたい」→
        `enrich branch slug`）。タイトルが元々英語主体の場合はタイトルをそのまま使ってよい。
     b. `new_issue_branch <n> "<a.で考えた英語フレーズ>"` でブランチを作成・checkout・push、
        続けて `new_draft_merge_request <n> "<branch>" "<issue.Title>"`
        （**Draft MRのタイトルには引き続き生のissueタイトルを使う。英語フレーズはブランチ名専用**）
        でDraft MRを作成する。
3. 取得したissue内容をもとに、全体フロー4（Planモードでの調査計画作成）に進む旨をユーザーに案内する。

### `comments [all]` — MRレビューコメントの取得（全体フロー8・15）

1. `get_mr_for_branch "$(git branch --show-current)"` で現在のブランチに紐づくMR番号を取得する。
2. `get_mr_unresolved_comments <n>` で未解決コメントを取得し、そのまま提示する
   （ファイルパス・行番号・スレッドID・該当diffを含む）。対応済み（解決済み）のスレッドは既定で
   機械的に除外される。引数に `all` が指定された場合は `get_mr_unresolved_comments <n> true` で呼び、
   解決済みも含めた全件を取得する。
3. ユーザがプロンプトにおいて指摘を行った場合は、MRにコメントすることを促す。
4. 提示した内容をもとに、`plans/<plan名>.md` を修正する、または設計・実装を修正する
   （この修正作業自体は本スキルの対象外。通常の編集で行う）。対応が完了したコメントには、
   `reply` サブコマンドで対応内容を返信する。

### `reply <threadId> <対応内容>` — レビューコメントへの返信（全体フロー8・15）

1. `get_mr_for_branch "$(git branch --show-current)"` で現在のブランチに紐づくMR番号を取得する
   （`comments` の手順1と同じ）。
2. 返信本文を組み立てる。**AIエージェントが返信する場合は、本文の先頭に必ず
   `Claude Codeより:` の署名行を付ける。** `gh` / `glab` CLIは人間のアカウントで認証
   されているため、GitHub/GitLab上の投稿者アカウントは人間のものとして表示される。誰が書いた
   返信かをレビュアーが判別できるよう、本文側で明示する（`add_mr_thread_reply` 関数は自由文を
   そのまま渡す設計のため、署名の付与は呼び出し側であるこの手順の責務とする）。
3. `add_mr_thread_reply <n> "<threadId>" "<署名付きの対応内容>"` で、
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

3. `get_mr_for_branch "$(git branch --show-current)"` で現在のブランチに紐づくMR番号を取得し
   （`comments` の手順1と同じ）、`set_mr_description <n> <一時ファイル>` で反映する。

### `sync` — セッション再開（全体フロー3の再開版）

対象ブランチ名を引数に取り、`sync_branch "<branch>"` を呼ぶだけの単純なコマンド。
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
3. 提示した内容をもとに、全体フロー33ステップのうちどこから再開すべきかをAIエージェントが判断し、
   次にすべきことを提案する（この判断はサブエージェントではなく呼び出し元が行う）。
4. issue番号が特定できていればブランチ/MRの存在確認へ（`start` 手順2相当）、issueが特定できなければ
   ブランチ命名規則から外れている旨を伝えて `start <issue番号>` での対応を促す。

## レビュー完了合図の確認（全体フロー8・14・19・25・30）

人間から「レビューOK」「合意」等、レビューループを終えて次のステップに進んでよいという合図を
受けても、それだけを根拠に次のステップへ進んではいけない。**必ず `comments all`
（`get_mr_unresolved_comments <n> true`）でスレッドを再取得し、`unresolved` のスレッドが
残っていないか確認する。**

- 残っていなければ、そのまま次のステップに進む。
- 残っていれば、その旨（対象スレッドと内容）を人間に伝えて再確認を取り、解消されるまで次の
  ステップには進まない（GitHub/GitLabのスレッド解決自体はレビュアー側の操作であり、`reply` は
  解決を行わないため、返信済みでも `unresolved` のまま残ることがある）。

## PRがflow-id 31実施前にマージされてしまった場合の対処

人間がレビュー後にそのままMR/PRをマージするなど、flow-id 31（`plans/` `worklog/`の削除・
`HANDOFF.md`のリセット）を実施する前に**先にマージが完了してしまう**ことがある（issue #28,
PR #29のセッションで実際に発生）。この場合、タスク固有の`plans/<plan名>.md`・
`worklog/日付_<plan名>.md`・作業途中のままの`HANDOFF.md`が、そのまま`main`へ残ってしまう
（本来`worklog/`はsquash mergeの対象からflow-id 31で除外され`main`に残らない設計であり、
このズレはdocs-workflow.mdの運用と矛盾する）。

マージ後にこのズレに気づいた場合、**`main`へ直接コミットせず**、以下の手順で対処する
（`main`は共有の正史であり、レビューを経ないままの直接変更は避ける）。

1. `git fetch origin main` 等で最新の`main`を確認し、残ってしまった`plans/`・`worklog/`ファイル・
   `HANDOFF.md`の状態を特定する。
2. 新しいクリーンアップ用ブランチを`main`から作成する（対象のissue番号が無いことが多いため、
   `.mrworkflow.json`の`branchPrefixTemplate`に従う必要はなく、`chore/cleanup-<簡潔な説明>`の
   ような分かりやすい名前でよい）。
3. そのブランチ上で、該当する`plans/`・`worklog/`ファイルを削除し、`HANDOFF.md`を次タスク向けの
   空テンプレートへリセットする（内容はflow-id 31で行うものと同じ）。
4. commit・pushし、`main`を対象にPRを作成する。PR作成・マージの実行は、他のPR操作と同様
   ユーザーから明示的な指示を受けてから行う（`.claude/rules/git-workflow.md`の原則どおり、
   マージ自体は人間が行う）。

## 詳細ルールへのポインタ

全体フローの各ステップに関わる詳細は、以下の既存ルールを参照する（このファイルは順序立った
フローの定義に専念し、内容の重複は避ける）。

- ドキュメントの置き場所・ライフサイクル（`plans/` `worklog/` `docs/spec/` `docs/ddr/` `HANDOFF.md`）:
  `.claude/rules/docs-workflow.md` の「ドキュメント運用」表
- ブランチ命名規則・squash mergeの方針・コミット運用（`commit`スキル必須使用・PreToolUse hookに
  よる技術的強制）: `.claude/rules/git-workflow.md`
- AHKコーディング規約・設計ドキュメントの章立て・実装時のコメント作法:
  `.claude/skills/ahk-implement/SKILL.md`, `.claude/rules/ahk-style.md`
- bashスクリプトの規約（`set -euo pipefail`・jq前提・改行/エンコーディング等）:
  `.claude/rules/shell-script-style.md`
- `Provider.sh`の設計・スクリプト言語選定方針（bash化できる/できない判断基準）:
  `.claude/scripts/docs/spec/shell-scripts.md`

## 前提

- `gh` CLI（GitHubの場合）または `glab` CLI（GitLabの場合）、および `jq` がインストール・認証済みで
  あること。認証情報自体は各CLIの既存ログイン状態に依存し、本スキル側では管理しない。
- リポジトリ直下に `.mrworkflow.json` があること（無い場合は `.claude/scripts/src/vcs/Provider.sh` の
  既定値が使われる）。
- issueは `.github/ISSUE_TEMPLATE/task.md`（GitHub）/ `.gitlab/issue_templates/task.md`（GitLab）の
  テンプレートに沿って「目的・現状・期待する動作・受け入れ条件」を記載しておくことが望ましい
  （必須ではなく、`start` サブコマンドが欠落を警告する）。
