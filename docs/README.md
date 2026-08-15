# docs 配下の目次

`nagame-ahk` の開発フロー全体は [.claude/skills/issue-mr-flow/SKILL.md](../.claude/skills/issue-mr-flow/SKILL.md)
（唯一の実装フロー定義）、ドキュメントの置き場所・ライフサイクルは
[.claude/rules/docs-workflow.md](../.claude/rules/docs-workflow.md) の「ドキュメント運用」表を参照。

- `spec/` ── 機能ごとの正史仕様（最新の仕様を上書き更新）
- `adr/` ── 過去の設計決断のログ（追記のみ・変更不可）

## spec（機能仕様）

- [activity-status.md](spec/activity-status.md) ── 操作状態表示（ActivityStatus）
- [external-command-server.md](spec/external-command-server.md) ── 外部コマンドサーバー（ExternalCommandServer）
- [logger.md](spec/logger.md) ── ロガー（Logger）
- [office-file-watcher.md](spec/office-file-watcher.md) ── MS Officeファイル監視・情報表示（OfficeFileWatcher）
- [pdf-file-watcher.md](spec/pdf-file-watcher.md) ── PDFファイル監視・情報表示（PdfFileWatcher）
- [recent-docs-watcher.md](spec/recent-docs-watcher.md) ── 最近使ったファイル監視・通知（RecentDocsWatcher）

## adr（意思決定ログ）

- [0001-ahk2exeビルドの環境依存対応.md](adr/0001-ahk2exeビルドの環境依存対応.md) ── `/base`指定・BOM必須・出力ファイルでの成否判定
