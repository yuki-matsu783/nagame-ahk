---
title: git pushイベントを検知してcompactを促すhookを追加する
type: log
description: issue #11対応。エージェントのgit push検知時に/compact実施を促すメッセージをユーザーへ返すPostToolUse hookを追加する計画
tags: [hooks, git-push, compact, post-tool-use]
keywords: [PostToolUse, additionalContext, git push検知, compact, session-start.sh, post-push-usage-report.sh]
---

# git pushイベントを検知してcompactを促すhookを追加する（issue #11）

## Context

MRレビュー待ちに入るタイミング（`git push`後）でコンテキストが肥大化しがちという課題がある
（issue #11）。ユーザーが `/compact` を実施するタイミングを逃さないよう、エージェントが
`git push` した直後に「レビュー待ちの間に `/compact` すると効率化できる」旨のメッセージを
ユーザーへ返すことで気づきを与えたい。

既存の `.claude/hooks/post-push-usage-report.sh`（issue #15/#28対応）が全く同じ
`PostToolUse`（`git push`検知）hookパターンをすでに実装しており、検知ロジック・設定方法を
そのまま踏襲できる。一方でユーザーへの伝達手段は、同スクリプトが使うMRコメント投稿ではなく、
`.claude/hooks/session-start.sh` が使う `hookSpecificOutput.additionalContext` 方式
（stdoutへJSONを返しコンテキストへテキストを注入、エージェントがそれを見て応答に反映する）が
issue #11の意図（**対話中のユーザーへの呼びかけ**）に合致する。

## 実施内容

### 1. 新規hookスクリプト `.claude/hooks/post-push-compact-prompt.sh`

`post-push-usage-report.sh` と責務を分離した新規ファイルとする（使用量集計とcompact促しは
別の関心事であり、既存スクリプトへ混在させると単一責務が崩れるため）。

- **検知ロジックは `post-push-usage-report.sh` と同一パターンを流用**:
  - stdinのJSONから `agent_id`（非空ならサブエージェント実行として即exit）、`tool_name`
    （`Bash`/`PowerShell`以外なら即exit）、`tool_input.command`
    （`git[[:space:]]+push` に大文字小文字無視でマッチしなければ即exit）を判定。
  - `CLAUDE_PROJECT_DIR` 未設定なら即exit。
  - `dev-tools/src/vcs/Provider.sh` の `get_workflow_config` で現在ブランチが
    `defaultBaseBranch`（mainブランチ等）でないことを確認（base branch上では何もしない）。
  - `get_mr_for_branch` でMRが存在することを確認（MRが無い＝レビュー対象が無いためメッセージを
    出さない。ブランチ作成直後のごく最初のpush等をノイズとして除外する意図も兼ねる）。
- **出力方式は `session-start.sh` の `write_additional_context` と同じ形**:
  ```bash
  jq -nc --arg text "$text" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $text}}'
  ```
  `$text` にはissue #11本文の文言に沿ったメッセージ
  「MRのレビューをお願いします。/compactを実施をしていただくと、レビュー中にコンテキストを
  圧縮して今後の作業が効率化になる可能性があります」を固定文で設定する（動的な値は使わない、
  シンプルな固定メッセージで十分と判断）。
- エラー方針: `post-push-usage-report.sh` と同様、本体処理を `main` 関数にまとめ
  `( main ) || true` で握りつぶし、最後に `exit 0`（git push自体を絶対にブロックしない）。
- ファイルはBOM無しUTF-8・LF改行、`set -uo pipefail` + `main`内 `set -euo pipefail`
  （`.claude/rules/shell-script-style.md` 準拠）。

### 2. `.claude/settings.json` の更新

既存の `hooks.PostToolUse[0]`（`matcher: "Bash|PowerShell"`）の `hooks` 配列へ、
新スクリプトを指す2エントリ（`if: "Bash(git push*)"` / `"PowerShell(git push*)"`、
`command: "bash"`、`timeout: 20`）を追加する。既存の使用量レポート用エントリはそのまま残す。

### 3. 動作確認

- `bash -n .claude/hooks/post-push-compact-prompt.sh` で構文チェック。
- 疑似stdin JSON（`tool_name: "Bash"`, `tool_input.command: "git push"` 等）を用意し、
  実際のブランチ・MR状態下で `bash .claude/hooks/post-push-compact-prompt.sh < fixture.json`
  を実行し、期待通り `hookSpecificOutput.additionalContext` を含むJSONが出力されることを確認する
  （base branch上・MR無し・agent_id有りの各ケースで何も出力されない＝exit 0のみになることも確認）。
- 実機確認として、このセッション内で実際に `git push` を行い、次の応答に
  `<system-reminder>PostToolUse hook additional context: ...</system-reminder>` 相当の
  コンテキストが注入され、エージェントがユーザーへ `/compact` を促すメッセージを含む応答を
  返せることを確認する（`PostToolUse`での`hookSpecificOutput.additionalContext`はこのリポジトリに
  前例が無いため、SessionStartと同様に機能することをここで実地検証する）。

## 対象外

- `post-push-usage-report.sh` 自体の改造（責務混在を避けるため触らない）。
- `/compact` の自動実行（あくまでユーザーへの呼びかけに留め、強制はしない。issue本文も
  「ユーザに/compactの実施を求めるレスポンスを送る」であり自動実行は求めていない）。
- `.claude/hooks/lib/` への検知ロジック共通化（既存2スクリプト間の重複は少量で、現状の
  プロジェクト内でも同種の小さな重複は許容されているため、本issueのスコープでは見送る）。

## 検証方法

上記「3. 動作確認」の通り。加えてAHKアプリ本体には影響しない変更のため `tests/` 配下の
AHKテストへの影響は無い。flow-id 16（設計反映）で
`dev-tools/docs/spec/issue-mr-workflow.md` へ新セクションとして追記する
（既存の「対応工数レポート（PostToolUse hook, git push検知）」節と対の構成にする）。
