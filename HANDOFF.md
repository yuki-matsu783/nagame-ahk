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

- issue: [#24 dev-toolsをAI・人間が利用するものと人間のみが利用するもので分ける](https://github.com/yuki-matsu783/nagame-ahk/issues/24)
- ブランチ: `feature-24-separate-ai-human-dev-tools`
- Draft PR: [#55](https://github.com/yuki-matsu783/nagame-ahk/pull/55)

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
| [x] | 9 | 調査計画をもとにMR descriptionを更新する | `describe` |
| [] | 10 | **調査を実施**し、結果を`plans/<plan名>.md`の「調査」章・worklogに記録する | エージェント |
| [] | 11 | `commit`スキル経由でcommitし、push してレビュー依頼を行う | エージェント |
| [] | 12 | 調査結果をもとにMR descriptionを更新する | `describe` |
| [] | 13 | MRで調査結果についてレビュー・コメントする。レビュー完了済み連絡をするまで以降の作業は行わない。 | 人間 |
| [] | 14 | レビュー内容を取得し、調査結果を修正する。対応が完了したコメントには対応内容を返信する（10〜14を合意まで繰り返す） | `comments` / `reply` |
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
| [] | 31 | `plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする | エージェント |
| [] | 32 | `commit`スキル経由でcommitし、push して Draftを解除する | エージェント |
| [] | 33 | マージする（squash merge。ブランチは削除してよい） | 人間 |

セッションのcompactは任意のタイミングで行ってよく、特定のflow-idには割り当てない。

## やったこと

- issue #24を取得し、featureブランチ・Draft PR #55を作成した。
- Exploreサブエージェントで`dev-tools/`配下の構成・参照元を事前調査した上で、`plans/delegated-gathering-frog.md`に調査計画（調査の目的・調査項目8点・調査対象外・調査方法）を作成し、人間の承認を得た。
- worklog（`worklog/2026-08-17_delegated-gathering-frog.md`）に事前調査で判明した内容の下書きを記録した。
- `commit`スキル経由でcommit・push、`describe`でPR #55のdescriptionを調査計画の内容で更新した。

## 次にやること

- PR #55で調査計画についての人間のレビューを待つ（flow-id 7）。
- レビューコメントがあれば`comments`/`reply`で対応し、調査計画を修正する（flow-id 8のループ）。
- レビュー完了後、flow-id 10「調査を実施」へ進む。事前調査（Explore結果）は`plans/delegated-gathering-frog.md`本体・worklogへ正式に記録済みの下書きがあるため、それをベースに整形する想定。

## 判断を迷った内容

- issue本文の移行先表記（「.claudeのscripts配下」「scripts/src」「scripts/docs」）から`.claude/scripts/src/`・`.claude/scripts/docs/`と解釈したが、最終確定は作業計画（flow-id 15）で行う。
- `shell-scripts.md`（AI専用スクリプトと人間専用`build.sh`の両方を対象とする規約）・既マージ済みDDRの移動要否は、調査結果を踏まえて作業計画で決定する方針とした。

## 未解決の内容

（無し）

## 守るべき条件・触ってはいけない範囲

- 調査計画の「調査対象外」に記載の通り、実際のファイル移動・パス書き換えは行っていない（flow-id 10以降で実施）。
