# HANDOFF

<!--
AIセッション間・AI⇔人間の状況引継ぎメモ。常に「このブランチの現状」を表現する
-->

## 現在地

- issue #3「開発フローを変える」対応ブランチ（現ブランチ `3-開発フローを変える`）、PR #4作成済み
  （https://github.com/yuki-matsu783/nagame-ahk/pull/4）。
- 全体フロー15〜16（設計反映・AIアセット改善）実施後、PR #4レビューで追加要望
  「途中引き継ぎ対応」を受けて `resume` サブコマンド + `issue-mr-resume` サブエージェントを
  実装済み（未commit）:
  - `Get-IssueNumberFromBranch` / `Get-MrForBranch` / `Get-BranchWorkFiles`（Provider.ps1）
  - `.claude/agents/issue-mr-resume.md`（状態調査専用の読み取り専用サブエージェント）
  - `.claude/skills/issue-mr-flow/SKILL.md` に `resume` サブコマンドを追加、
    `comments`/`describe` のMR番号取得を `Get-MrForBranch` に統一
  - plan: `plans/misty-foraging-torvalds.md`、worklog: `worklog/20260815_misty-foraging-torvalds.md`
- **注意**: `issue-mr-resume` サブエージェントは今セッション内では起動確認できていない
  （エージェント定義はセッション開始時読み込みのため、新規作成分はホットリロードされない）。
  次回セッションで `/issue-mr-flow resume` を実際に呼び出して確認すること。

## 次回やること

- 変更をcommit, pushする。
- 次回セッション開始時、`/issue-mr-flow resume` を実行してサブエージェントの起動・
  現在地サマリの内容を実機確認する。
- 人間のレビューを受け、合意まで繰り返す（完了合図後は必ず `Get-MrUnresolvedComments` /
  `/issue-mr-flow comments all` で再確認してから次に進む。ADR 0003参照）。
- 合意後、全体フロー18〜19: `plans/misty-foraging-torvalds.md` と
  `worklog/20260815_misty-foraging-torvalds.md` を削除し、本HANDOFF.mdを次タスクへリセットする。
  その後commit, push。
- 最後に人間がPR #4をsquash mergeする。

## 判断が分かれるポイント

- `ConvertTo-Slug` が全角文字のみのissueタイトルで `issue` にフォールバックする件（実害なしとして
  許容済み）。
- `ahk-implement` スキルが独立エントリーポイントでなくなったことで、非issueタスクの需要が
  実際に無くなるかは運用しながら見極める。
- `Get-BranchWorkFiles` は「1ブランチ1issue」運用を前提としたヒューリスティック
  （`dev-tools/docs/spec/issue-mr-workflow.md` 未決定事項参照）。

## 未解決の質問

- 特になし。

## 守るべき条件・触ってはいけない範囲

- write系関数（`New-IssueBranch` / `New-DraftMergeRequest` / `Set-MrDescription`）を、この
  issue #3ブランチ・PR #4に対して誤って再実行しない（重複ブランチ/MR作成のおそれ）。
- `Add-MrThreadReply` はGitHub上に実際にコメントを投稿する（副作用あり）。
- plan/worklogの削除は、人間の最終合意を得てから行う（まだ削除していない）。
