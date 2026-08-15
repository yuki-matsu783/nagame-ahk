# HANDOFF

<!--
AIセッション間・AI⇔人間の状況引継ぎメモ。常に「このブランチの今の状態」を表現する
-->

## 現在地

- issue #3「開発フローを変える」対応ブランチ（現ブランチ `3-開発フローを変える`）で、
  issue駆動MRワークフロー支援を実装済み（Phase 1: 基本機能、Phase 2: issueテンプレート標準化）。
  - 設計doc: `dev-tools/docs/spec/issue-mr-workflow.md`（承認済み・実装差分反映済み）
  - plan: `plans/misty-foraging-torvalds.md`（Phase 1・Phase 2両方を記載）
  - 実装（Phase 1）: `.mrworkflow.json`, `dev-tools/src/vcs/{Provider,Github,Gitlab}.ps1`,
    `.claude/skills/issue-mr-flow/SKILL.md`, `dev-tools/docs/README.md`（リンク追加）
  - 実装（Phase 2）: `.github/ISSUE_TEMPLATE/task.md`, `.gitlab/issue_templates/task.md`,
    `Provider.ps1` に `Test-IssueSections` 追加, `SKILL.md` の `start` に警告ステップ追加
  - 実機確認: `gh` インストール・認証済み。`Get-Issue -Number 3` / `Get-Provider` /
    `Get-WorkflowConfig` / `Test-IssueSections` を確認済み（詳細は
    `worklog/20260815_misty-foraging-torvalds.md`）。
  - write系関数（ブランチ/MR作成、description更新）とGitLab側は未検証のまま（意図的。詳細はworklog参照）。

## 次回やること

- ユーザーの指示があればcommit/pushする。
- その後、実際に `/issue-mr-flow` を使って本ワークフローの後続ステップ（レビューコメント取得・
  description更新等）を回してみる。GitHub UI上でissueテンプレートが選択できるかもpush後に確認する。
- reflect（plan/worklogの内容をspec/adrへ最終反映し、worklogを削除）はPR作成前に行う。

## 判断が分かれるポイント

- `ConvertTo-Slug` が全角文字のみのissueタイトルで `issue` にフォールバックする件（実害なしとして
  今回は許容。設計docの未決定事項に記載済み）。

## 未解決の質問

- 特になし。

## 守るべき条件・触ってはいけない範囲

- write系関数（`New-IssueBranch` / `New-DraftMergeRequest` / `Set-MrDescription`）を、この
  issue #3ブランチに対して誤って再実行しない（重複ブランチ/MR作成のおそれ）。実機確認は別issueで行う。
