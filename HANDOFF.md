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

- issue: #48 調査ドキュメントはmarkdownとhtmlで作る
- ブランチ: feature-48-add-html-version-of-investigation-docs
- Draft PR: #57 https://github.com/yuki-matsu783/nagame-ahk/pull/57

| 進捗 | flow-id | ステップ | 担当 |
|----|---|---|---|
| [x] | 1 | issueを起票する（`.github/ISSUE_TEMPLATE/task.md` / `.gitlab/issue_templates/task.md` で目的・現状・期待する動作・受け入れ条件を記載） | 人間（AIが代行する場合は `issue-create` スキル） |
| [x] | 2 | issueの内容を取得する | `start <issue番号>` |
| [x] | 3 | featureブランチ（`feature-<issue番号>-<slug>`）とDraft MRを作成する（既にあれば `sync` のみ） | `start` |
| [x] | 4 | Planモードで**調査計画**を作成する（`plans/<plan名>.md`の「調査」章へ出力・コミット。このタイミングで `worklog/日付_<plan名>.md` を作成） | エージェント |
| [x] | 5 | 調査計画に合意する | 人間 |
| [x] | 6 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [x] | 7 | MRで調査計画についてレビュー・コメントする。レビュー完了済み連絡をするまで以降の作業は行わない。 | 人間 |
| [x] | 8 | レビュー内容を取得し、調査計画を修正する。対応が完了したコメントには対応内容を返信する（7〜8を合意まで繰り返す） | `comments` / `reply` |
| [x] | 9 | 調査計画をもとにMR descriptionを更新する | `describe` |
| [x] | 10 | **調査を実施**し、結果を`plans/<plan名>.md`の「調査」章・worklogに記録する | エージェント |
| [x] | 11 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [x] | 12 | 調査結果をもとにMR descriptionを更新する | `describe` |
| [x] | 13 | MRで調査結果についてレビュー・コメントする。レビュー完了済み連絡をするまで以降の作業は行わない。 | 人間 |
| [x] | 14 | レビュー内容を取得し、調査結果を修正する。対応が完了したコメントには対応内容を返信する（10〜14を合意まで繰り返す） | `comments` / `reply` |
| [x] | 15 | **調査結果をもとに**Planモードで**作業計画**を作成する（`plans/<plan名>.md`の「作業計画」章へ追記・コミット） | エージェント |
| [x] | 16 | 作業計画に合意する | 人間 |
| [] | 17 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [] | 18 | MRで作業計画についてレビュー・コメントする。レビュー完了済み連絡をするまで以降の作業は行わない。 | 人間 |
| [] | 19 | レビュー内容を取得し、作業計画を修正する。対応が完了したコメントには対応内容を返信する（18〜19を合意まで繰り返す） | `comments` / `reply` |
| [] | 20 | 作業計画をもとにMR descriptionを更新する | `describe` |
| [] | 21 | 作業計画をもとに作業を進める、作業内容はworklogに更新する | エージェント |
| [] | 22 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [] | 23 | 作業内容をもとにMR descriptionを更新する | `describe` |
| [] | 24 | MRでレビュー・コメントする。レビュー済み連絡をするまで以降の作業は行わない。 | 人間 |
| [] | 25 | レビュー内容を取得し、実装・ドキュメントを修正する。対応が完了したコメントには対応内容を返信する（21〜25の作業ループを合意まで繰り返す） | `comments` / `reply` |
| [] | 26 | 設計反映: `plans/` `worklog/` の内容を `docs/spec/` `docs/ddr/` へ反映する | エージェント |
| [] | 27 | AIアセット改善: 作業中に気づいたルール・スキルの不備があれば `.claude/rules/` `.claude/skills/` `CLAUDE.md` `AGENTS.md` に反映する | エージェント |
| [] | 28 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [] | 29 | MRでレビュー・コメントする。レビュー済み連絡をするまで以降の作業は行わない。 | 人間 |
| [] | 30 | レビュー内容を取得し、設計反映・AIアセットの内容を修正する。対応が完了したコメントには対応内容を返信する（26〜30を合意まで繰り返す） | `comments` / `reply` |
| [] | 31 | `plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする | エージェント |
| [] | 32 | `commit`スキル経由でcommitし、push して Draftを解除する | エージェント |
| [] | 33 | マージする（squash merge。ブランチは削除してよい） | 人間 |

セッションのcompactは任意のタイミングで行ってよく、特定のflow-idには割り当てない。

## やったこと

- issue #48のタイトル（readme→markdownに修正）・本文4項目を記入。
- `start 48` でブランチ`feature-48-add-html-version-of-investigation-docs`・Draft PR #57を作成。
- Exploreエージェントによる事前調査（issue-mr-flow・docs-workflow・既存のArtifact/html変換関連の
  仕組みの有無等）を実施。
- ユーザーとのAskUserQuestionで主要な設計判断を確定（生成方式=自己完結HTMLをコミット、
  保存場所=`reports/<plan名>.html`・worklogと同じライフサイクル、スタイリング=TailwindCSS CDN第一候補）。
- Planモードで調査計画を作成し、`plans/drifting-sniffing-clover.md`として承認済み。
- 調査計画レビューOK確認（未解決コメント無し）→MR description更新（flow-id 9）。
- 調査を実施（flow-id 10）。調査項目1〜8の結果を`plans/drifting-sniffing-clover.md`の
  「調査結果」章に記録。特に重要な発見: `reportsDir`追加だけでなく`Provider.sh`の
  `get_branch_work_files`改修が必要（詳細はworklog push2参照）。

## 次にやること

- flow-id 11: `commit`スキルでcommitし、push してレビュー依頼を行う。
- flow-id 12〜14: `describe`でMR description更新→MRレビュー→（必要なら）調査結果修正。
- flow-id 15: 調査結果をもとにPlanモードで作業計画を作成する
  （少なくとも SKILL.md・docs-workflow.md・directory-structure.md・.mrworkflow.json・
  Provider.sh(`get_branch_work_files`)・issue-mr-workflow.md・issue-mr-resume.mdの更新を
  スコープに含める見込み）。

## 判断を迷った内容

- flow-id 31の「`plans/` `worklog/` を削除」という記述と、docs-workflow.mdの「plansは永続」という
  記述の整合性について、「ブランチ/PRのコミット履歴には残るがmainのツリーには残らない」という
  解釈で整合させた（詳細はworklog参照）。この解釈の妥当性は要注意。

## 未解決の内容

（無し）

## 守るべき条件・触ってはいけない範囲

- 今回の対象は「調査結果」のHTML化のみ（「調査計画」「作業計画」章は対象外、ユーザー明示）。
- `usage/`配下の対応工数レポート機能自体は変更しない（`reports/`という名称衝突の有無のみ確認）。
