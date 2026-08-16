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
| [x] | 7 | MRで再度planについてレビュー・コメントする | 人間 |
| [x] | 8 | レビュー内容を取得し、planを修正する。対応が完了したコメントには対応内容を返信する（7〜8を合意まで繰り返す） | `comments` / `reply` |
| [x] | 9 | planをもとにMR descriptionを更新する | `describe` |
| [x] | 10 | コンテキスト削減のためにセッションをcompactする | 人間 |
| [x] | 11 | planをもとに作業を進める、作業内容はworklogに更新する | エージェント |
| [x] | 12 | commit, push してレビュー依頼を行う | エージェント |
| [x] | 13 | 作業内容をもとにMR descriptionを更新する | `describe` |
| [x] | 14 | MRでレビュー・コメントする | 人間 |
| [x] | 15 | レビュー内容を取得し、実装・ドキュメントを修正する。対応が完了したコメントには対応内容を返信する（11〜15の作業ループを合意まで繰り返す） | `comments` / `reply` |
| [x] | 16 | 設計反映: `plans/` `worklog/` の内容を `docs/spec/` `docs/ddr/` へ反映する | エージェント |
| [x] | 17 | AIアセット改善: 作業中に気づいたルール・スキルの不備があれば `.claude/rules/` `.claude/skills/` `CLAUDE.md` `AGENTS.md` に反映する | エージェント |
| [] | 18 | commit, push してレビュー依頼を行う | エージェント |
| [] | 19 | MRでレビュー・コメントする | 人間 |
| [] | 20 | レビュー内容を取得し、設計反映・AIアセットの内容を修正する。対応が完了したコメントには対応内容を返信する（16〜20を合意まで繰り返す） | `comments` / `reply` |
| [] | 21 | `plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする | エージェント |
| [] | 22 | commit, push して Draftを解除する | エージェント |
| [] | 23 | マージする（squash merge。ブランチは削除してよい） | 人間 |

## やったこと

- issue #26取得、ブランチ`feature-26-plan`・Draft PR #27作成。
- plan `plans/groovy-twirling-puffin.md` 作成・承認、worklog `worklog/20260816_groovy-twirling-puffin.md` 作成。
- 実装完了・commit/push・PR description更新済み:
  - `dev-tools/src/archive-reentrant-plan.sh` 新規作成（plan/worklogの`_actN`退避）
  - `tests/test_archive_reentrant_plan.sh` 新規作成（19アサーション成功）
  - `.claude/rules/plan-mode-safety.md` 規則6全面改訂・規則2改題（ユーザー指摘対応）

- レビュー完了確認（`comments all`で未解決コメント無し。自動使用量レポートのみ）済み（flow-id 14〜15）。
- 設計反映: `dev-tools/docs/ddr/0009-...md` を新規作成し、`dev-tools/docs/README.md`索引に追記
  （flow-id 16）。規則改訂自体は実装（flow-id 11）で完了済みのためAIアセット改善（flow-id 17）は
  追加対応不要と判断。

## 次にやること

- flow-id 18: 本反映のcommit/push・レビュー依頼。
- レビュー完了後、flow-id 21（plans/worklog削除・HANDOFFリセット）→22（Draft解除）→23（人間がマージ）。

## 判断を迷った内容

- EnterPlanMode/ExitPlanModeをhookで自動フックする案は見送り、規則6は引き続き
  エージェントが手順として読んで実行する運用のままとした（`plans/groovy-twirling-puffin.md`
  「対象外」節参照）。

## 未解決の内容

- 作業ツリーに、自分では作成していない未コミットの変更が2件存在する（issue #26と無関係、
  origin不明のため触っていない）:
  - `.claude/rules/markdown-frontmatter.md`: type表の`template`行が`log`行（`worklog/*.md`）に置換
  - `worklog/TEMPLATE.md`: `type: template` → `type: log`
  - 内容的には一貫しており、自分のworklogファイルのtypeも`log`とした（この点は矛盾なし）。

## 守るべき条件・触ってはいけない範囲

- `.claude/rules/plan-mode-safety.md`の「背景」節（2026-08-15事故の記録）は変更しない
  （規則6本文のみ改訂）。
- 上記「未解決の内容」の2ファイルの未コミット変更は、origin確認・ユーザー判断が付くまで
  コミット・破棄いずれも行わない。
