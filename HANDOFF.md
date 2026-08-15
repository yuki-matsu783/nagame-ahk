# HANDOFF

<!--
セッション間・作業者間の引継ぎメモ（Git管理下）。常に「今の状態」だけを軽量に保つ。
詳細な試行錯誤ログ（何を試した／うまくいった／ダメだったか）は worklog/日付_<planファイル名>.md に書く。
タスク完了・PR作成時（reflect）には、このファイルを次のタスクに向けてリセットする。
-->

## 現在地

- 開発フロー整理タスク（ブランチ: `docs/dev-workflow-rules`）で、`.claude/rules/git-workflow.md`（新設）・
  `.claude/rules/docs-workflow.md`・`.claude/rules/directory-structure.md`・
  `.claude/skills/ahk-implement/SKILL.md`・`HANDOFF.md`（本ファイル）を更新済み。
- 旧HANDOFF.mdの内容（README/DEVELOPERS分割タスクの試行錯誤ログ）は
  `worklog/20260815_fancy-painting-prism.md` に移設済み。

## 次回やること

- 内容に問題なければユーザーがPRを作成し、レビュー・squash mergeを行う。
- 別件として、前回セッションのREADME/DEVELOPERS分割作業（`AGENTS.md` / `DEVELOPERS.md` /
  `README.md` / `plans/fancy-painting-prism.md`）が未コミットのままmain上の作業ツリーに残っている。
  本タスクでは意図的に触れていないので、対応方針は別途ユーザー判断待ち。

## 参照するファイル

- `plans/dreamy-scribbling-pixel.md`（本タスクの計画）
- `.claude/rules/git-workflow.md`（新設したブランチ・worklog・PR運用ルール）
- `.claude/rules/docs-workflow.md`（実装フロー・ドキュメント運用表を更新）

## 判断が分かれるポイント

- `worklog/` はブランチ単位で削除される前提のため `.gitignore` には加えていない
  （削除自体を通常コミットとして記録し、squash mergeでmainに残らないようにする設計）。

## 未解決の質問

- 特になし。

## 守るべき条件・触ってはいけない範囲

- `AGENTS.md` / `DEVELOPERS.md` / `README.md` / `plans/fancy-painting-prism.md` は
  前回セッションの未コミット変更が残っているため、本タスクでは変更しない。
