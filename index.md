---
title: Repository Map
type: guide
description: プロジェクトルートから各ディレクトリへの相対パスと役割をまとめたリポジトリマップ
tags: [index, repository-map, guide]
keywords: [directory, repository-map, リポジトリマップ, ディレクトリ, src, docs, dev-tools, claude, plans, worklog]
---

# Repository Map

`nagame-ahk` リポジトリの主要ディレクトリの一覧。**各ディレクトリの役割説明は本ファイルを正とし**、
ファイル単位の詳細は記載しない（重複を避けるため）。ディレクトリツリー構造・配置ルール・個別
ファイルの役割は [.claude/rules/directory-structure.md](.claude/rules/directory-structure.md) を、
ドキュメントの置き場所・ライフサイクルは [.claude/rules/docs-workflow.md](.claude/rules/docs-workflow.md) を参照。

## Directory Structure

- [./src/](./src/) アプリ本体（AutoHotkey v2）のソースコード。`main.ahk` は `#Include` の集約と起動呼び出しのみを行う。
  - [./src/config/](./src/config/) 定数・ユーザー設定値（`Settings.ahk`）。
  - [./src/core/](./src/core/) 起動処理・ホットキー登録・トレイメニューなどアプリのライフサイクル管理。
  - [./src/features/](./src/features/) 機能単位の自動化ロジック（1機能 = 1ファイル目安）。
  - [./src/lib/](./src/lib/) 複数機能から使い回す汎用ユーティリティ。
- [./assets/icons/](./assets/icons/) トレイアイコンなどのアプリアイコン素材。
- [./docs/](./docs/) アプリ本体の設計ドキュメント。
  - [./docs/spec/](./docs/spec/) 機能ごとの正史仕様（最新の仕様を上書き更新）。
  - [./docs/ddr/](./docs/ddr/) 意思決定ログ（DDR: Design Decision Record。追記のみ）。
- [./dev-tools/](./dev-tools/) 人間専用の開発補助ツール一式（exe配布ビルド関連）。アプリ本体
  （`src/`, `docs/`）とは分離して管理する。AIエージェントが能動的に実行するスクリプトは
  `.claude/scripts/`に分離されている（issue #24）。
  - [./dev-tools/src/](./dev-tools/src/) exe配布ビルドスクリプト（bash）。
  - [./dev-tools/docs/](./dev-tools/docs/) dev-tools機能の設計ドキュメント。
    - [./dev-tools/docs/spec/](./dev-tools/docs/spec/) dev-tools機能ごとの正史仕様。
    - [./dev-tools/docs/ddr/](./dev-tools/docs/ddr/) dev-tools関連の意思決定ログ。
- [./tests/](./tests/) 手動/自動テスト用スクリプト（AutoHotkey・bash）。
  - [./tests/lib/](./tests/lib/) テスト共通処理（`Assert.ahk`）。
- [./.claude/](./.claude/) Claude Code向けのルール・スキル・エージェント・hook・スクリプト定義一式。
  - [./.claude/rules/](./.claude/rules/) AI向け詳細ルール（コーディング規約・ディレクトリ構成・ドキュメント運用等）。
  - [./.claude/skills/](./.claude/skills/) `/issue-mr-flow`（唯一の実装フロー定義）・`/ahk-implement` などのスキル定義。
  - [./.claude/agents/](./.claude/agents/) サブエージェント定義（コードレビュー・issue-mr-flow途中引き継ぎ等）。
  - [./.claude/scripts/](./.claude/scripts/) AIエージェントが`.claude/skills/*`経由で能動的に実行するスクリプト一式（issue #24）。
    - [./.claude/scripts/src/](./.claude/scripts/src/) issue駆動MRワークフロー支援スクリプト等（bash）。
      - [./.claude/scripts/src/vcs/](./.claude/scripts/src/vcs/) GitHub/GitLabの差異を吸収するVCS抽象化層（`Provider.sh`）。
    - [./.claude/scripts/docs/](./.claude/scripts/docs/) `.claude/scripts`機能の設計ドキュメント。
      - [./.claude/scripts/docs/spec/](./.claude/scripts/docs/spec/) 機能ごとの正史仕様。
      - [./.claude/scripts/docs/ddr/](./.claude/scripts/docs/ddr/) 関連の意思決定ログ。
  - [./.claude/hooks/](./.claude/hooks/) SessionStart/PostToolUse等のClaude Code hookスクリプト。
    - [./.claude/hooks/lib/](./.claude/hooks/lib/) 複数hookスクリプトで使い回す共通ロジック。
- [./.gemini/](./.gemini/) Gemini CLI向け設定（`settings.json`）。
- [./plans/](./plans/) AIエージェントのplanモードが出力する計画ファイル。タスクごとに新規生成しそのままコミットして履歴として残す。
- [./worklog/](./worklog/) 実装中の詳細な試行錯誤ログ（`日付_<planファイル名>.md`）。PR作成前の設計反映でspec/ddrへ反映し削除する。
- [./.github/ISSUE_TEMPLATE/](./.github/ISSUE_TEMPLATE/) GitHub用issueテンプレート（目的・現状・期待する動作・受け入れ条件）。
- [./.gitlab/issue_templates/](./.gitlab/issue_templates/) GitLab用issueテンプレート（同上）。
- [./build/](./build/) Ahk2Exeビルド成果物の出力先。`.gitignore` 対象でコミットしない（通常は空）。
