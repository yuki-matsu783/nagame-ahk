# HANDOFF

<!--
AIセッション間・AI⇔人間の状況引継ぎメモ。常に「このブランチの現状」を表現する
-->

## 現在地

- issue #3「開発フローを変える」対応ブランチ（現ブランチ `3-開発フローを変える`）、PR #4作成済み
  （https://github.com/yuki-matsu783/nagame-ahk/pull/4）。
- PR #4の3件のレビューコメントすべてに返信＋ユーザーがresolve済みであることを確認済み
  （`Get-MrUnresolvedComments` で0件を確認）。
- 全体フロー15（設計反映）・16（AIアセット改善）まで完了（未commit）:
  - `dev-tools/docs/spec/issue-mr-workflow.md` の「未決定事項」を整理し「決定済み事項」に格上げ
  - `dev-tools/docs/adr/0003-レビュースレッド解決は自動化しない.md` を新規起票
  - `dev-tools/docs/README.md` にADR 0003へのリンクを追加
  - plan: `plans/misty-foraging-torvalds.md`、worklog: `worklog/20260815_misty-foraging-torvalds.md`

## 次回やること

- 変更をcommit, pushする。
- 人間のレビューを受け、合意まで繰り返す（完了合図後は必ず `Get-MrUnresolvedComments` /
  `/issue-mr-flow comments all` で再確認してから次に進む。ADR 0003参照）。
- 合意後、全体フロー18〜19: `plans/misty-foraging-torvalds.md` と
  `worklog/20260815_misty-foraging-torvalds.md` を削除し、本HANDOFF.mdを次タスクへリセットする。
  その後commit, push。
- 最後に人間がPR #4をsquash mergeする。

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
- `Add-MrThreadReply` はGitHub上に実際にコメントを投稿する（副作用あり）。テスト目的で
  無関係なスレッドに誤投稿しないよう注意する。
- plan/worklogの削除は、人間の最終合意（設計反映・AIアセット改善内容のレビューOK）を得てから行う
  （まだ削除していない）。
