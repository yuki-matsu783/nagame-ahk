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

- issue: #58 調査結果のcanvas形式HTML生成スキルを作る
- ブランチ: feature-58-canvas-format-report-skill
- Draft PR: #59 https://github.com/yuki-matsu783/nagame-ahk/pull/59

| 進捗 | flow-id | ステップ | 担当 |
|----|---|---|---|
| [x] | 1 | issueを起票する（`.github/ISSUE_TEMPLATE/task.md` / `.gitlab/issue_templates/task.md` で目的・現状・期待する動作・受け入れ条件を記載） | 人間（AIが代行する場合は `issue-create` スキル） |
| [x] | 2 | issueの内容を取得する | `start <issue番号>` |
| [x] | 3 | featureブランチ（`feature-<issue番号>-<slug>`）とDraft MRを作成する（既にあれば `sync` のみ） | `start` |
| [x] | 4 | Planモードで**調査計画**を作成する（`plans/<plan名>.md`の「調査」章へ出力・コミット。このタイミングで `worklog/日付_<plan名>.md` を作成） | エージェント |
| [x] | 5 | 調査計画に合意する | 人間 |
| [x] | 6 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [] | 7 | MRで調査計画についてレビュー・コメントする。レビュー完了済み連絡をするまで以降の作業は行わない。 | 人間 |
| [] | 8 | レビュー内容を取得し、調査計画を修正する。対応が完了したコメントには対応内容を返信する（7〜8を合意まで繰り返す） | `comments` / `reply` |
| [] | 9 | 調査計画をもとにMR descriptionを更新する | `describe` |
| [] | 10 | **調査を実施**し、結果を`plans/<plan名>.md`の「調査」章・worklogに記録する。あわせて調査結果を視覚的に分かりやすくまとめた自己完結HTML（TailwindCSS CDN方式）を`reports/<plan名>.html`として作成する | エージェント |
| [] | 11 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [] | 12 | 調査結果をもとにMR descriptionを更新する | `describe` |
| [] | 13 | MRで調査結果についてレビュー・コメントする。レビュー完了済み連絡をするまで以降の作業は行わない。 | 人間 |
| [] | 14 | レビュー内容を取得し、調査結果を修正する。対応が完了したコメントには対応内容を返信する（`reports/<plan名>.html`も調査結果と同期して更新する。10〜14を合意まで繰り返す） | `comments` / `reply` |
| [] | 15 | **調査結果をもとに**Planモードで**作業計画**を作成する（`plans/<plan名>.md`の「作業計画」章へ追記・コミット） | エージェント |
| [] | 16 | 作業計画に合意する | 人間 |
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
| [] | 31 | `plans/` `worklog/` `reports/` を削除し、`HANDOFF.md` を次タスクへリセットする | エージェント |
| [] | 32 | `commit`スキル経由でcommitし、push して Draftを解除する | エージェント |
| [] | 33 | マージする（squash merge。ブランチは削除してよい） | 人間 |

セッションのcompactは任意のタイミングで行ってよく、特定のflow-idには割り当てない。

## やったこと

- issue #48での対話中、通常の一覧・表形式では表現しづらい「複数要素間の関連・依存関係」を
  主題とする調査結果向けに、codecanvas.app的なノード・エッジのcanvas形式が有効だと分かり、
  4種の比較試作（TailwindCSS CDN通常版・自前ミニマムCSSハイブリッド版・リッチ演出版・canvas版）
  をscratchpad上で実施。
- issue #48はスコープ外・完了間近だったため、新規issue #58として起票（`issue-create`スキル）。
  ユーザー要望「ノード・エッジの表現できる幅はリッチにしてほしい」を受け入れ条件に反映。
- `start 58`でブランチ・Draft PR #59を作成し、Planモードで調査計画を作成（承認済み）。

## 次にやること

- flow-id 6: `commit`スキルでcommitし、push してレビュー依頼を行う。
- flow-id 7〜9: MRレビュー→調査計画修正（必要なら）→`describe`でMR description更新。
- flow-id 10: 調査項目1〜7を実施し、`plans/cached-crunching-mochi.md`の「調査結果」章に記録する。
  あわせて`reports/cached-crunching-mochi.html`を試作する。

## 判断を迷った内容

（無し）

## 未解決の内容

（無し）

## 守るべき条件・触ってはいけない範囲

- issue #48自体の内容・成果物は変更しない（既に完了・マージ待ちのため）。
- 検証は「軽めのvibe check」に留める（skill-creatorの本格的な評価ループ・サブエージェント並列
  実行・eval viewerは使わない。ユーザー確認済み）。
