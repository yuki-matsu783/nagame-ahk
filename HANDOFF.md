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

issue #39「コミットSkillを利用するようにルールを記載する」、ブランチ
`feature-39-use-commit-skill-rule`、PR [#40](https://github.com/yuki-matsu783/nagame-ahk/pull/40)。

| 進捗 | flow-id | ステップ | 担当 |
|----|---|---|---|
| [x] | 1 | issueを起票する（`.github/ISSUE_TEMPLATE/task.md` / `.gitlab/issue_templates/task.md` で目的・現状・期待する動作・受け入れ条件を記載） | 人間（AIが代行する場合は `issue-create` スキル） |
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
| [x] | 12 | commit, push してレビュー依頼を行う | エージェント |
| [x] | 13 | 作業内容をもとにMR descriptionを更新する | `describe` |
| [x] | 14 | MRでレビュー・コメントする | 人間 |
| [x] | 15 | レビュー内容を取得し、実装・ドキュメントを修正する。対応が完了したコメントには対応内容を返信する（11〜15の作業ループを合意まで繰り返す） | `comments` / `reply` |
| [x] | 16 | 設計反映: `plans/` `worklog/` の内容を `docs/spec/` `docs/ddr/` へ反映する | エージェント |
| [x] | 17 | AIアセット改善: 作業中に気づいたルール・スキルの不備があれば `.claude/rules/` `.claude/skills/` `CLAUDE.md` `AGENTS.md` に反映する | エージェント |
| [x] | 18 | commit, push してレビュー依頼を行う | エージェント |
| [] | 19 | MRでレビュー・コメントする | 人間 |
| [] | 20 | レビュー内容を取得し、設計反映・AIアセットの内容を修正する。対応が完了したコメントには対応内容を返信する（16〜20を合意まで繰り返す） | `comments` / `reply` |
| [] | 21 | `plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする | エージェント |
| [] | 22 | commit, push して Draftを解除する | エージェント |
| [] | 23 | マージする（squash merge。ブランチは削除してよい） | 人間 |

## やったこと

- issue #39 取得、ブランチ `feature-39-use-commit-skill-rule` / Draft PR #40 作成。
- plan作成（ドキュメントのみ案）→ ユーザーからhook提案を受けPlanモード再突入 →
  ラッパースクリプト＋PreToolUse hookによる技術的強制を含む計画へ拡張し承認取得
  （`plans/tranquil-strolling-shannon.md`。1回目の内容は`_act1`へ退避済み）。
- plan/worklogをcommit・push（flow-id 6）、MR descriptionを更新（flow-id 9）。
- flow-id 7-8: ユーザーから「レビュー完了」の合図を受領後、`comments all`
  （`get_mr_unresolved_comments 40 true`）で未解決スレッドが無いことを確認（自動投稿の対応工数
  レポートのみで、実際のレビューコメントは無かった）。
- flow-id 11: planどおり8ファイルを実装。`dev-tools/src/create-commit.sh`（新規ラッパー）、
  `.claude/hooks/block-direct-git-commit.sh`（新規PreToolUse hook）、`.claude/settings.json`
  （`permissions.deny` + `hooks.PreToolUse`追加）、`.claude/skills/commit/SKILL.md` /
  `.claude/rules/git-workflow.md` / `.claude/skills/issue-mr-flow/SKILL.md` の更新、
  `dev-tools/docs/ddr/0012-...md`（新規DDR）、`extract-frontmatter.sh`によるindex.jsonl再生成。
  詳細は`worklog/2026-08-17_tranquil-strolling-shannon.md`参照。
- エンドツーエンド検証: 直接`git commit`がhookにブロックされること、
  `dev-tools/src/create-commit.sh`経由なら成功することを確認済み。
- flow-id 12: 3コミット（`7a1254e` feat / `c04bc77` docs / `cea4140` chore）＋worklog反映コミット
  （`7406b72`）を作成しpush済み。
- flow-id 13: `describe`でPR #40 descriptionを実装状況ベースへ更新。
- flow-id 14-15: ユーザーから「レビューOK」の合図を受領後、`comments all`で再確認。未解決の
  レビューコメントは無く（自動投稿の対応工数レポートのみ）、修正対応なし。
- flow-id 16: plan「対象外」節の通りdocs/spec反映対象なし。DDR 0012が既にflow-id 11で
  作成済みのため追加反映不要と判断。
- flow-id 17: このセッションで実際に2回発生した「hookの部分文字列マッチがコミットメッセージ・
  PR description中の"git commit"という地の文にも誤反応する」実例を、
  `.claude/rules/git-workflow.md`のコミット運用節へAIエージェント向け注記として追記。
- flow-id 18: 上記flow-id 13-17の変更を1コミット（`a089cdd`）にまとめてcommit・push済み。

## 次にやること

flow-id 19（人間レビュー待ち）。レビュー完了の合図を受けたら`comments all`で再確認してから
flow-id 21（plans/worklog削除・HANDOFF.mdリセット）へ進む。

## 判断を迷った内容

- flow-id 9（describe）を、flow-id 7-8の人間レビュー完了前に実施した（レビュアーがMR description
  上でplan内容を確認できるようにするため）。flow-idの数字順とは前後するが、7に「レビュー完了まで
  次の作業をしない」というブロック条件があるのはflow-id 9以降の話であり、9自体を先に行うことは
  妨げていないと判断した。

## 未解決の内容

（無し。hookの部分文字列マッチによる誤検知の実例はflow-id 17で
`.claude/rules/git-workflow.md`へ注記として反映済み）

## 守るべき条件・触ってはいけない範囲

（無し）
