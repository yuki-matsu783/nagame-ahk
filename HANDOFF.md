# HANDOFF

<!--
AIセッション間・AI⇔人間の状況引継ぎメモ。常に「このブランチの現状」を表現する
-->

## 現在地

- issue #3「開発フローを変える」対応ブランチ（現ブランチ `3-開発フローを変える`）、PR #4作成済み
  （https://github.com/yuki-matsu783/nagame-ahk/pull/4）。
- issue駆動MRワークフロー支援（`.claude/skills/issue-mr-flow`）を実装し、PR #4のレビュー3件を受けて
  さらに以下を実施済み（未commit）:
  - `.claude/skills/issue-mr-flow/SKILL.md` を、issue起票〜マージの**唯一の実装フロー定義**に統合
    （`docs-workflow.md` / `git-workflow.md` の手順部分を移動。今後は全タスクをissue起点で進める前提）
  - 「reflect」を「設計反映」（docs/spec, docs/adr）／「AIアセット改善」（.claude/rules等）に分割
  - `dev-tools/docs/adr/0002-issue-mr-flowへの実装フロー統合.md` を新規起票
  - `Github.ps1` の `gh api graphql` 不具合を修正（`{owner}`/`{repo}` はクエリ文字列でなく `-F` で渡す）、
    `path`/`line`/`diffHunk` も取得するよう拡張
  - plan: `plans/misty-foraging-torvalds.md`、worklog: `worklog/20260815_misty-foraging-torvalds.md`

## 次回やること

- 変更をcommit, pushする。
- `/issue-mr-flow describe` でPR #4のdescriptionに今回の対応内容を反映する。
- PR #4上で3件のレビューコメントに対応した旨を伝え、再レビューを依頼する。
- 合意が得られたら「設計反映」（plan/worklogをdocs/spec, docs/adrへ反映）→「AIアセット改善」の
  ステップへ進む（`.claude/skills/issue-mr-flow/SKILL.md` の全体フロー15〜19）。

## 判断が分かれるポイント

- `ConvertTo-Slug` が全角文字のみのissueタイトルで `issue` にフォールバックする件（実害なしとして
  許容済み。設計docの未決定事項に記載）。
- `ahk-implement` スキルが独立エントリーポイントでなくなったことで、非issueタスクの需要が
  実際に無くなるかは運用しながら見極める（`dev-tools/docs/spec/issue-mr-workflow.md` 未決定事項参照）。

## 未解決の質問

- 特になし。

## 守るべき条件・触ってはいけない範囲

- write系関数（`New-IssueBranch` / `New-DraftMergeRequest` / `Set-MrDescription`）を、この
  issue #3ブランチ・PR #4に対して誤って再実行しない（重複ブランチ/MR作成のおそれ）。
