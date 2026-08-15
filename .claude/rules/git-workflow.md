---
alwaysApply: true
title: Git運用（ブランチ・命名規則）
type: rule
description: featureブランチの命名規則・worklog配置・PR/マージ運用を定めたルール
tags: [git, branch, rule]
timestamp: "2026-08-16T05:31:36"
---

# Git運用（ブランチ・命名規則）

開発フロー全体（issue起票〜マージ、worklog・設計反映・PR・マージの手順を含む）は
`.claude/skills/issue-mr-flow/SKILL.md` を参照する（唯一の実装フロー定義）。本ファイルは
ブランチ運用に関する参照情報のみを記載する。

## 適用範囲

`.claude/skills/issue-mr-flow/SKILL.md` の全体フローが適用されるタスク（新機能の追加・既存動作の変更）に適用する。
誤字修正・軽微なドキュメント修正等、フロー自体を省略してよいごく小さな変更は、mainへの直接コミットも許容する。

## ブランチ運用

- フロー対象のタスクは、着手前に必ずfeatureブランチを作成する（mainへの直接コミットはしない）。
- ブランチ名は `.mrworkflow.json` の `branchPrefixTemplate`（既定 `feature-<issue番号>-<slug>`）に従う。

## worklogの配置・命名

`worklog/日付_<planファイル名>.md` に記録する（配置・命名は `directory-structure.md`、ライフサイクルは
`docs-workflow.md` の「ドキュメント運用」表、作成・削除のタイミングは `.claude/skills/issue-mr-flow/SKILL.md`
の全体フローを参照）。

## PR・マージ

- PR作成・レビュー依頼・マージは人間が実施する。AIエージェントはブランチでの実装・コミット・設計反映までを担当し、`gh pr create` / `gh pr merge` 等のPR作成・マージ操作は、ユーザーから明示的に指示されない限り実行しない。
- マージはsquash mergeを用いる。設計反映時にworklogファイルを削除しておくことで、squash後にmainへ反映される内容は「コード＋spec/ddr」のみになり、試行錯誤の詳細はブランチ上のコミット履歴（PRのコミット一覧）としてのみ残る。
- マージ後、作業ブランチは削除してよい。
