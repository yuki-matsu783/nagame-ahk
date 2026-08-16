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

issue #45「commitスキルをAskUserQuestion確認なしで実行するよう変更」、ブランチ
`feature-45-commit-skill-skip-confirmation`、PR [#46](https://github.com/yuki-matsu783/nagame-ahk/pull/46)。

| 進捗 | flow-id | ステップ | 担当 |
|----|---|---|---|
| [x] | 1 | issueを起票する（`.github/ISSUE_TEMPLATE/task.md` / `.gitlab/issue_templates/task.md` で目的・現状・期待する動作・受け入れ条件を記載） | 人間（AIが代行する場合は `issue-create` スキル） |
| [x] | 2 | issueの内容を取得する | `start <issue番号>` |
| [x] | 3 | featureブランチ（`feature-<issue番号>-<slug>`）とDraft MRを作成する（既にあれば `sync` のみ） | `start` |
| [x] | 4 | Planモードで実行手順を作成する（`plans/` へ出力・コミット。このタイミングで `worklog/日付_<plan名>.md` を作成） | エージェント |
| [x] | 5 | Planに合意する | 人間 |
| [x] | 6 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [] | 7 | MRで再度planについてレビュー・コメントする。レビュー完了済み連絡をするまで以降の作業は行わない。 | 人間 |
| [] | 8 | レビュー内容を取得し、planを修正する。対応が完了したコメントには対応内容を返信する（7〜8を合意まで繰り返す） | `comments` / `reply` |
| [x] | 9 | planをもとにMR descriptionを更新する | `describe` |
| [x] | 10 | コンテキスト削減のためにセッションをcompactする | 人間 |
| [x] | 11 | planをもとに作業を進める、作業内容はworklogに更新する | エージェント |
| [x] | 12 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [x] | 13 | 作業内容をもとにMR descriptionを更新する | `describe` |
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

- ユーザー依頼を`issue-create`スキルで起票（issue #45）。ブランチ
  `feature-45-commit-skill-skip-confirmation` / Draft PR #46 を作成
  （`new_draft_merge_request`初回失敗→空コミット追加で自動リトライ成功）。
- Planモード中、issue #39（PR #40）未マージが判明。ユーザーへ確認しPR #40のマージを待機、
  マージ確認後（`git show origin/main:...`で内容確認）に計画確定・承認取得。
- 承認後、ブランチを最新`origin/main`へrebase・`--force-with-lease`でpush。
- flow-id 6: plan/worklogをcommit（`bb13408`）・push。
- flow-id 9: `describe`でPR #46 descriptionを更新。
- 「レビューOK」の合図を受け、ルール通り`comments all`で再確認（未解決スレッド無し）してから
  flow-id 11へ進行。
- flow-id 11: `.claude/skills/commit/SKILL.md`を計画通り編集（Step 3削除・Step番号振り直し・
  複数prefix自動分割の明記等）。計画外の見落とし2点（冒頭説明文の「対話的に進める」表現、
  「呼び出しタイミング」節の旧Step番号参照）も合わせて修正。詳細は
  `worklog/2026-08-17_tranquil-strolling-shannon.md` 参照。
- flow-id 12: 更新後のスキル手順（確認なし）を実際に使ってcommit（`e4ebd33`）・push。
- flow-id 13: `describe`でPR #46 descriptionを実装状況込みで更新。

## 次にやること

flow-id 14（人間レビュー待ち）。レビュー完了の合図を受けたら`comments all`で確認してから
flow-id 16（設計反映: plans/worklogの内容をdocs/spec, docs/ddrへ反映）へ進む。

## 判断を迷った内容

（無し）

## 未解決の内容

（無し）

## 守るべき条件・触ってはいけない範囲

（無し）
