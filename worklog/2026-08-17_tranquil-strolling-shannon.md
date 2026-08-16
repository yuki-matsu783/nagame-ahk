---
title: コミットは必ずcommitスキル経由で行うルールの追加 worklog
type: log
description: issue #39対応の作業ログ。commitスキルの呼び出し条件を広げるための変更検討・実施記録（ドキュメント記載＋PreToolUse hookによる技術的強制）
tags: [git-workflow, commit-skill, issue-mr-flow, hook]
keywords: [commit, コミット, スキル, git-workflow, issue-mr-flow, pretooluse, hook]
---

# worklog: コミットは必ずcommitスキル経由で行うルールの追加（issue #39）

対応するplan: [plans/tranquil-strolling-shannon.md](../plans/tranquil-strolling-shannon.md)
（1回目のplan内容は
[plans/tranquil-strolling-shannon_act1.md](../plans/tranquil-strolling-shannon_act1.md)、
対応するworklogは
[worklog/2026-08-17_tranquil-strolling-shannon_act1.md](2026-08-17_tranquil-strolling-shannon_act1.md)
に退避済み）。

## 2026-08-17

- issue #39 の内容を確認。現状 `commit` スキルのfrontmatter descriptionが
  「Use ONLY when the user explicitly invoked /commit」となっており、issue-mr-flowの
  flow-id 6/12/18/22（エージェントが自律的にコミットする場面）でスキルを経由しない余地が
  あることが根本原因と特定した。
- ブランチ `feature-39-use-commit-skill-rule` / Draft PR #40 を作成。
- 1回目のplan: `.claude/rules/git-workflow.md` / `.claude/skills/commit/SKILL.md` /
  `.claude/skills/issue-mr-flow/SKILL.md` の3ファイルへ「commitは常にスキル経由」という
  ドキュメント上のルールを追記するだけの方針で作成・承認。
- ユーザーから、`.claude/settings.json`の`permissions.deny` + `PreToolUse` hookで
  `git commit`の直接実行を機構的にもブロックできるとの提案を受領。AskUserQuestionで
  対応範囲を確認したところ「hookによる技術的強制も実装する」を選択。
- Planモードへ再突入（`dev-tools/src/archive-reentrant-plan.sh`で1回目の内容を`_act1`へ退避
  済み。plan-mode-safety.md規則6の手順通り）。
- 既存の`.claude/hooks/post-push-usage-report.sh`（`matcher: "Bash|PowerShell"` +
  スクリプト側での正規表現による部分文字列チェック）と、`issue-create`スキルが
  `dev-tools/src/create-issue.sh`をラッパーとして使う既存パターンを踏襲する設計に決定。
  - `dev-tools/src/create-commit.sh`（新規ラッパー）: commitスキルはこれ経由でgit add/git commit
    する。呼び出し文字列自体に`git commit`という部分文字列を含まないため、hookの対象外になる。
  - `.claude/hooks/block-direct-git-commit.sh`（新規PreToolUse hook）: `git commit`を含む
    Bash/PowerShellコマンドをexit code 2でブロック。
  - `.claude/settings.json`: `permissions.deny`にも`Bash(git commit*)` `PowerShell(git commit*)`を
    追加（多重防御）。
  - 経緯・却下案（ドキュメントのみ案／deny単体案）は`dev-tools/docs/ddr/0012-...`として記録する。
- 2回目のplanとして承認を得た（本ファイルの対応するplan本体を参照）。
