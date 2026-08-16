---
title: コミットは必ずcommitスキル経由で行うルールの追加
type: log
description: issue #39対応。commitスキルの利用を「ユーザーが/commitと明示入力した場合のみ」から「常時必須」へ広げ、ドキュメント上のルール整備に加えPreToolUse hookとラッパースクリプトによる技術的な強制も行う計画
tags: [git-workflow, commit-skill, issue-mr-flow, rule, hook]
keywords: [commit, コミット, スキル, git-workflow, issue-mr-flow, frontmatter, pretooluse, hook, ラッパースクリプト]
---

# コミットは必ずcommitスキル経由で行うルールの追加（issue #39）

## Context

issue #39: 「コミットSkillを利用するようにルールを記載する」。現状、`commit`スキル
（[.claude/skills/commit/SKILL.md](../.claude/skills/commit/SKILL.md)）のfrontmatter descriptionは
「Use ONLY when the user explicitly invoked /commit」となっており、AIエージェントが
issue-mr-flowの全体フロー内で自律的にコミットする場面（flow-id 6/12/18/22「commit, push して
レビュー依頼を行う」担当:エージェント）では、このスキルを経由せず直接 `git commit` を実行して
しまう余地がある。これが「スキルが使われたり使われなかったりしている」という現状の原因。
受け入れ条件は「すべてのコミットがスキルを利用して行われる」こと。

当初はドキュメント（ルール記載）のみの計画だったが、ユーザーから
「`.claude/settings.json`の`permissions.deny` + `PreToolUse` hookで技術的にも強制できる」との
提案を受け、対応範囲をhookによる機構的な強制まで広げることにした（ユーザー選択で確認済み）。
ドキュメントでの記載はエージェントの遵守に依存するが、hookを入れることで`git commit`の直接実行
自体を機構的にブロックできる。

## 設計方針

- **commitスキルはラッパースクリプト `dev-tools/src/create-commit.sh` 経由でコミットする**
  （新規作成。`issue-create`スキルが`dev-tools/src/create-issue.sh`を使う既存パターンを踏襲）。
  このスクリプトの呼び出し文字列自体（例: `bash dev-tools/src/create-commit.sh --message "..." --
  file1 file2`）には `git commit` という部分文字列を含まないため、次のhookの検知対象にならない。
- **`.claude/hooks/block-direct-git-commit.sh`（新規、PreToolUse hook）** が、Bash/PowerShellツールの
  コマンド文字列に `git commit`（正規表現 `git[[:space:]]+commit`）が含まれる場合に exit code 2で
  ブロックする。既存の`post-push-usage-report.sh`と同じ設計（`matcher: "Bash|PowerShell"`で広く
  受けて、スクリプト側で正規表現による部分文字列チェックを行う）を踏襲する。理由も同じ:
  `permissions.deny`の`if`相当のprefixマッチだけでは`cd src && git commit ...`のような複合コマンドを
  すり抜けてしまうため。
- **`.claude/settings.json`の`permissions.deny`にも`Bash(git commit*)` / `PowerShell(git commit*)`を
  追加**（単純な直接実行は許可プロンプトの時点で弾く多重防御。複合コマンドのすり抜けはhook側で
  カバーする）。
- **既知のトレードオフ**: 部分文字列マッチのため、コマンド文字列中にたまたま`git commit`という
  語が含まれる場合（該当文字列を検索する`grep`など）も誤ってブロックする。実行頻度が低い操作
  のため許容する。悪意を持った回避（意図的な文字列分割等）までは想定しない（エージェントの
  既定動作を確実な方向へ倒すための仕組みであり、敵対的な安全境界ではない）。
- 経緯・却下案（ドキュメントのみ案、deny単体案）はDDRとして記録する
  （`dev-tools/docs/ddr/`。dev-tools配下のhook/スクリプトに関する意思決定のため）。

## 変更・新規作成するファイル

1. **`dev-tools/src/create-commit.sh`（新規）**
   `--message <メッセージ> -- <file1> [file2 ...]` を受け取り、`git add -- <files>` →
   `git commit -m <メッセージ>` を実行する。`create-issue.sh`と同じCLIスタイル（`usage()`関数、
   `set -euo pipefail`）。`--amend` `--no-verify` `git add .` は行わない。

2. **`.claude/hooks/block-direct-git-commit.sh`（新規）**
   PreToolUse hook。`post-push-usage-report.sh`と同じ枠組み（jqでtool_name/tool_input.commandを
   読み、正規表現でチェック）。マッチしたら理由をstderrへ出しexit 2、それ以外はexit 0。

3. **`.claude/settings.json`**
   `permissions.deny`に`Bash(git commit*)` `PowerShell(git commit*)`を追加。`hooks.PreToolUse`に
   `matcher: "Bash|PowerShell"`で上記hookスクリプトを追加（既存の`hooks.PostToolUse`と同じ形式）。

4. **[.claude/skills/commit/SKILL.md](../.claude/skills/commit/SKILL.md)**
   - frontmatter `description`: 「Use ONLY when the user explicitly invoked /commit」の限定を外し、
     「ユーザーが明示的に`/commit`と入力した場合・AIエージェントが本リポジトリでコミットを作成
     する場面（issue-mr-flowのflow-id 6/12/18/22等）の両方で使う」旨に広げる。
   - `## 絶対ルール`の前に`## 呼び出しタイミング`節を追加（上記2パターンの明記、
     `git commit`直接実行はhookでブロックされる旨）。
   - Step 5「コミット実行」を`dev-tools/src/create-commit.sh`経由に書き換える
     （`git add`/`git commit`を直接実行しない）。

5. **[.claude/rules/git-workflow.md](../.claude/rules/git-workflow.md)**
   「ブランチ運用」節の後に`## コミット運用`節を新設。ルール上の必須化（`commit`スキル経由）と、
   hookによる機構的強制の両方、およびそのトレードオフを記載する。

6. **[.claude/skills/issue-mr-flow/SKILL.md](../.claude/skills/issue-mr-flow/SKILL.md)**
   全体フロー表のflow-id 6/12/18/22のセル文言に「`commit`スキル経由で」を追記。末尾「詳細ルールへの
   ポインタ」の`git-workflow.md`参照箇所を「コミット運用（`commit`スキル必須使用・PreToolUse hook
   による技術的強制）」を含む形に拡張。

7. **`dev-tools/docs/ddr/0012-コミットはcommitスキル経由を機構的に強制する.md`（新規）**
   背景（ドキュメントのみでは遵守がエージェント任せ）・決定（ラッパースクリプト＋hookの二段構え、
   `permissions.deny`も併用）・却下案（ドキュメントのみで運用／`permissions.deny`単体での運用
   （複合コマンドをすり抜けるため））を記録する。

8. **`dev-tools/docs/ddr/index.jsonl`（および7で新規作成したmarkdownを含む他のindex.jsonl）**
   `bash dev-tools/src/extract-frontmatter.sh .` を実行し再生成する
   （手動再生成が前提の既存運用。[dev-tools/docs/spec/extract-frontmatter.md](../dev-tools/docs/spec/extract-frontmatter.md)参照）。

## 対象外

- `docs/spec/` への追記は行わない（アプリ機能の仕様変更ではなく、開発フロー・dev-tool側の変更の
  ため。DDRは`dev-tools/docs/ddr/`側に置く）。
- `commit`スキルのAskUserQuestionによる確認フロー自体は変更しない。
- 悪意ある回避（意図的な文字列分割等）への対策は行わない（上記トレードオフの通り）。

## 検証方法

- `bash -n dev-tools/src/create-commit.sh` / `bash -n .claude/hooks/block-direct-git-commit.sh`
  で構文チェックする。
- 実際にこのタスク自身のコミット（flow-id 6）で、まず直接`git commit`を試みてhookにブロック
  されることを確認し、続けて`dev-tools/src/create-commit.sh`経由でコミットが成功することを
  確認する（エンドツーエンドの実地検証を兼ねる）。
- 変更後の3ドキュメント（commit skill / git-workflow.md / issue-mr-flow SKILL.md）間で
  「commitは常にスキル経由」という結論が矛盾なく一致していることを確認する。
