# HANDOFF

<!--
AIセッション間・AI⇔人間の状況引継ぎメモ。常に「このブランチの現状」を表現する
-->

## 現在地

- issue #3「開発フローを変える」対応ブランチ（現ブランチ `3-開発フローを変える`）、PR #4作成済み
  （https://github.com/yuki-matsu783/nagame-ahk/pull/4）。
- 全体フロー15〜16（設計反映・AIアセット改善）実施後、PR #4レビューで追加要望
  「途中引き継ぎ対応」を受けて `resume` サブコマンド + `issue-mr-resume` サブエージェントを
  実装・commit・push済み（commit `2cb9871`）:
  - `Get-IssueNumberFromBranch` / `Get-MrForBranch` / `Get-BranchWorkFiles`（Provider.ps1）
  - `.claude/agents/issue-mr-resume.md`（状態調査専用の読み取り専用サブエージェント）
  - `.claude/skills/issue-mr-flow/SKILL.md` に `resume` サブコマンドを追加、
    `comments`/`describe` のMR番号取得を `Get-MrForBranch` に統一
  - plan: `plans/misty-foraging-torvalds.md`、worklog: `worklog/20260815_misty-foraging-torvalds.md`
- 次セッションで `/issue-mr-flow resume` → `issue-mr-resume` サブエージェント起動を実機確認済み。
  正常に現在地サマリ（ブランチ・issue・PR・未解決コメント・plan/worklogファイル・HANDOFF.mdの内容と
  矛盾点）を返すことを確認できた。前回の「未commit」「起動未確認」の注意書きは解消済み。
- 上記実機確認の結果を受け、PR #4の未解決コメント（threadId `PRRT_kwDOT4Y-5s6Ze4iq`,
  `.claude/skills/issue-mr-flow/SKILL.md:23`）に対応完了として返信済み（スレッド自体は
  レビュアーが解決するまでunresolvedのまま残る仕様）。
- 人間から「レビューした」と合図を受けたため `comments all` で再確認したところ、
  新たに未解決コメントが2件見つかった:
  1. `PRRT_kwDOT4Y-5s6ZfGIk`（`SKILL.md:43`、全体フロー旧行14）: 人間/AIの担当が1行に
     混在していた点。行14/15に分割して対応（行8・9と同じパターンに統一）。
  2. `PRRT_kwDOT4Y-5s6ZfGaK`（`SKILL.md:83`、`reply`）: AIの返信がGitHub上で元コメント投稿者
     （人間の`gh`認証アカウント）と同一に見える点。アカウント自体の分離は技術的にできないため、
     返信本文冒頭に `Claude Code より:` の署名を必ず付ける運用ルールを追加して対応
     （botアカウント方式は規模超過のため見送り。判断理由は
     `worklog/20260815_pr4-review-followup2.md` 参照）。
  - `.claude/skills/issue-mr-flow/SKILL.md` の全体フロー表は21ステップに更新済み
    （旧14が14/15に分割されたため、旧15〜20は新16〜21）。
  - 上記2件への返信は署名運用の初適用として実施済み（commit `3c75b50`）。
- 全体フロー17（AIアセット改善）として、セッション中に発生した `ExitPlanMode` の計画とりちがえ事故
  （古い計画テキストを3回連続で誤送信）の再発防止ルールを
  `.claude/rules/plan-mode-safety.md` に追加し、`CLAUDE.md` からインポートした。
  経緯となぜなぜ分析は `worklog/20260815_planmode-safety-rule.md` 参照。

## 次回やること

- 人間のレビュー・合意を受ける。合意まで9〜15の実装ループを繰り返す（完了合図後は必ず
  `Get-MrUnresolvedComments` / `/issue-mr-flow comments all` で unresolved が残っていないか
  再確認してから次に進む。ADR 0003参照）。
- 合意後、全体フロー19〜20: `plans/` `worklog/` のこのブランチ固有ファイル
  （`misty-foraging-torvalds` / `toasty-orbiting-finch` / `pr4-review-followup2` /
  `planmode-safety-rule` の各plan・worklog）を削除し、本HANDOFF.mdを次タスクへリセットする。
  その後commit, push。このタイミングで、署名方式採用の経緯（worklog参照）を
  `dev-tools/docs/spec/issue-mr-workflow.md` の決定事項・必要ならADRへ反映する。
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
