---
title: 0002. issue-mr-flowへの実装フロー統合と「reflect」の分割
type: ddr
description: issue駆動MRワークフロー支援をissue-mr-flowへ統合し、reflectステップを分割した経緯を記録したDDR
tags: [issue-mr-flow, workflow, ddr]
keywords: [skill-md, docs-workflow, git-workflow, 設計反映, aiアセット改善, 実装フロー統合]
---

# 0002. issue-mr-flowへの実装フロー統合と「reflect」の分割

## 背景

issue駆動MRワークフロー支援（PR #4）は当初、「`.claude/rules/docs-workflow.md` の
「実装フロー（必須）」・`.claude/rules/git-workflow.md` を置き換えない、issue取得・ブランチ/MR作成・
レビューコメント取得・MR description更新だけを自動化する薄い層」として設計した
（[dev-tools/docs/spec/issue-mr-workflow.md](../../dev-tools/docs/spec/issue-mr-workflow.md)）。

PR #4へのレビューで以下2点の指摘を受けた（`/issue-mr-flow comments` で取得）。

1. 実装フローが `docs-workflow.md` / `git-workflow.md` / `.claude/skills/issue-mr-flow/SKILL.md` /
   `dev-tools/docs/spec/issue-mr-workflow.md` に分散しており、「今のワークフローを作り変えて、
   issue-mr-flowに統一したい」。
2. `docs-workflow.md` / `git-workflow.md` で使っていた「reflect」という用語が何をする手順なのか
   分かりにくい。

## 決定

### 1. `.claude/skills/issue-mr-flow/SKILL.md` を唯一の実装フロー定義にする

`docs-workflow.md` の「実装フロー（必須）」と `git-workflow.md` の手順（ブランチ運用・worklogと
reflect・PR・マージ）のうち、**順序立ったフロー部分**を `.claude/skills/issue-mr-flow/SKILL.md` に
統合した。`docs-workflow.md` / `git-workflow.md` はドキュメントの置き場所・ライフサイクル参照表や
ブランチ命名規則など、フロー本体ではない参照情報のみを残し、冒頭でSKILL.mdへのポインタを置く。
`.claude/skills/ahk-implement/SKILL.md` は独立した最上位エントリーポイントではなく、
issue-mr-flowの「設計ドキュメント作成〜実装」ステップから呼ばれるサブフローという位置づけに変更した。

今後はごく小さな変更（誤字修正等、`git-workflow.md` の「適用範囲」に定める例外）を除き、
あらゆるタスクをissue起点で進める前提とする。

### 2. 「reflect」を「設計反映」と「AIアセット改善」に分割する

従来の「reflect」は実際には2つの異なる作業を指していた。

- **設計反映**: `plans/` `worklog/` の内容を `docs/spec/` `docs/ddr/` へ反映する（従来のreflectの主内容）
- **AIアセット改善**: 作業中に気づいたルール・スキルの不備を `.claude/rules/` `.claude/skills/`
  `CLAUDE.md` `AGENTS.md` に反映する（今回のこの変更自体が該当する。従来は無名だった）

英語の借用語「reflect」を使わず、上記2つの日本語名でそれぞれ明示的に呼ぶことにした。

## 却下した案

- `docs-workflow.md` / `git-workflow.md` をそのまま残し、`issue-mr-flow/SKILL.md` 側にも
  全体フローの説明を追加するだけの案: 同じ手順が複数ファイルに重複し、将来の更新で内容が
  ドリフトするリスクが高いため不採用。手順の実体は1箇所（SKILL.md）に集約し、他のファイルからは
  参照のみとする方針にした。
- 「reflect」を単純に日本語の同義語（例:「反映」）へ置き換えるだけの案: 「反映」は本プロジェクトで
  既に「設計ドキュメントへ変更内容を反映する」等、より広い意味の一般動詞としても使われており、
  置き換えるだけでは曖昧さが解消しない。2つの異なる作業として名前を分けることにした。
