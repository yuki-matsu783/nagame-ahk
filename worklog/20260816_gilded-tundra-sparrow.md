---
title: "worklog: 各ディレクトリのindex.jsonl生成・git管理化"
type: guide
description: extract-frontmatter.shをindex.mdの主要ディレクトリごとに実行し、index.jsonlをgit管理下に置いた作業ログ
tags: [dev-tools, frontmatter, jsonl]
keywords: [extract-frontmatter, index.jsonl, gitignore, リポジトリマップ, 生成物管理]
---

# worklog: 各ディレクトリのindex.jsonl生成・git管理化

対象: PR #23、`dev-tools/src/extract-frontmatter.sh`の生成物をgit管理下に置く対応（2026-08-16）。
plan: `plans/gilded-tundra-sparrow.md`

## 試したこと

- 対象ディレクトリの粒度をAskUserQuestionでユーザーに確認し、「`index.md`の主要ディレクトリごと」を選択。
- `.gitignore`からround2で追加した`index.jsonl`の除外ルールを削除。
- `index.md`のトップレベル箇条書きのうち、markdownファイルを含む8ディレクトリ
  （`docs/`, `dev-tools/`, `tests/`, `.claude/`, `plans/`, `worklog/`, `.github/ISSUE_TEMPLATE/`,
  `.gitlab/issue_templates/`）に対して`extract-frontmatter.sh`を実行し、各ディレクトリ直下に
  `index.jsonl`を生成。markdownファイルが無い`src/`, `assets/icons/`, `.gemini/`, `build/`は対象外。

## うまくいったこと

- 全8ファイル・計42行が`jq empty`で妥当なJSONであることを確認。`.claude/index.jsonl`では
  `ahk-style.md`のブロック配列（`paths`）が正しく配列としてパースされていることをスポットチェック済み。
- `plans/index.jsonl`は4件（`immutable-painting-kitten`, `purrfect-churning-oasis`,
  `ember-quilted-narwhal`, `gilded-tundra-sparrow`）となり、frontmatterを持たない
  `immutable-painting-kitten`は`frontmatter: null`として正しく扱われた。

## ダメだったこと

- 特になし。

## 次の一歩

- 特になし（完了）。今後frontmatterやmarkdownファイルが変わるたびに、該当ディレクトリで
  スクリプトを再実行し`index.jsonl`を更新する運用となる（自動更新の仕組みは今回未導入。
  設計反映時にdev-tools/docs/spec/へ運用上の注意点として記録する）。
