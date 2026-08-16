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

### 実装（flow-id 11）

- `.claude/hooks/post-push-compact-prompt.sh` を新規作成。検知ロジックは
  `post-push-usage-report.sh` と同一パターン（agent_id/tool_name/tool_input.commandの
  `git[[:space:]]+push`判定、`CLAUDE_PROJECT_DIR`確認、`get_workflow_config`でbase branch除外、
  `get_mr_for_branch`でMR存在確認）。出力は`session-start.sh`の`write_additional_context`と
  同じ形の`hookSpecificOutput.additionalContext`（`hookEventName: "PostToolUse"`）。
  固定メッセージ「MRのレビューをお願いします。/compactを実施をしていただくと、レビュー中に
  コンテキストを圧縮して今後の作業が効率化になる可能性があります」を注入する。
  `main`関数 + `( main ) || true` + `exit 0`のエラー方針、BOM無しUTF-8・LF改行（Write後に
  `file`/`xxd`/CR有無で確認済み）。
- `.claude/settings.json` の `hooks.PostToolUse[0].hooks` へ、新スクリプトを指す2エントリ
  （`if: "Bash(git push*)"` / `"PowerShell(git push*)"`）を追加。既存の
  `post-push-usage-report.sh`用エントリはそのまま維持。
- `bash -n` 構文チェックOK。
- 疑似stdin JSONでの動作確認: 正常系（現ブランチ・Bashツール・git push検知）で
  `additionalContext`付きJSONが出力されることを確認。異常系（agent_id有り／git push以外の
  コマンド／Bash・PowerShell以外のツール）ではいずれも何も出力されずexit 0のみになることを確認。
  最初の試行では`CLAUDE_PROJECT_DIR`を手動シェルにexportし忘れており「何も出力されない」状態に
  なったが、原因を特定しexport後に再実行して解消（実際のhook実行時はClaude Code側が
  `CLAUDE_PROJECT_DIR`を設定するため問題にならない）。
- **実機確認**: フィクスチャ検証用のBashコマンド文字列自体に`git push`という文字列が
  含まれていたため、`.claude/settings.json`に登録済みの本スクリプトが実際にPostToolUse hookとして
  発火し、次のターンで`<system-reminder>PostToolUse:Bash hook additional context: ...</system-reminder>`
  が実際に注入されることを確認できた。`PostToolUse`での`hookSpecificOutput.additionalContext`は
  このリポジトリに前例が無かったが、`SessionStart`と同様に機能することを実地検証できた。

### レビュー（flow-id 14〜15）

- ユーザーから「レビューOK」の合図を受領。`get_mr_unresolved_comments 33 true`で再確認したところ、
  未解決スレッドは0件（自動投稿の対応工数レポートコメントのみで、実装への指摘コメントは無し）。
  対応すべきレビューコメントが無かったため、flow-id 15（修正・返信）は実質何もせず完了とした。

### 設計反映（flow-id 16）

- `dev-tools/docs/spec/issue-mr-workflow.md`へ反映:
  - 「コンポーネント構成」ツリーに`post-push-compact-prompt.sh`を追加。
  - 新規サブセクション「/compact実施の呼びかけ（PostToolUse hook, git push検知）」を、既存の
    「対応工数レポート」節・「セッション開始時の自動コンテキスト注入」節の直後（「ブランチ命名」節の
    直前）に追加。検知ロジックの流用元、伝達手段（`additionalContext`）、実地検証結果、既知の制約を記載。
  - 「影響範囲」に issue #11 分の新規／変更ファイル一覧を追加。
- 本issueの変更はAHKアプリ本体には影響しないため`docs/spec/`（AHK機能向け）への反映は無し。
- 新規DDRは作成しなかった（対象外とした3案は`plans/silly-puzzling-ember.md`の「対象外」節に留まる
  小粒な判断で、`post-push-usage-report.sh`と同規模の`SessionStart` hook追加（issue #5）でも
  DDRは作成していない前例と整合的と判断）。

### AIアセット改善（flow-id 17）

- HANDOFF.mdの「未解決の内容」に記録していた`new_issue_branch`（`dev-tools/src/vcs/Provider.sh`）の
  stdout汚染バグを修正。`git fetch`/`git switch`/`git push`の標準出力を`>/dev/null`へ捨てるよう変更
  （`add_empty_commit_for_draft_mr`と同じパターン）。`bash -n`で構文チェックOK。既存の単体テスト
  （`tests/test_vcs_provider.sh`）は`new_issue_branch`を対象にしていない（git remote操作を伴うため
  純粋ロジックの単体テスト対象外）ため変更不要。
- `dev-tools/docs/spec/issue-mr-workflow.md`の「影響範囲」issue #11分に本修正を追記済み。
- 他に気づいたルール・スキルの不備は無し。

## 次にやること

- flow-id 18（commit, push してレビュー依頼）を実施 → flow-id 19（人間による設計反映レビュー）待ち。
