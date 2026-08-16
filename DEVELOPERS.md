---
title: 開発者向けドキュメント
type: guide
description: nagame-ahkの開発に参加する人向けの動作環境・関連ドキュメントへの入り口をまとめたガイド
tags: [developers, guide]
keywords: [autohotkey-v2, directory-structure, docs-spec, ahk2exe, build, issue-mr-flow, distribution, release]
---

# 開発者向けドキュメント

`nagame-ahk` の開発に参加する人向けのドキュメント。exeファイルを使うだけのユーザー向け情報は
[README.md](README.md) を参照。

プロジェクト概要は [AGENTS.md](AGENTS.md)、コーディング規約・ディレクトリ構成などの詳細ルールは
[.claude/rules/](.claude/rules/) 配下を参照。開発者向けツール一式（ビルドスクリプト等）は
[dev-tools/](dev-tools/) 配下にアプリ本体と分離して置いている
（設計: [dev-tools/docs/spec/distribution.md](dev-tools/docs/spec/distribution.md)）。

## 動作環境

- AutoHotkey v2（v2.0系）。exeビルド時は同梱の Ahk2Exe も使用する。
- 推奨エディタ: VSCode + AutoHotkey v2 拡張機能（構文ハイライト・デバッグ用）。

## ソースから実行する

`src/main.ahk` を AutoHotkey v2 で実行する。

```
AutoHotkey64.exe src\main.ahk
```

## ディレクトリ構成

詳細は [.claude/rules/directory-structure.md](.claude/rules/directory-structure.md) を参照。

主な機能とその正史仕様（`docs/spec/`）は以下の通り。機能追加・変更時はまずここを確認する
（一覧は [docs/README.md](docs/README.md) にもある）。

- [activity-status.md](docs/spec/activity-status.md) ── 操作状態表示（ActivityStatus）
- [external-command-server.md](docs/spec/external-command-server.md) ── 外部コマンドサーバー（ExternalCommandServer）
- [logger.md](docs/spec/logger.md) ── ロガー（Logger）
- [office-file-watcher.md](docs/spec/office-file-watcher.md) ── MS Officeファイル監視・情報表示（OfficeFileWatcher）
- [pdf-file-watcher.md](docs/spec/pdf-file-watcher.md) ── PDFファイル監視・情報表示（PdfFileWatcher）
- [recent-docs-watcher.md](docs/spec/recent-docs-watcher.md) ── 最近使ったファイル監視・通知（RecentDocsWatcher）

## 実装フロー

新機能の追加や既存動作の変更を行う前に、必ずissueの起票→設計ドキュメント作成→人間の承認→
（必要に応じて）planモードでの合意→実装、という手順を踏む。詳細は
[.claude/skills/issue-mr-flow/SKILL.md](.claude/skills/issue-mr-flow/SKILL.md)（唯一の実装フロー定義）を参照
（AHK機能実装部分は `/ahk-implement` スキルとして手順化されている）。

## テスト

`tests/` 配下に手動/自動テスト用スクリプトがある。一覧・実行方法・手動確認手順は
[tests/README.md](tests/README.md) を参照。

## exeのビルド

前提: 開発者PCに AutoHotkey v2（Ahk2Exeを含む）がインストール済みであること。

```
powershell -File dev-tools\src\build.ps1
```

`build\nagame-ahk-vX.Y.Z.exe`（`.gitignore` 対象・コミット不要）が生成される。バージョンは
`src\main.ahk` 先頭の `;@Ahk2Exe-SetVersion` ディレクティブから取得する。

Ahk2Exe.exe が標準の場所（`%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe`）に無い場合は、
環境変数 `AHK2EXE_PATH` で実際のパスを指定する。同様にAutoHotkey v2本体
（既定 `%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe`）が標準の場所に無い場合は
`AHK_V2_EXE_PATH` で指定する（v1/v2が共存する環境ではAhk2Exeの既定baseがv1になっていることがあり、
`build.ps1` は `/base` でv2本体を明示指定してビルドする。経緯は
[dev-tools/docs/ddr/0001-ahk2exeビルドの環境依存対応.md](dev-tools/docs/ddr/0001-ahk2exeビルドの環境依存対応.md)参照）。

## リリース時の手順

1. `src\config\Settings.ahk` の `Version` を更新する。
2. `src\main.ahk` 先頭の `;@Ahk2Exe-SetVersion` を同じ値に手動で更新する（自動同期はしていない）。
3. 上記コマンドでビルドし、`build\nagame-ahk-vX.Y.Z.exe` を生成する。
4. 生成したexeを社内ファイルサーバーの配布先フォルダに手動でコピーし、配置場所を案内する
   （GitHub Releasesは使わない）。

## 未整備・今後整理する点

- ファイルサーバー上の配置パス・命名規則、旧バージョンの扱いは未確定。
- 詳細な設計・未決定事項は [dev-tools/docs/spec/distribution.md](dev-tools/docs/spec/distribution.md) を参照。