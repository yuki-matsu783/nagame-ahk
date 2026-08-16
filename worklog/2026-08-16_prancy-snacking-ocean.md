---
title: issue #22 ブランチ名slugのリッチ化 作業ログ
type: log
description: issue #22対応の試行錯誤ログ。何を試した/うまくいった/ダメだったかを記録する
tags: [issue-mr-flow, slug, branch-naming]
keywords: [to_slug, new_issue_branch, 意訳, slug, ブランチ名, Provider.sh, SKILL.md, worklog]
---

# issue #22 作業ログ

計画本体は `plans/prancy-snacking-ocean.md` を正とする。ここには計画確定までの経緯・判断・
実装時の試行錯誤を記録する。

## 経緯

- issue #22「ブランチ名のslugをリッチにしたい」の本文は標準4見出しのみで中身が未記入だった。
  `start`実行時にユーザーへ意図を確認し、「日本語タイトルの英訳・意訳をslugに反映したい」と
  回答を得た。
- 現行ブランチ・Draft PRは既存ロジック（`to_slug`が英字部分のみ拾う機械的変換）で
  `feature-22-slug` / PR #32 として作成済み（タイトル中に`slug`という英単語が含まれていたため
  空文字フォールバックにはならなかった）。
- Explore調査により、`to_slug()`はサニタイズのみの純粋関数であり、渡す文字列の中身を
  変えるだけで意図した動作（英語意訳→kebab-caseスラッグ）が実現できることを確認した。
  `Provider.sh`側での翻訳ロジック追加は既存の自己完結設計方針（`shell-scripts.md`）から
  外れるため見送り、翻訳・意訳はAIエージェント（`start`サブコマンド実行者）の責務とする方針とした。
- Plan agentによるレビューで、slugをAI生成にすると非決定的になり、`start`手順2の「既存ブランチが
  あるかの確認」（現状は完全一致のブランチ名を前提とした書き方）が破綻しうる点を指摘された。
  対応方式についてユーザーに確認し、「Provider.shに専用関数を追加せず、SKILL.mdの手順文だけを
  修正する」方式を選択した（スコープを本issueの主題に近く保つため）。

## 次にやること

- `plans/prancy-snacking-ocean.md` の「実施内容」1〜3を実装する
- 検証方法に沿って `bash -n` / `tests/test_vcs_provider.sh` / 手動確認を実施する
- flow-id 16（設計反映）で `dev-tools/docs/spec/issue-mr-workflow.md` へ反映する
  （反映すべき骨子は計画の「実施内容4」参照）
