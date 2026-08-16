---
title: extract-frontmatter.shをディレクトリごとの分散出力・repo root基準concept_idへ再設計
type: guide
description: extract-frontmatter.shの出力仕様をレビュー指摘に合わせ、markdownが存在する各ディレクトリごとにindex.jsonlを分散生成し、concept_idをプロジェクトルート基準の相対パスにする再設計計画
tags: [dev-tools, frontmatter, jsonl]
keywords: [extract-frontmatter, index.jsonl, concept-id, repo-root, ディレクトリ分散, リファクタ]
---

# plan: extract-frontmatter.sh再設計（出力ディレクトリ分散・concept_id基準の修正）

## Context

`dev-tools/src/extract-frontmatter.sh`（PR #23 round2実装、round3でyq優先利用に更新）に対し、
レビューで「イメージが違った」との指摘を受けた（`PRRT_kwDOT4Y-5s6Zj1NE`）。

> プロジェクトルートで実施したら、markdownが存在する各ディレクトリごとにindex.jsonlが作成され、
> その中身のconcept_idはプロジェクトルートからの相対パスから.md拡張子を除いたものになるイメージ。
> プロジェクトルート以外のディレクトリで実施した場合も、その配下の子ディレクトリを再帰的に走査し、
> markdownが存在する各ディレクトリ毎にindex.jsonlが作成され、その中身のconcept_idはプロジェクト
> ルートからの相対パスから.md拡張子を除いたものになるイメージ

現行実装は「指定ディレクトリ配下を再帰走査し、指定ディレクトリ直下に1つの`index.jsonl`へ全件を
集約、concept_idは指定ディレクトリからの相対パス」という設計だった。これを以下へ変更する。

- **出力**: markdownが直下に存在する**ディレクトリごと**に、そのディレクトリ自身へ`index.jsonl`を
  生成する（1回の実行で複数ファイルが生成されうる）。
- **concept_id**: 実行時の指定ディレクトリではなく、**gitリポジトリのルート**からの相対パスを
  基準にする（`.md`拡張子を除く）。`directory`フィールドも同様にリポジトリルート基準にする。

この変更により、リポジトリルートで1回実行するだけで、markdownを含む全ディレクトリの`index.jsonl`
が正しい`concept_id`で生成できるようになる（前回round4の対応で8ディレクトリを個別に手動実行し、
かつ各ディレクトリ配下を1ファイルに集約していたのは誤りだったため、やり直す）。

## 実施内容

### 1. リポジトリルートの解決

`git bash`環境では`git rev-parse --show-toplevel`と`realpath`の返すパス表記
（`C:/Users/...`形式 と `/c/Users/...`形式）が一致しないため、`realpath --relative-to`が
正しく機能しない問題を実機確認済み。以下の手順でMSYS形式に統一した`repo_root`を得る。

```bash
repo_root="$(cd "$target_dir" && cd "$(git rev-parse --show-toplevel)" && pwd)"
```

### 2. `main()`の再設計

- `find "$target_dir" -type f -name '*.md' -print0 | sort -z`で対象ファイルを列挙する処理は
  そのまま流用する。
- 各ファイルについて:
  - `rel="$(realpath --relative-to="$repo_root" "$file")"` → `concept_id="${rel%.md}"`、
    `directory="$(dirname "$rel")"`（いずれもrepo_root基準）。
  - 出力先は`$(dirname "$file")/index.jsonl`（そのmarkdownファイルが直接属するディレクトリ）。
  - 出力先ディレクトリごとに初回だけ`index.jsonl`を切り詰める（連想配列`seen_dirs`で管理し、
    同じ出力先が複数ファイルにまたがる場合は追記していく）。
- 完了後、生成した`index.jsonl`のパス一覧を標準エラーへ報告する（現行の単一パス報告から複数件対応へ）。

### 3. 既存の`index.jsonl`（round4で誤った形式で生成・コミット済み）を再生成する

現在コミット済みの8ファイル（`docs/index.jsonl`, `dev-tools/index.jsonl`, `tests/index.jsonl`,
`.claude/index.jsonl`, `plans/index.jsonl`, `worklog/index.jsonl`,
`.github/ISSUE_TEMPLATE/index.jsonl`, `.gitlab/issue_templates/index.jsonl`）は誤った集約方式の
ため、リポジトリルートで一旦すべて削除したうえで、新しい`extract-frontmatter.sh .`の1回実行で
再生成し直す（正しい設計では、リポジトリルート自身の`index.md`等も含め、より多くのディレクトリに
`index.jsonl`が新設される）。

### 4. テストへの反映

`tests/test_extract_frontmatter.sh`が検証している`concept_id`・`directory`導出ロジック
（`${rel%.md}`, `dirname`のテストケース）は、repo_root基準の相対パス計算という前提を反映するよう
コメント・アサーションを見直す（`frontmatter_to_json`本体のテストは変更不要）。

## 対象外

- `frontmatter_to_json`（YAML→JSON変換、yq優先利用）のロジックは変更しない。
- `.gitignore`の変更は不要（round4で既に`index.jsonl`除外ルールを削除済み）。

## 検証方法

- `bash dev-tools/src/extract-frontmatter.sh .`をリポジトリルートで1回実行し、markdownが存在する
  全ディレクトリ（`.`自身、`.claude/agents`, `.claude/rules`, `.claude/skills/ahk-implement`,
  `.claude/skills/issue-mr-flow`, `.github/ISSUE_TEMPLATE`, `.gitlab/issue_templates`,
  `dev-tools/docs`, `dev-tools/docs/ddr`, `dev-tools/docs/spec`, `docs`, `docs/ddr`, `docs/spec`,
  `plans`, `tests`, `worklog`）に`index.jsonl`が生成されることを確認する。
- 生成された全`index.jsonl`の各行が`jq empty`で妥当なJSONであること、`concept_id`が
  リポジトリルートからの相対パス（例: `docs/spec/activity-status`, `.claude/rules/ahk-style`）に
  なっていることを確認する。
- `bash tests/test_extract_frontmatter.sh`が引き続き成功することを確認する。
- `git status`で意図した範囲のファイルのみが変更されていることを確認する。
