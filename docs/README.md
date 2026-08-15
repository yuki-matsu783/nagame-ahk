---
title: docs配下の目次
type: guide
description: docs/spec・docs/ddrの位置づけと各ドキュメントへのリンクをまとめた目次
tags: [docs, index, guide]
timestamp: "2026-08-16T05:31:36"
---

# docs 配下の目次

`nagame-ahk` の開発フロー全体は [.claude/skills/issue-mr-flow/SKILL.md](../.claude/skills/issue-mr-flow/SKILL.md)
（唯一の実装フロー定義）、ドキュメントの置き場所・ライフサイクルは
[.claude/rules/docs-workflow.md](../.claude/rules/docs-workflow.md) の「ドキュメント運用」表を参照。

- `spec/` ── 機能ごとの正史仕様（最新の仕様を上書き更新）
- `ddr/` ── 過去の設計決断のログ（DDR: Design Decision Record。追記のみ・変更不可）

## spec（機能仕様）

- [activity-status.md](spec/activity-status.md) ── 操作状態表示（ActivityStatus）
- [external-command-server.md](spec/external-command-server.md) ── 外部コマンドサーバー（ExternalCommandServer）
- [logger.md](spec/logger.md) ── ロガー（Logger）
- [office-file-watcher.md](spec/office-file-watcher.md) ── MS Officeファイル監視・情報表示（OfficeFileWatcher）
- [pdf-file-watcher.md](spec/pdf-file-watcher.md) ── PDFファイル監視・情報表示（PdfFileWatcher）
- [recent-docs-watcher.md](spec/recent-docs-watcher.md) ── 最近使ったファイル監視・通知（RecentDocsWatcher）

## ddr（意思決定ログ）

DDR（Design Decision Record）はADR（Architecture Decision Record）の考え方を拡張し、
architectureに限らない意思決定（運用ルールの決定等）も記録対象とする。

- [0001-意思決定ログをADRからDDRへ改称.md](ddr/0001-意思決定ログをADRからDDRへ改称.md) ── adr→ddr改称の経緯
