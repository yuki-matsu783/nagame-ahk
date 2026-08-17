---
alwaysApply: true
title: Git運用（ブランチ・命名規則）
type: rule
description: featureブランチの命名規則・worklog配置・PR/マージ運用を定めたルール
tags: [git, branch, rule]
keywords: [featureブランチ, ブランチ命名, worklog, squash-merge, draft-pr, issue-mr-flow, マージ運用, always-apply]
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

## コミット運用

- **すべてのコミットは `commit` スキル（`.claude/skills/commit/SKILL.md`）経由で行う**
  （issue #39）。ユーザーが明示的に `/commit` を呼ぶ場合だけでなく、`issue-mr-flow` の全体フロー
  flow-id 6/11/17/22/28/32でAIエージェントが自律的にコミットする場面も対象。
- ドキュメント上のルールだけでなく、技術的にも強制する。`git commit` の直接実行は
  `.claude/hooks/block-direct-git-commit.sh`（PreToolUse hook。`.claude/settings.json`の
  `hooks.PreToolUse`で登録）が、Bash/PowerShellのコマンド文字列に `git commit` を検知した時点で
  exit code 2でブロックする。`permissions.deny`にも`Bash(git commit*)` / `PowerShell(git commit*)`
  を追加しているが、複合コマンド（例: `cd src && git commit -m "fix"`）はprefixマッチをすり抜ける
  ため、実質的な強制はhook側が担う（多重防御）。
  - `commit`スキル自身は `.claude/scripts/src/create-commit.sh` というラッパースクリプト経由で
    `git add` / `git commit` を実行する。呼び出し文字列自体に `git commit` という部分文字列を
    含まないため、hookの対象にならず正規に実行できる。
  - 既知のトレードオフ: 部分文字列マッチのため、たまたま `git commit` という語を含む無関係な
    コマンド（該当文字列を検索する `grep` 等）も誤ってブロックされる。悪意ある回避への対策は
    行わない（既定動作を確実な方向へ倒す仕組みであり、敵対的な安全境界ではない）。
    **AIエージェント向け注記**: このトレードオフはissue #39対応時に実際に2回発生した
    （コミットメッセージ、およびMR description用heredocの説明文中に、それぞれ`git commit`という
    語句が地の文として含まれていたため）。コミットメッセージ・PR description・スクリプトの
    コメント等、このhookの仕組み自体を日本語で説明する文章を書く際は、`git` と `commit` を
    半角スペース区切りで連続させず（例:「gitのコミット操作」「直接コミットを実行する」のように
    言い換える）、同一Bash/PowerShellツール呼び出し文字列内で誤検知を避ける。
  - 経緯・却下案は
    `.claude/scripts/docs/ddr/0012-コミットはcommitスキル経由を機構的に強制する.md` を参照。

## worklogの配置・命名

`worklog/日付_<planファイル名>_push<N>.md` に記録する（配置・命名は `directory-structure.md`、ライフサイクルは
`docs-workflow.md` の「ドキュメント運用」表、作成・削除のタイミングは `.claude/skills/issue-mr-flow/SKILL.md`
の全体フローを参照）。

## PR・マージ

- PR作成・レビュー依頼・マージは人間が実施する。AIエージェントはブランチでの実装・コミット・設計反映までを担当し、`gh pr create` / `gh pr merge` 等のPR作成・マージ操作は、ユーザーから明示的に指示されない限り実行しない。
- マージはsquash mergeを用いる。設計反映時にworklogファイルを削除しておくことで、squash後にmainへ反映される内容は「コード＋spec/ddr」のみになり、試行錯誤の詳細はブランチ上のコミット履歴（PRのコミット一覧）としてのみ残る。
- マージ後、作業ブランチは削除してよい。
