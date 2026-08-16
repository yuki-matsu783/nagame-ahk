---
title: worklog - git pushイベントを検知してcompactを促すhookを追加する
type: log
description: issue #11対応の作業ログ（試行錯誤・判断の詳細）
tags: [hooks, git-push, compact, post-tool-use]
keywords: [PostToolUse, additionalContext, session-start.sh, post-push-usage-report.sh]
---

# worklog: git pushイベントを検知してcompactを促すhookを追加する（issue #11）

計画本体: [plans/silly-puzzling-ember.md](../plans/silly-puzzling-ember.md)

## 2026-08-16

### 起票〜ブランチ作成

- issue #11「git pushイベントを検知してcompactする」を取得。
- `feature-11-prompt-compact-after-push` ブランチ・Draft PR #33 を作成。
- `new_issue_branch`（`dev-tools/src/vcs/Provider.sh`）実行時、`branch="$(new_issue_branch ...)"` の
  形で呼んだところ、関数内 `git push -u origin "$branch"` の出力（"Branch 'x' set up to track..."）が
  呼び出し元の `$(...)` キャプチャへ混入し、`branch` 変数が複数行文字列になった。結果、続く
  `new_draft_merge_request` へ渡すbranch引数が壊れ、`gh pr create` が
  `Head ref must be a branch` エラーで失敗（空コミットでの自動リトライも同様に失敗）。
  - 実際には `git switch -c`/`git push -u` 自体は正しいブランチ名で実行済みだったため、
    `git branch --show-current` で正しいブランチ名を確認した上で、`new_draft_merge_request` を
    正しい文字列（ハードコードしたブランチ名）で再実行し、PR #33 を作成できた（リカバリ完了）。
  - `new_issue_branch` 関数自体の出力汚染は本issueのスコープ外のため、HANDOFF.mdの
    「未解決の内容」に記録し、flow-id 17（AIアセット改善）での対応検討へ回した。
- origin/main（直前にマージされたPR #32分）を取り込みmerge・push。

### 調査・Plan作成

- Explore agentと自分の直接読み込みの両方で `.claude/hooks/post-push-usage-report.sh`・
  `.claude/hooks/session-start.sh`・`.claude/settings.json`・
  `dev-tools/docs/spec/issue-mr-workflow.md` を調査。
- **判明した設計上のポイント**:
  - 既存の `post-push-usage-report.sh` は `PostToolUse`（`Bash|PowerShell` matcher +
    `if: "Bash(git push*)"` / `"PowerShell(git push*)"`）でgit push検知しているが、ユーザーへの
    伝達手段は**MRコメント投稿**（`add_mr_comment`）であり、対話中のユーザーへの直接メッセージでは
    ない。issue #11が求めるのは後者。
  - `session-start.sh` が使う `hookSpecificOutput.additionalContext`
    （stdoutへJSON出力→コンテキストへテキスト注入→エージェントが応答に反映）方式が、
    issue #11の意図（対話中のユーザーへの呼びかけ）に合致すると判断。ただし**PostToolUseでの
    この方式の実例はリポジトリ内に無く**（SessionStartでの実績のみ）、実装後に実地検証が必要
    （Explore agentの調査結果でも同様の指摘あり）。
  - `dev-tools/docs/spec/issue-mr-workflow.md` 349-358行目の「スクリプト経由のgit pushは検知
    されない」制約は新規hookにも同様に適用される（既知の制約として引き継ぐのみ、対応不要）。
- 新規スクリプトとして `.claude/hooks/post-push-compact-prompt.sh` を追加する方針でPlanを作成し、
  ユーザー承認を得た（`post-push-usage-report.sh`自体の改造は責務混在を避けるため見送り）。

## 次にやること

- Plan承認後、flow-id 6（commit, push してレビュー依頼）を実施 → flow-id 7（人間によるplanレビュー）待ち。
