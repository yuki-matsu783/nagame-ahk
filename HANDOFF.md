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

| 進捗 | flow-id | ステップ | 担当 |
|----|---|---|---|
| [x] | 1 | issueを起票する（`.github/ISSUE_TEMPLATE/task.md` / `.gitlab/issue_templates/task.md` で目的・現状・期待する動作・受け入れ条件を記載） | 人間 |
| [x] | 2 | issueの内容を取得する | `start <issue番号>` |
| [x] | 3 | featureブランチ（`feature-<issue番号>-<slug>`）とDraft MRを作成する（既にあれば `sync` のみ） | `start` |
| [x] | 4 | Planモードで実行手順を作成する（`plans/` へ出力・コミット。このタイミングで `worklog/日付_<plan名>.md` を作成） | エージェント |
| [x] | 5 | Planに合意する | 人間 |
| [x] | 6 | commit, push してレビュー依頼を行う | エージェント |
| [x] | 7 | MRで再度planについてレビュー・コメントする。レビュー完了済み連絡をするまで以降の作業は行わない。 | 人間 |
| [x] | 8 | レビュー内容を取得し、planを修正する。対応が完了したコメントには対応内容を返信する（7〜8を合意まで繰り返す） | `comments` / `reply` |
| [x] | 9 | planをもとにMR descriptionを更新する | `describe` |
| [x] | 10 | コンテキスト削減のためにセッションをcompactする | 人間 |
| [x] | 11 | planをもとに作業を進める、作業内容はworklogに更新する | エージェント |
| [] | 12 | commit, push してレビュー依頼を行う | エージェント |
| [] | 13 | 作業内容をもとにMR descriptionを更新する | `describe` |
| [] | 14 | MRでレビュー・コメントする | 人間 |
| [] | 15 | レビュー内容を取得し、実装・ドキュメントを修正する。対応が完了したコメントには対応内容を返信する（11〜15の作業ループを合意まで繰り返す） | `comments` / `reply` |
| [] | 16 | 設計反映: `plans/` `worklog/` の内容を `docs/spec/` `docs/ddr/` へ反映する | エージェント |
| [] | 17 | AIアセット改善: 作業中に気づいたルール・スキルの不備があれば `.claude/rules/` `.claude/skills/` `CLAUDE.md` `AGENTS.md` に反映する | エージェント |
| [] | 18 | commit, push してレビュー依頼を行う | エージェント |
| [] | 19 | MRでレビュー・コメントする | 人間 |
| [] | 20 | レビュー内容を取得し、設計反映・AIアセットの内容を修正する。対応が完了したコメントには対応内容を返信する（16〜20を合意まで繰り返す） | `comments` / `reply` |
| [] | 21 | `plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする | エージェント |
| [] | 22 | commit, push して Draftを解除する | エージェント |
| [] | 23 | マージする（squash merge。ブランチは削除してよい） | 人間 |

## やったこと

- issue #34（対応工数レポートのサブエージェント分が前回pushからの差分になってなさそう）を取得。
  4見出しの過不足なし。
- `feature-34-fix-subagent-effort-diff-since-last-push` ブランチを作成し、Draft PR #35 を作成。
- 原因調査（`_usage_merge_state`が`.agents`スナップショットを引き継がずサブエージェント分が
  常に「差分ゼロ」の前回状態から再計算される不具合）を特定し、再現・修正案の動作確認まで完了。
- ユーザーからの追加指示（agent単位の1行表示化、差分0のagent非表示）を含めてplanを拡張し承認を得た
  （`plans/cheeky-sprouting-pine.md`。旧版は`plans/cheeky-sprouting-pine_act1.md`へ退避）。
- plan・worklog・HANDOFF.mdをcommit・push（flow-id 6）。ユーザーから「レビューOK」の合図を受け、
  `comments all`で未解決スレッドが0件であることを確認済み（flow-id 7〜8）。
  PR #35のdescriptionをplan内容で更新済み（flow-id 9）。
- flow-id 11実装完了:
  - `_usage_merge_state`への`.agents`passthrough追加（push差分バグ本体の修正）
  - `subagentsByType`→`subagents`（agentId単位、agentType・description付き）へのスキーマ変更
  - `_usage_reset_since_last_push`・`_usage_filter_nonzero_subagents`の追加
  - `post-push-usage-report.sh`のサブエージェントテーブルをagentId単位1行表示・0件除外に変更
  - `tests/test_usage_tracking.sh`更新・回帰テスト追加（25→39件、全pass）
  - 実装中に判明した追加修正: Windows版jqのCR混入バグ（`tr -d '\r'`で対応）、
    ツール実行回数の0件フィルタ（ユーザー追加指示）。詳細はworklog参照。

## 次にやること

- flow-id 12: 実装をcommit・pushしてレビュー依頼。

## 判断を迷った内容

（無し）

## 未解決の内容

（無し）

## 守るべき条件・触ってはいけない範囲

（無し）
