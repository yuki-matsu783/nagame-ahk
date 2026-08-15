# dev-tools/docs 配下の目次

`dev-tools/` は開発者向けツール（ビルド・配布まわり等）一式を、アプリ本体（`src/`, `docs/`）とは
分離して管理するディレクトリ。ドキュメント運用ルールはアプリ本体側と同様、
[.claude/rules/docs-workflow.md](../../.claude/rules/docs-workflow.md) の「実装フロー（必須）」に従う。

- `spec/` ── dev-tools機能ごとの正史仕様（最新の仕様を上書き更新）

## spec（機能仕様）

- [distribution.md](spec/distribution.md) ── Windows用exe配布方法
- [issue-mr-workflow.md](spec/issue-mr-workflow.md) ── issue駆動MRワークフロー支援
