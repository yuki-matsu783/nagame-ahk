# 開発フロー整理: worklog分離 + ブランチ/PR/squash merge運用の導入

## Context

現状は「実装フロー（必須）」（`.claude/rules/docs-workflow.md`）で spec 承認 → planモード → 実装、という流れは定義済みだが、以下が未整理だった。

- 全作業がmainへの直接コミットで行われており、ブランチ／PRの概念がルールに存在しない。
- `HANDOFF.md` は「試したこと／うまくいったこと／ダメだったこと」という詳細な作業ログと、「次回やること」等の軽量な引継ぎ情報が同居しており、肥大化しやすい。
- セッションをまたいだ知見の蓄積を、いつ・どうやって `docs/spec` や `docs/adr`（＝正史）に反映し、作業ログ側を片付けるかのタイミングが決まっていない。

ユーザーの意向：
- `docs/`配下は決定事項と経緯のみを書く正史とする。
- セッションの知見蓄積はブランチ上のコミットとしては自由に残してよいが、PR作成前に spec/adr へ反映したうえで作業ログを消去し、squash mergeでmainには正史のみが残るようにする。
- `HANDOFF.md` は「現在地／次回やること／参照ファイル／判断が分かれるポイント／未解決の質問／守るべき条件」に絞った軽量な引継ぎメモとして残す（セッション間の引継ぎ・人間への説明用）。詳細な試行錯誤ログは新設の `worklog/` ディレクトリへ分離する。
- PR作成・マージ（squash）は人間が実施し、AIエージェントはブランチでの実装・reflectまでを担当する。

なお、現在の作業ツリーには前回セッション（README/DEVELOPERS分割）の未コミット変更（`AGENTS.md`, `DEVELOPERS.md`, `README.md`, `plans/fancy-painting-prism.md`）が残っているが、これは今回のタスクとは別件として一切変更しない。今回のタスクは新規ブランチ `docs/dev-workflow-rules` を作成しコミットする。

## 変更内容

### 1. 新規ルール `.claude/rules/git-workflow.md`

`alwaysApply: true` フロントマターを付け、既存の `directory-structure.md` / `docs-workflow.md` と同じ形式にする。内容:

- 適用範囲: `docs-workflow.md`の実装フロー対象タスクに適用（誤字修正等の軽微な変更はmain直接コミットも許容）。
- ブランチ運用: 着手前にfeatureブランチを作成（`feat/`, `fix/`, `docs/` 等のプレフィックス）。
- worklogとreflect: `worklog/日付_<planファイル名>.md` の作成・書き足しタイミング、PR作成前のreflect手順（spec反映→adr起票→worklog削除→HANDOFF.mdリセット）。
- PR・マージ: PR作成・レビュー・squash mergeは人間が実施し、AIは`gh pr create`/`gh pr merge`等を明示的な指示なしには実行しない。squash mergeによりworklogの試行錯誤はmainに残らずPR側のコミット履歴にのみ残る旨。

### 2. `.claude/rules/docs-workflow.md` の更新

- 「実装フロー（必須）」の番号付き手順に以下を反映:
  - 先頭にブランチ作成ステップを追加（`git-workflow.md`参照）。
  - planモード完了時に `worklog/日付_<planファイル名>.md` を作成する旨を追記。
  - 実装中の試行錯誤は worklog に書き、HANDOFF.mdは軽量な状態のみを保つ旨に修正。
  - 完了後のステップに「reflect」（spec上書き・adr起票・worklog削除・HANDOFF.mdリセット）とPR作成・squash mergeへの導線を追記。
- 「ドキュメント運用」表を更新:
  - `HANDOFF.md` 行: 対象を「人間＋AI」に、寿命を「短期（常に最新状態のみ。詳細はworklogへ）」に、内容を新テンプレの6項目に、運用説明をタスク完了・PR作成時にリセットする旨に更新。
  - `worklog/日付_<planファイル名>.md` 行を新設（対象・寿命・内容・運用）。squash merge前提のため`.gitignore`には加えず、削除自体を通常コミットとして記録する旨を明記。
- 末尾の「HANDOFF.mdは空でも…」の一文を新テンプレの見出し前提に書き換える。

### 3. `.claude/rules/directory-structure.md` の更新

- ツリー図の `plans/` の直後に `worklog/` を追加（役割・reflectでの削除・参照先コメント付き）。
- ツリー図の `HANDOFF.md` コメントを新しい役割（軽量な引継ぎメモ）に書き換える。

### 4. `.claude/skills/ahk-implement/SKILL.md` の更新

`docs-workflow.md`と内容を揃える（手順3・手順5の記述をworklog/reflect/ブランチ運用に合わせて更新）。

### 5. `HANDOFF.md` の書き換え

- 冒頭コメントと本文を新テンプレート（現在地／次回やること／参照するファイル／判断が分かれるポイント／未解決の質問／守るべき条件・触ってはいけない範囲）に置き換える。
- 現在の本文（README/DEVELOPERS分割タスクの「試したこと／うまくいったこと／ダメだったこと／次の一歩」）は内容を保持したまま `worklog/20260815_fancy-painting-prism.md` へ移設し、新運用の実例とする（`plans/fancy-painting-prism.md`自体は変更しない）。

### 6. Git操作

- 新規ブランチ `docs/dev-workflow-rules` を作成してから上記1〜5を実施・コミットする。
- `AGENTS.md`, `DEVELOPERS.md`, `README.md`, `plans/fancy-painting-prism.md` の既存の未コミット変更には一切触れない。
- PR作成・マージはユーザーが実施するため、コミットまでで完了とする。

## 対象外（今回やらないこと）

- 既存の未コミット変更（README/DEVELOPERS分割）のコミットやレビュー。
- `docs/spec/`・`docs/adr/`配下の実際の機能仕様追記（今回はプロセス変更のみ）。

## 検証

- 変更後のMarkdownファイルをRead/Grepで再確認し、リンク切れ・記述の矛盾がないか確認する。
- `git status`で意図した差分（新規ブランチ上の該当ファイルのみ）になっていること、`AGENTS.md`/`DEVELOPERS.md`/`README.md`/`plans/fancy-painting-prism.md`が変更されていないことを確認する。
