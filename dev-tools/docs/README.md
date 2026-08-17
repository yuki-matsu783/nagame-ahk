---
title: dev-tools/docs配下の目次
type: guide
description: dev-tools配下（人間専用の開発補助ツール。exe配布ビルド関連）のspec・ddrの位置づけと各ドキュメントへのリンクをまとめた目次
tags: [dev-tools, docs, index, guide]
keywords: [正史仕様, 意思決定ログ, 配布, ビルド, ahk2exe]
---

# dev-tools/docs 配下の目次

`dev-tools/` は、人間（開発者）が手動で実行する開発補助ツール（exe配布ビルド関連）一式を、
アプリ本体（`src/`, `docs/`）とは分離して管理するディレクトリ。AIエージェントが
`.claude/skills/*`経由で能動的に実行するスクリプト一式は`.claude/scripts/`に分離されている
（詳細: [.claude/scripts/docs/README.md](../../.claude/scripts/docs/README.md)、issue #24）。
開発フロー全体は
[.claude/skills/issue-mr-flow/SKILL.md](../../.claude/skills/issue-mr-flow/SKILL.md)
（唯一の実装フロー定義）に従い、ドキュメントの置き場所・ライフサイクルは
[.claude/rules/docs-workflow.md](../../.claude/rules/docs-workflow.md) の「ドキュメント運用」表を参照する。

- `spec/` ── dev-tools機能ごとの正史仕様（最新の仕様を上書き更新）
- `ddr/` ── dev-tools関連の意思決定ログ（DDR: Design Decision Record。追記のみ）

## spec（機能仕様）

- [distribution.md](spec/distribution.md) ── Windows用exe配布方法

## ddr（意思決定ログ）

DDR（Design Decision Record）はADR（Architecture Decision Record）の考え方を拡張し、
architectureに限らない意思決定も記録対象とする（詳細は
[docs/ddr/0001-意思決定ログをADRからDDRへ改称.md](../../docs/ddr/0001-意思決定ログをADRからDDRへ改称.md)参照）。

- [0001-ahk2exeビルドの環境依存対応.md](ddr/0001-ahk2exeビルドの環境依存対応.md)
