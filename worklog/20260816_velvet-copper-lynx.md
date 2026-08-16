---
title: "worklog: extract-frontmatter.sh再設計（出力ディレクトリ分散・concept_id基準の修正）"
type: guide
description: extract-frontmatter.shの出力仕様をレビュー指摘に合わせて再設計した作業ログ
tags: [dev-tools, frontmatter, jsonl]
keywords: [extract-frontmatter, index.jsonl, concept-id, repo-root, ディレクトリ分散, リファクタ]
---

# worklog: extract-frontmatter.sh再設計

対象: PR #23、`dev-tools/src/extract-frontmatter.sh`の出力仕様レビュー対応（2026-08-16）。
plan: `plans/velvet-copper-lynx.md`

## 試したこと

- レビューコメント「イメージが違った」を受け、実際の意図（markdownが存在する各ディレクトリごとに
  index.jsonlを分散生成し、concept_idはプロジェクトルート基準の相対パスにする）を確認。
- `git rev-parse --show-toplevel`（`C:/Users/...`形式）と`realpath`（`/c/Users/...`形式）の
  パス表記が一致せず、`realpath --relative-to`が正しく相対パスを計算できない問題を実機確認。
  `cd`はどちらの表記も受け付けるため、`(cd "$start_dir" && cd "$(git rev-parse --show-toplevel)" && pwd)`
  でMSYS形式に統一した`repo_root`を得る`resolve_repo_root`関数を新設。
- `main()`を、出力先を`$(dirname "$file")/index.jsonl`（そのmarkdownファイルの直接の親ディレクトリ）
  に、concept_id/directoryを`realpath --relative-to="$repo_root"`基準に変更。連想配列
  `seen_out_files`で「そのディレクトリのindex.jsonlを既に切り詰めたか」を管理し、同一出力先への
  複数ファイルの追記に対応。
- 誤った旧仕様で生成・コミット済みだった8ファイルを削除し、リポジトリルートで
  `extract-frontmatter.sh .`を1回実行して16ファイルへ再生成。

## うまくいったこと

- リポジトリルートで1回実行するだけで、markdownが存在する16ディレクトリ全てに正しい
  `index.jsonl`が生成されることを確認（`.`自身、`.claude/agents`、`.claude/rules`、
  `.claude/skills/ahk-implement`、`.claude/skills/issue-mr-flow`、`.github/ISSUE_TEMPLATE`、
  `.gitlab/issue_templates`、`dev-tools/docs`、`dev-tools/docs/ddr`、`dev-tools/docs/spec`、
  `docs`、`docs/ddr`、`docs/spec`、`plans`、`tests`、`worklog`）。
- `docs/`を指定して実行した場合でも、`concept_id`が`docs/spec/activity-status`
  （`docs/`基準の`spec/activity-status`ではなく）になることを確認し、レビューの「指定
  ディレクトリ以外の場所で実施してもプロジェクトルート基準」という要求を満たせた。
- `tests/test_extract_frontmatter.sh`に`resolve_repo_root`の単体テスト（リポジトリルート自身・
  サブディレクトリいずれを指定してもリポジトリルートを返すこと）と、concept_id/directoryの
  導出テストを実際のリポジトリファイル（README.md, docs/spec/activity-status.md）を使って書き直し、
  15アサーション全て成功。

## ダメだったこと

- 特になし。

## 次の一歩

- 特になし（完了）。今後markdownやfrontmatterが変わるたびに、リポジトリルートで
  `extract-frontmatter.sh .`を再実行し`index.jsonl`群を更新する運用となる。
