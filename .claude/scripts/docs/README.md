---
title: .claude/scripts/docs配下の目次
type: guide
description: .claude/scripts配下（AIエージェント専用スクリプト一式）のspec・ddrの位置づけと各ドキュメントへのリンクをまとめた目次
tags: [claude-scripts, docs, index, guide]
keywords: [正史仕様, 意思決定ログ, issue-mr-workflow, シェルスクリプト方針, frontmatter抽出, AI専用]
---

# .claude/scripts/docs 配下の目次

`.claude/scripts/` は、AIエージェント（Claude Code）が`.claude/skills/*`経由で能動的に実行する
スクリプト一式を、人間専用の開発補助ツール（`dev-tools/`）とは分離して管理するディレクトリ
（issue #24）。開発フロー全体は
[.claude/skills/issue-mr-flow/SKILL.md](../skills/issue-mr-flow/SKILL.md)
（唯一の実装フロー定義）に従い、ドキュメントの置き場所・ライフサイクルは
[.claude/rules/docs-workflow.md](../rules/docs-workflow.md) の「ドキュメント運用」表を参照する。

- `spec/` ── AI専用スクリプト機能ごとの正史仕様（最新の仕様を上書き更新）
- `ddr/` ── AI専用スクリプト関連の意思決定ログ（DDR: Design Decision Record。追記のみ）

## spec（機能仕様）

- [issue-mr-workflow.md](spec/issue-mr-workflow.md) ── issue駆動MRワークフロー支援
- [shell-scripts.md](spec/shell-scripts.md) ── 開発補助スクリプトのシェル言語方針（PowerShell→bash）
- [extract-frontmatter.md](spec/extract-frontmatter.md) ── frontmatter抽出スクリプト（index.jsonl生成）

## ddr（意思決定ログ）

DDR（Design Decision Record）はADR（Architecture Decision Record）の考え方を拡張し、
architectureに限らない意思決定も記録対象とする（詳細は
[docs/ddr/0001-意思決定ログをADRからDDRへ改称.md](../../docs/ddr/0001-意思決定ログをADRからDDRへ改称.md)参照）。

- [0002-issue-mr-flowへの実装フロー統合.md](ddr/0002-issue-mr-flowへの実装フロー統合.md)
- [0003-レビュースレッド解決は自動化しない.md](ddr/0003-レビュースレッド解決は自動化しない.md)
- [0004-AI返信は署名で識別しbotアカウント分離は見送る.md](ddr/0004-AI返信は署名で識別しbotアカウント分離は見送る.md)
- [0005-DraftPR作成失敗時は空コミットで自動リトライする.md](ddr/0005-DraftPR作成失敗時は空コミットで自動リトライする.md)
- [0006-対応工数レポートはtranscript自前パースで実装する.md](ddr/0006-対応工数レポートはtranscript自前パースで実装する.md)
- [0007-hookのcommandはbashのPATH解決方式へ変更.md](ddr/0007-hookのcommandはbashのPATH解決方式へ変更.md)
- [0008-frontmatter抽出スクリプトの設計判断.md](ddr/0008-frontmatter抽出スクリプトの設計判断.md)
- [0009-Planモードre-entry時はgit checkout復元でなくarchiveスクリプトで対処する.md](ddr/0009-Planモードre-entry時はgit checkout復元でなくarchiveスクリプトで対処する.md)
- [0010-ブランチslugの意訳生成はAIエージェントが行う.md](ddr/0010-ブランチslugの意訳生成はAIエージェントが行う.md)
- [0011-issue作成は独立スキルとして新設する.md](ddr/0011-issue作成は独立スキルとして新設する.md)
- [0012-コミットはcommitスキル経由を機構的に強制する.md](ddr/0012-コミットはcommitスキル経由を機構的に強制する.md)
- [0013-dev-toolsをAI専用_人間専用に分離する.md](ddr/0013-dev-toolsをAI専用_人間専用に分離する.md)
- [0014-調査結果のhtml版は自己完結htmlのコミットで作る.md](ddr/0014-調査結果のhtml版は自己完結htmlのコミットで作る.md)
