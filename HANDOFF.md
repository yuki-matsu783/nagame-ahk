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

- issue: #37「対応工数レポートの数値が間違っていそうなので集計ロジックを修正する」
- ブランチ: `feature-37-fix-effort-report-aggregation-logic`
- Draft PR: https://github.com/yuki-matsu783/nagame-ahk/pull/47

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
| [] | 10 | コンテキスト削減のためにセッションをcompactする | 人間 |
| [x] | 11 | planをもとに作業を進める、作業内容はworklogに更新する | エージェント |
| [] | 12 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [] | 13 | 作業内容をもとにMR descriptionを更新する | `describe` |
| [] | 14 | MRでレビュー・コメントする。レビュー済み連絡をするまで以降の作業は行わない。 | 人間 |
| [] | 15 | レビュー内容を取得し、実装・ドキュメントを修正する。対応が完了したコメントには対応内容を返信する（11〜15の作業ループを合意まで繰り返す） | `comments` / `reply` |
| [] | 16 | 設計反映: `plans/` `worklog/` の内容を `docs/spec/` `docs/ddr/` へ反映する | エージェント |
| [] | 17 | AIアセット改善: 作業中に気づいたルール・スキルの不備があれば `.claude/rules/` `.claude/skills/` `CLAUDE.md` `AGENTS.md` に反映する | エージェント |
| [] | 18 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [] | 19 | MRでレビュー・コメントする。レビュー済み連絡をするまで以降の作業は行わない。 | 人間 |
| [] | 20 | レビュー内容を取得し、設計反映・AIアセットの内容を修正する。対応が完了したコメントには対応内容を返信する（16〜20を合意まで繰り返す） | `comments` / `reply` |
| [] | 21 | `plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする | エージェント |
| [] | 22 | `commit`スキル経由でcommitし、push して Draftを解除する | エージェント |
| [] | 23 | マージする（squash merge。ブランチは削除してよい） | 人間 |

## やったこと

- issue #37の内容取得、ブランチ・Draft PR作成（flow-id 2〜3）
- 調査（Explore agent + 手動jq調査）で、対応工数レポートの件数ズレの原因を特定
  - 実データで確認: 同一セッションが複数ブランチにわたってresumeされると、transcript JSONL上に
    同一`uuid`の行が複数回（異なる`gitBranch`ラベル付きで）出現する
  - 現行の「毎回全件再パース＋前回累計との引き算」方式は、同一セッションが新しいブランチで
    初めてpushされた際に`prevSession`が存在せず、蓄積済みの全件がその新ブランチの初回差分として
    計上されてしまう
- Plan作成→uuid重複排除案を一度提示したが、「uuidの重複自体は異常ではない（parentUuidチェーン上の
  ノード識別子）」というユーザー指摘によりExitPlanModeが却下され、方針を再設計
  - 採用方針: セッション単位でグローバルなカーソル（`.claude/usage-state/session-cursors/
    <sessionId>.json`の`lastLineCount`）を持ち、push断面ごとに「前回処理済み行数以降の新規行」
    のみを差分として加算していく方式（issue本文が当初提案していた方式）
  - `activeSeconds`（稼働時間）のみ、単調非減少性の前提が崩れるリスクを避けるため既存の
    全件再パース方式を維持
  - あわせてskill/AskUserQuestion/Agent呼び出しの詳細テーブルも同issueで実装することを確認
- Plan承認済み（`plans/inherited-gathering-biscuit.md`）
- flow-id 6完了: plan・worklog・HANDOFF.mdをcommit・push済み
- push直後、ユーザーから追加指示: session-logs/usage-stateを`.claude/`配下から`usage/`
  ディレクトリへ移設してほしい → 実装未着手だったためplan（対応方針A、E、G、H）へ反映し、
  追加commit・push済み
- 「レビューOK」の連絡を受け、`comments all`で未解決スレッドが無いことを確認（自動投稿の
  工数レポートコメントのみで、レビュースレッドは無し）
- flow-id 9: `describe`でPR #47のdescriptionをplan要約で更新済み

- flow-id 11完了: plan対応方針A〜G（`usage/`ディレクトリ移設、カーソル管理、新規行diff集計、
  merge_state書き換え、レポート描画、テスト）を実装。`bash tests/test_usage_tracking.sh`は
  66件全pass。対応方針H（ドキュメント反映）はflow-id 16〜17で実施予定のため未着手

## 次にやること

- flow-id 12: `commit`スキルでcommit・push（レビュー依頼）

## 判断を迷った内容

- （無し。上記「やったこと」に記載した設計方針転換の経緯を参照）

## 未解決の内容

（無し）

## 守るべき条件・触ってはいけない範囲

- `activeSeconds`（稼働時間）の算出ロジックは変更しない（既存の全件再パース＋スナップショット差分を
  維持する。plan「対象外」節参照）
