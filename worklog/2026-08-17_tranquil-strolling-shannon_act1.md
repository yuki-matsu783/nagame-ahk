---
title: コミットは必ずcommitスキル経由で行うルールの追加 worklog
type: log
description: issue #39対応の作業ログ。commitスキルの呼び出し条件を広げるための変更検討・実施記録
tags: [git-workflow, commit-skill, issue-mr-flow]
keywords: [commit, コミット, スキル, git-workflow, issue-mr-flow]
---

# worklog: コミットは必ずcommitスキル経由で行うルールの追加（issue #39）

対応するplan: [plans/tranquil-strolling-shannon.md](../plans/tranquil-strolling-shannon.md)

## 2026-08-17

- issue #39 の内容を確認。現状 `commit` スキルのfrontmatter descriptionが
  「Use ONLY when the user explicitly invoked /commit」となっており、issue-mr-flowの
  flow-id 6/12/18/22（エージェントが自律的にコミットする場面）でスキルを経由しない余地が
  あることが根本原因と特定した。
- 対応方針として、`.claude/skills/commit/SKILL.md`（呼び出し条件の緩和）・
  `.claude/rules/git-workflow.md`（コミット運用ルールの明記）・
  `.claude/skills/issue-mr-flow/SKILL.md`（フロー表・ポインタへの追記）の3ファイルで
  一貫して「commitは常にスキル経由」と読めるようにする方針でplanを作成し、承認を得た。
- ブランチ `feature-39-use-commit-skill-rule` / Draft PR #40 を作成済み。
