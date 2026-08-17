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

- issue #24を取得し、featureブランチ・Draft PR #55を作成した。
- Exploreサブエージェントで`dev-tools/`配下の構成・参照元を事前調査した上で、`plans/delegated-gathering-frog.md`に調査計画（調査の目的・調査項目8点・調査対象外・調査方法）を作成し、人間の承認を得た。
- `commit`スキル経由でcommit・push、`describe`でPR #55のdescriptionを調査計画の内容で更新した。
- 人間からレビュー完了の連絡を受け、`comments all`で未解決スレッドが無いことを確認した（自動投稿の対応工数レポートのみで、レビューコメントは無し）。
- 調査を実施（flow-id 10）。追加のgrepでExplore結果の裏取りを行い、`plans/delegated-gathering-frog.md`の「調査」章に「調査結果」（ファイル分類・参照箇所一覧・hooksとの役割整理・プラグイン配布の既存記述有無・directory-structure.md記載の乖離・移行先ディレクトリ構成案・stale参照）を追記、worklogにも記録した。
- 人間からチャットで「`extract-frontmatter.sh`と判断が分かれる部分も移行して」との指摘を受け、調査結果を修正（`extract-frontmatter.sh`・`shell-scripts.md`・`extract-frontmatter.md`・DDR`0008`を移行対象に変更）。commit・push、PR descriptionも更新した。
- `comments all`で未解決スレッドが無いことを再確認し、調査結果レビュー完了とした（flow-id 13〜14）。
- 調査結果をもとにPlanモードで作業計画を作成し（`plans/delegated-gathering-frog.md`の「作業計画」章）、人間の承認を得た（flow-id 15〜16）。

## 次にやること

- `commit`スキル経由でcommit・push・レビュー依頼を行う（flow-id 17）。
- PR #55で作業計画についての人間のレビューを待つ（flow-id 18）。レビューコメントがあれば`comments`/`reply`で対応する（flow-id 19のループ）。
- レビュー完了後、`describe`でMR descriptionを更新（flow-id 20）してから、作業計画に沿って実装を進める（flow-id 21）。

## 判断を迷った内容

- issue本文の移行先表記（「.claudeのscripts配下」「scripts/src」「scripts/docs」）から`.claude/scripts/src/`・`.claude/scripts/docs/`と解釈した（作業計画で確定）。
- `shell-scripts.md`（`dev-tools/`に残る`build.sh`の規約も含む）を移行対象に含めた結果、移行後も`build.sh`から参照可能な状態をどう保つかは実装時に検討する。
- 作業計画作成時に`.claude/agents/issue-mr-resume.md`を精読した結果、調査結果7番で想定していた「移行対象パスの書き換えのみ」では不十分と判明（旧PowerShell版Provider.ps1・PascalCase関数を前提とした記述で、単純なパス書き換えでは済まない全面的な作り直しが必要）。dev-tools分離とは独立した既存バグのため、本issueのスコープからは除外し、**別issueとしての起票を推奨する**。

## 未解決の内容

（無し）

## 守るべき条件・触ってはいけない範囲

- 調査計画の「調査対象外」に記載の通り、実際のファイル移動・パス書き換えは行っていない（flow-id 10以降で実施）。
