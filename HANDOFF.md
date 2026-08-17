---
title: HANDOFF
type: handoff
description: セッション間・作業者間の引継ぎメモ（現在地・次回やること等）
tags: [handoff, workflow]
keywords: [フロー進捗, worklog, 引き継ぎ, plan, レビュー]
---

# HANDOFF

<!--
AI⇔AI/AI⇔人間の状況引継ぎメモ。常に「このブランチの現状」を表現する
-->

## フロー進捗状況

- issue: [#43 調査計画→レビュー→調査実施→結果レビュー→作業計画→レビュー→作業実施→結果レビューの流れにする](https://github.com/yuki-matsu783/nagame-ahk/issues/43)
- ブランチ: `feature-43-add-investigation-plan-phase-to-flow`
- Draft PR: [#53](https://github.com/yuki-matsu783/nagame-ahk/pull/53)

**注**: 本タスク自体は、着手時点で有効だった旧23ステップの全体フロー（本タスクで新設する
33ステップ表はこのタスクの成果物であり、まだ有効化されていない）で進行する。

| 進捗 | flow-id | ステップ | 担当 |
|----|---|---|---|
| [x] | 1 | issueを起票する（`.github/ISSUE_TEMPLATE/task.md` / `.gitlab/issue_templates/task.md` で目的・現状・期待する動作・受け入れ条件を記載） | 人間（AIが代行する場合は `issue-create` スキル） |
| [x] | 2 | issueの内容を取得する | `start <issue番号>` |
| [x] | 3 | featureブランチ（`feature-<issue番号>-<slug>`）とDraft MRを作成する（既にあれば `sync` のみ） | `start` |
| [x] | 4 | Planモードで実行手順を作成する（`plans/` へ出力・コミット。このタイミングで `worklog/日付_<plan名>.md` を作成） | エージェント |
| [x] | 5 | Planに合意する | 人間 |
| [x] | 6 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [x] | 7 | MRで再度planについてレビュー・コメントする。レビュー完了済み連絡をするまで以降の作業は行わない。 | 人間 |
| [x] | 8 | レビュー内容を取得し、planを修正する。対応が完了したコメントには対応内容を返信する（7〜8を合意まで繰り返す） | `comments` / `reply` |
| [x] | 9 | planをもとにMR descriptionを更新する | `describe` |
| [x] | 10 | コンテキスト削減のためにセッションをcompactする | 人間 |
| [x] | 11 | planをもとに作業を進める、作業内容はworklogに更新する | エージェント |
| [x] | 12 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [x] | 13 | 作業内容をもとにMR descriptionを更新する | `describe` |
| [x] | 14 | MRでレビュー・コメントする。レビュー済み連絡をするまで以降の作業は行わない。 | 人間 |
| [x] | 15 | レビュー内容を取得し、実装・ドキュメントを修正する。対応が完了したコメントには対応内容を返信する（11〜15の作業ループを合意まで繰り返す） | `comments` / `reply` |
| [x] | 16 | 設計反映: `plans/` `worklog/` の内容を `docs/spec/` `docs/ddr/` へ反映する | エージェント |
| [x] | 17 | AIアセット改善: 作業中に気づいたルール・スキルの不備があれば `.claude/rules/` `.claude/skills/` `CLAUDE.md` `AGENTS.md` に反映する | エージェント |
| [] | 18 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [] | 19 | MRでレビュー・コメントする。レビュー済み連絡をするまで以降の作業は行わない。 | 人間 |
| [] | 20 | レビュー内容を取得し、設計反映・AIアセットの内容を修正する。対応が完了したコメントには対応内容を返信する（16〜20を合意まで繰り返す） | `comments` / `reply` |
| [] | 21 | `plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする | エージェント |
| [] | 22 | `commit`スキル経由でcommitし、push して Draftを解除する | エージェント |
| [] | 23 | マージする（squash merge。ブランチは削除してよい） | 人間 |

## やったこと

- issue #43を取得し、`feature-43-add-investigation-plan-phase-to-flow`ブランチ・Draft PR #53を作成した。
- Planモードで、全体フローに「調査」サイクル（調査計画→レビュー→調査実施→結果レビュー）を
  追加する設計をまとめ、`plans/splendid-dazzling-tower.md`として承認を得た。
- commit・push・レビュー依頼（flow-id 6）を行い、レビューで「セッションをcompactは番号付き
  ステップにしない」という指摘を受けてplanを35→33ステップへ修正・再push（flow-id 7〜8ループ）。
  未解決コメント無しを確認し、planをもとにMR descriptionを更新した（flow-id 9）。
- セッションをcompactした（flow-id 10）。
- planの実施内容1〜5に従い、`.claude/skills/issue-mr-flow/SKILL.md`（全体フローを33ステップへ
  再構成）、`.claude/rules/docs-workflow.md`、`.claude/rules/git-workflow.md`、
  `.claude/skills/commit/SKILL.md`、`dev-tools/docs/spec/issue-mr-workflow.md`（影響範囲へ
  新規ブロック追記）を編集した（flow-id 11）。HANDOFF.mdのフロー進捗状況テーブルの33行化は、
  本タスク自身が旧23ステップで進行中のため次のリセット（flow-id 21）まで意図的に見送った
  （詳細はworklogの「判断」節を参照）。`index.jsonl`の再生成もスコープ外と判断し見送った
  （同worklog参照）。

- commit・push・レビュー依頼（flow-id 12）、MR descriptionの更新（flow-id 13）を行った。
- 「レビューOK」の合図を受けたが、`comments all`で未解決コメントの有無を再確認してから進んだ
  （2件とも解決済みで、未解決コメントは無かった。flow-id 14〜15）。
- worklogの「うまくいったこと」「ダメだったこと」を埋め、既に`dev-tools/docs/spec/issue-mr-workflow.md`
  へ反映済みの内容（影響範囲ブロック）と合わせて設計反映を完了させた（flow-id 16）。
- 作業中に発見した`extract-frontmatter.sh`の懸念（`参考ディレクトリ/`を含む全体スキャンでの
  タイムアウト・破損リスク、原因不明のスコープ外ファイル変更）を
  `dev-tools/docs/spec/extract-frontmatter.md`の「未決定事項・懸念点」へ追記した（flow-id 17）。

## 次にやること

- `commit`スキル経由でcommit・push・レビュー依頼を行う（flow-id 18）。

## 判断を迷った内容

- HANDOFF.mdのフロー進捗状況テーブルを33行化するタイミング: planの実施内容2は「今すぐ33行に
  差し替える」としていたが、本タスク自身がこのHANDOFF.mdで旧23ステップの進捗を追跡中のため、
  今差し替えると進捗表示と矛盾する。次タスクへ向けたリセット（flow-id 21）まで見送ることにした
  （worklog参照）。

## 未解決の内容

（無し）

## 守るべき条件・触ってはいけない範囲

- `dev-tools/docs/ddr/000{9,11,12}-*.md`（DDR）内の過去のflow-id言及は追記のみ・不変の運用のため書き換えない。
- `dev-tools/docs/spec/issue-mr-workflow.md`末尾の「影響範囲」内の既存ブロックは過去の変更履歴のため
  書き換えず、新規ブロックを追記する。
