# docs 配下の目次

`nagame-ahk` のドキュメント運用ルールは [.claude/rules/docs-workflow.md](../.claude/rules/docs-workflow.md) の「実装フロー（必須）」を参照。

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

まだ記録はありません。「後で『なぜこうなってるんだっけ』と聞かれそうな決定」をしたら
`docs/adr/0001-タイトル.md` の形式で追加してください。
