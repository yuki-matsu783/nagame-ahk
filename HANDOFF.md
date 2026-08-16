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
| [] | 7 | MRで再度planについてレビュー・コメントする。レビュー完了済み連絡をするまで以降の作業は行わない。 | 人間 |
| [] | 8 | レビュー内容を取得し、planを修正する。対応が完了したコメントには対応内容を返信する（7〜8を合意まで繰り返す） | `comments` / `reply` |
| [] | 9 | planをもとにMR descriptionを更新する | `describe` |
| [] | 10 | コンテキスト削減のためにセッションをcompactする | 人間 |
| [] | 11 | planをもとに作業を進める、作業内容はworklogに更新する | エージェント |
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

- issue #28（対応工数レポートの日本語修正・経過時間記録追加）を起票内容から着手。
  `feature-28-issue` ブランチ・Draft PR #29 を作成。
- ブランチ作成直後、出所不明の未コミット差分（7ファイル、issue #28の意図と一致する文言統一）を
  発見。ユーザーに確認し、活用する方針で合意（詳細は `worklog/2026-08-16_noble-painting-waffle.md`）。
- Planを作成・承認済み（`plans/noble-painting-waffle.md`）。

## 次にやること

- 人間によるPlanレビュー完了連絡を待つ（flow-id 7〜8）。完了後、flow-id 11から実装に着手する。

## 判断を迷った内容

- 出所不明差分に含まれる、マージ済みDDR（`docs/ddr/0006-...md`）自体のタイトル/本文書き換えを
  活かすかどうか。ユーザー確認の結果「過去に承認済みの対応」とのことで、そのまま活かす方針に確定。

## 未解決の内容

（現時点で無し。前ブランチ（issue #26）由来の「未解決の内容」記載は、該当2ファイル
`.claude/rules/markdown-frontmatter.md` / `worklog/TEMPLATE.md` が現在の作業ツリーで無変更
（差分なし）であることを確認したため解消済みとして整理した）

## 守るべき条件・触ってはいけない範囲

- `docs/ddr/*.md` は原則追記のみ（変更不可）。今回のDDR文言修正は例外としてユーザー承認済みだが、
  それ以外のDDR本文修正は行わない。
