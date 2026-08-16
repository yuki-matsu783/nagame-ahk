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
| [x] | 12 | commit, push してレビュー依頼を行う | エージェント |
| [x] | 13 | 作業内容をもとにMR descriptionを更新する | `describe` |
| [x] | 14 | MRでレビュー・コメントする | 人間 |
| [x] | 15 | レビュー内容を取得し、実装・ドキュメントを修正する。対応が完了したコメントには対応内容を返信する（11〜15の作業ループを合意まで繰り返す） | `comments` / `reply` |
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
  この7ファイルはその後 `ff702e7 タイトルを修正` コミットで既にコミット済みになっていることを
  flow-id 11着手時に確認した（コミット済みのため実装コミットへ含める対応は不要になった）。
- Planを作成・承認済み（`plans/noble-painting-waffle.md`）。
- Planレビュー1回目: 「入力待ち時間を稼働時間から除外するロジックになっているか」の指摘を受け、
  gapベースの除外方式にPlanを修正・返信・再レビューOKまで完了（flow-id 7〜8ループ終了）。
- flow-id 11: ユーザー用意の参考実装2件（`参考ディレクトリ/claude-work-timer`,
  `claude-code-time-tracking`。いずれもローカルclone、`.gitignore`で除外済み）を調査し、
  tail buffer（既定30秒）をPlanへ追加。実装中に、開発機のjq（Windowsネイティブ版jq 1.6）が
  `strptime`/`mktime`未実装で`fromdateiso8601`が使えないことが判明したため、自前実装
  （`days_from_civil`アルゴリズム）で代替した。`.claude/hooks/lib/UsageTracking.sh` /
  `post-push-usage-report.sh` の実装、`tests/test_usage_tracking.sh`（新設、12アサーション
  全合格）、ドキュメント（`dev-tools/docs/spec/issue-mr-workflow.md`, `tests/README.md`,
  `.claude/rules/shell-script-style.md`）を更新済み。詳細は
  `worklog/2026-08-16_noble-painting-waffle.md` 参照。

## 次にやること

- flow-id 12・13完了（commit `028d8c7` push済み、PR #29 descriptionを実装状況込みで更新済み）。
  実際のpushでPostToolUse hookが発火し、「対応工数（目安・入力待ち時間を除く）: 36分」の行が
  自動投稿コメントに表示されることを実地確認済み。
- flow-id 14〜15（1回目）: トークン数の既知の過小カウント問題をドキュメントへ反映する指摘に対応・
  返信・push済み（commit `20f8b74`）。この指摘スレッドはユーザーがGitHub上で`resolved`にした。
- flow-id 14〜15（2回目）: ユーザーから「レビュー指摘を記入した」の合図を受け、
  `get_mr_unresolved_comments 29 true`で新規未解決スレッド1件を検出（フッターの免責事項説明文を
  MRへの初回投稿時のみ表示するようにという指摘）。`post-push-usage-report.sh`に
  `is_first_post`判定を追加して対応・返信・push済み（commit `0d96d24`）。実際のpushで
  フッターが2回目以降省略されることを実地確認済み。
  なお、ユーザー（または連携ツール）がフッター文言自体も手動編集していた（簡略化）ため、
  その編集内容は活かしたまま実装した。
  **スレッドの解決（resolved）操作はレビュアー側の操作のため、返信しただけでは`unresolved`のまま**。
  ユーザーに、対応内容の確認とスレッドの解決操作（またはさらなるコメント）を依頼する必要がある。
  flow-id 16（設計反映）以降には、`get_mr_unresolved_comments 29 true`で未解決スレッドが
  0件であることを再確認してから進むこと。

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
