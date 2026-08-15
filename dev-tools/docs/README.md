# dev-tools/docs 配下の目次

`dev-tools/` は開発者向けツール（ビルド・配布まわり等）一式を、アプリ本体（`src/`, `docs/`）とは
分離して管理するディレクトリ。開発フロー全体は
[.claude/skills/issue-mr-flow/SKILL.md](../../.claude/skills/issue-mr-flow/SKILL.md)
（唯一の実装フロー定義）に従い、ドキュメントの置き場所・ライフサイクルは
[.claude/rules/docs-workflow.md](../../.claude/rules/docs-workflow.md) の「ドキュメント運用」表を参照する。

- `spec/` ── dev-tools機能ごとの正史仕様（最新の仕様を上書き更新）
- `adr/` ── dev-tools関連の意思決定ログ（追記のみ）

## spec（機能仕様）

- [distribution.md](spec/distribution.md) ── Windows用exe配布方法
- [issue-mr-workflow.md](spec/issue-mr-workflow.md) ── issue駆動MRワークフロー支援

## adr（意思決定ログ）

- [0001-ahk2exeビルドの環境依存対応.md](adr/0001-ahk2exeビルドの環境依存対応.md)
- [0002-issue-mr-flowへの実装フロー統合.md](adr/0002-issue-mr-flowへの実装フロー統合.md)
- [0003-レビュースレッド解決は自動化しない.md](adr/0003-レビュースレッド解決は自動化しない.md)
