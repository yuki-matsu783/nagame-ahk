---
title: index.mdの主要ディレクトリごとにindex.jsonlを生成しgit管理下に置く
type: guide
description: dev-tools/src/extract-frontmatter.shをindex.mdの主要ディレクトリごとに実行し、生成されたindex.jsonlをgitignore対象から外してコミットする計画
tags: [dev-tools, frontmatter, jsonl]
keywords: [extract-frontmatter, index.jsonl, gitignore, リポジトリマップ, 生成物管理]
---

# plan: 各ディレクトリのindex.jsonl生成・git管理化

## Context

`dev-tools/src/extract-frontmatter.sh`（PR #23 round2で新規作成）はこれまで動作確認のたびに
生成・削除するだけで、生成物`index.jsonl`は`.gitignore`（round2で追加した`index.jsonl`パターン）
により非コミット対象としていた。ユーザーから「各ディレクトリのjsonl出力を実施し、gitignoreにせず
管理してほしい」との指示を受け、実際にコミット対象の成果物として扱う方針に変更する。

対象ディレクトリの粒度は、AskUserQuestionでユーザーに確認し「index.mdの主要ディレクトリごと」を
選択済み（1リポジトリルートのみの単一ファイル案、frontmatterを持つ最下層ディレクトリごとの案は不採用）。

## 実施内容

### 1. `.gitignore`からindex.jsonlの除外ルールを削除する

round2で追加した以下のブロックを削除する。

```
# dev-tools/src/extract-frontmatter.sh の生成物（実行のたびに上書きされるため非コミット対象）
index.jsonl
```

### 2. `index.md`の主要ディレクトリごとにスクリプトを実行する

`index.md`（Repository Map）のトップレベル箇条書きのうち、実際にmarkdownファイルを含む
ディレクトリに対して`bash dev-tools/src/extract-frontmatter.sh <dir>`を実行する。
markdownファイルが1つも無いディレクトリ（`src/`, `assets/icons/`, `.gemini/`, `build/`）は、
空の`index.jsonl`を生成する価値が無いため対象外とする。

実行対象（8ディレクトリ）: `docs/`, `dev-tools/`, `tests/`, `.claude/`, `plans/`, `worklog/`,
`.github/ISSUE_TEMPLATE/`, `.gitlab/issue_templates/`。

いずれも指定ディレクトリ配下を再帰的に走査する仕様のため、例えば`docs/`実行で`docs/spec/`
`docs/ddr/`配下も1つの`docs/index.jsonl`にまとめて含まれる（サブディレクトリごとに個別実行はしない）。

### 3. 生成された`index.jsonl`をコミット対象に追加する

`git add`で8ファイルをステージし、通常のcommit/pushフローに含める。

## 対象外

- `src/`, `assets/icons/`, `.gemini/`, `build/`（markdownファイルが無いため生成しない）。
- リポジトリルート直下の単独ファイル（`README.md`, `AGENTS.md`等）を集約する`./index.jsonl`は
  作成しない（`index.md`の箇条書きに対応する主要ディレクトリの単位に絞る）。
- スクリプト自体（`extract-frontmatter.sh`）のロジック変更は行わない（round3で実装済みのyq優先
  ＋フォールバック構成をそのまま使う）。
- 自動更新の仕組み（git hookでの自動再生成等）は今回は導入しない。今後frontmatterやmarkdown
  ファイルが変わるたびに再実行が必要になる点は、設計反映時にdev-tools/docs/spec/へ運用上の注意点
  として記録する。

## 検証方法

- `git status`で`.gitignore`の変更と8件の`index.jsonl`新規ファイルが検出されることを確認する。
- 各`index.jsonl`の全行が`jq empty`で妥当なJSONであることを確認する。
- `.claude/`実行分に`ahk-style.md`のブロック配列（`paths`）が正しく配列として入っていることを
  スポットチェックする。
- `git diff --stat`で意図しない他ファイルの変更が含まれていないことを確認する。
