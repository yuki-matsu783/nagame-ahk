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
| [x][x] | 14 | MRでレビュー・コメントする | 人間 |
| [x][x] | 15 | レビュー内容を取得し、実装・ドキュメントを修正する。対応が完了したコメントには対応内容を返信する（11〜15の作業ループを合意まで繰り返す） | `comments` / `reply` |
| [x] | 16 | 設計反映: `plans/` `worklog/` の内容を `docs/spec/` `docs/ddr/` へ反映する | エージェント |
| [x] | 17 | AIアセット改善: 作業中に気づいたルール・スキルの不備があれば `.claude/rules/` `.claude/skills/` `CLAUDE.md` `AGENTS.md` に反映する | エージェント |
| [] | 18 | commit, push してレビュー依頼を行う | エージェント |
| [] | 19 | MRでレビュー・コメントする | 人間 |
| [] | 20 | レビュー内容を取得し、設計反映・AIアセットの内容を修正する。対応が完了したコメントには対応内容を返信する（16〜20を合意まで繰り返す） | `comments` / `reply` |
| [] | 21 | `plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする | エージェント |
| [] | 22 | commit, push して Draftを解除する | エージェント |
| [] | 23 | マージする（squash merge。ブランチは削除してよい） | 人間 |

## やったこと

- issue #28（対応工数レポートの日本語修正・経過時間記録追加）を起票内容から着手。
  `feature-28-issue` ブランチ・Draft PR #29 を作成。
- ブランチ作成直後の出所不明の未コミット差分（7ファイル、issue #28の意図と一致する文言統一）は
  ユーザー確認の上で活用する方針とし、その後 `ff702e7 タイトルを修正` コミットで既にコミット
  済みになっていることを確認した（詳細は `worklog/2026-08-16_noble-painting-waffle.md`）。
- Planを作成・承認・レビュー1回目対応済み（`plans/noble-painting-waffle.md`。flow-id 4〜9完了）。
- flow-id 11: ユーザー用意の参考実装2件（`参考ディレクトリ/claude-work-timer`,
  `claude-code-time-tracking`）を調査し、tail buffer（既定30秒）をPlanへ追加。実装中に、開発機の
  jq（Windowsネイティブ版jq 1.6）が`strptime`/`mktime`未実装で`fromdateiso8601`が使えないことが
  判明したため、自前実装（`days_from_civil`アルゴリズム）で代替した。
  `.claude/hooks/lib/UsageTracking.sh` / `post-push-usage-report.sh` の実装、
  `tests/test_usage_tracking.sh`（新設、12アサーション全合格）、ドキュメント更新まで完了
  （commit `028d8c7`）。
- flow-id 14〜15（レビューループ2往復）: 1往復目はトークン数の既知の過小カウント問題をドキュメントへ
  反映する指摘（commit `20f8b74`）、2往復目はフッターの免責事項説明文をMRへの初回投稿時のみ表示する
  よう変更する指摘（commit `0d96d24`）。いずれも対応・署名付き返信済みで、
  `get_mr_unresolved_comments 29 true`で未解決スレッド0件を確認済み。
- flow-id 16〜17: 実装中に都度`dev-tools/docs/spec/issue-mr-workflow.md`・DDR 0006へ反映していたため
  追加反映は少なかった。AIアセット改善として`.claude/rules/shell-script-style.md`
  （jqのstrptime/mktime制約）・`.claude/rules/directory-structure.md`（`参考ディレクトリ/`の説明）を
  追加。詳細は `worklog/2026-08-16_noble-painting-waffle.md` 参照。

## 次にやること

- flow-id 18: 設計反映・AIアセット改善の変更をcommit, pushしてレビュー依頼を行う。
- flow-id 19〜20: 人間レビュー待ち。レビューOKの合図を受けても`get_mr_unresolved_comments 29 true`
  で未解決スレッドが無いことを必ず確認してから次へ進む。
- flow-id 21: `plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする。
- flow-id 22〜23: commit, push してDraft解除（人間がマージ）。

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
