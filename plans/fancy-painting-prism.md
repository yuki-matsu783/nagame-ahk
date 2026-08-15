# README.md / DEVELOPERS.md の書き分け

## Context

現状の `README.md` は「`src/main.ahk` をAutoHotkey v2で実行する」という開発者向けの案内のみで、
exe配布（`dev-tools/src/build.ps1` でビルドし社内ファイルサーバーで配布する運用、
[dev-tools/docs/spec/distribution.md](../dev-tools/docs/spec/distribution.md)）を受け取って使う
一般ユーザー向けの内容になっていない。一方 `DEVELOPERS.md` はビルド・リリース手順のみで、
開発に参加する人が最初に知るべき情報（ディレクトリ構成・実装フロー・テスト方法・機能一覧）への
導線が無い。

今回、現在のソースコード（`src/`）と各機能の正史仕様（`docs/spec/*.md`）をもとに、両ファイルを
「誰向けのドキュメントか」で明確に書き分ける。

- **README.md**: exeファイル（`nagame-ahk-vX.Y.Z.exe`）を受け取って使うエンドユーザー向け。
  ソースコードやビルドの話はしない。
- **DEVELOPERS.md**: このプロジェクトの開発に参加する人向け。既存のビルド・リリース手順は残しつつ、
  開発の始め方（実行方法・ディレクトリ構成・実装フロー・テスト）への導線を加える。

いずれも**既存の詳細ドキュメント（`.claude/rules/*.md`, `docs/spec/*.md`, `dev-tools/docs/*.md`,
`tests/README.md`）の内容を重複して書き写すのではなく、要点とリンクでまとめる**方針とする
（`docs-workflow.md` の「情報の寿命で置き場所を切り分ける」考え方に合わせる）。

## README.md（エンドユーザー向け）の構成

現ソースコード（`src/core/App.ahk`, `TrayMenu.ahk`, `Hotkeys.ahk`, `config/Settings.ahk`）と
各 `docs/spec/*.md` の「操作方法」節に基づき記載する。

1. **概要**: 常駐して動く自動化ツールであること（トレイに常駐、ホットキー／ウィンドウイベント起点）。
2. **入手方法**: 開発者から配布される `nagame-ahk-vX.Y.Z.exe` を受け取って使う。AutoHotkey本体の
   インストールは不要（exe単体で動作する）。GitHub Releasesではなく社内ファイルサーバー経由で
   配布される旨。
3. **使い方**: exeをダブルクリックで起動 → タスクトレイに常駐。
4. **トレイメニュー**: `TrayMenu.Setup()` の並び通りに、各項目（操作状態表示／外部コマンド受付／
   Office監視／PDF監視／最近使ったファイル通知／再読み込み／終了）を1行ずつ説明する。
5. **ホットキー**: `Hotkeys.Register()` の内容（`Ctrl+Alt+A` で操作状態表示ON/OFF）を記載する。
   `Ctrl+Alt+N` はサンプル実装（ログ出力のみ）である旨を明記する。
6. **常駐機能の説明**（既定で自動的に動く3機能。各 `docs/spec/*.md` の「背景・目的」「操作方法」を
   ユーザー向けに要約）:
   - Office監視: Word/Excel/PowerPoint/Visioでファイルを開くとTrayTipで情報表示
   - PDF監視: 主要PDFリーダーでファイルを開くとTrayTipで情報表示（対応リーダーを列挙）
   - 最近使ったファイル通知: ファイル種別を問わず「開いたこと」を軽量にTrayTip通知
     （Windowsの「最近使った項目の記録」設定に依存する注意点を明記）
7. **外部コマンド受付（上級者・自動化向け）**: Python等の外部プロセスからの操作を受け付けるTCP
   サーバー機能があることを紹介する程度に留め、プロトコル詳細は
   [docs/spec/external-command-server.md](../docs/spec/external-command-server.md) にリンクする。
8. **ログ**: `nagame-ahk.log`（exeの1つ上の階層に生成される。`Settings.LogFilePath` の
   `A_ScriptDir "\..\"` 仕様に基づく）の場所と用途。
9. **終了方法**: トレイメニュー「終了」。
10. **開発者向け情報へのリンク**: 末尾に「開発に参加する場合は [DEVELOPERS.md](DEVELOPERS.md) を
    参照」を残す（現行README.mdの記載を踏襲）。

## DEVELOPERS.md（開発者向け）の構成

既存の「exeのビルド」「リリース時の手順」「未整備・今後整理する点」の節は**そのまま残し**、
その前に開発の始め方の節を追加する構成にする。

1. **概要・関連ドキュメント**（既存の書き出しを踏襲・整理）: プロジェクト概要は
   [AGENTS.md](AGENTS.md) 、コーディング規約・ディレクトリ構成は `.claude/rules/*.md` を参照。
2. **動作環境**: AutoHotkey v2.0系（+ Ahk2Exe、ビルド時のみ）。推奨エディタ（VSCode + AutoHotkey v2
   拡張機能）。
3. **ソースから実行する方法**: `src/main.ahk` をAutoHotkey v2で実行する。
4. **ディレクトリ構成**: 詳細は
   [.claude/rules/directory-structure.md](.claude/rules/directory-structure.md) を参照、のリンクのみ
   （重複して書き写さない）。主要機能一覧として `docs/spec/*.md` 6件へのリンク集を掲載する
   （`docs/README.md` と同内容の要約）。
5. **実装フロー**: 新機能追加・既存動作変更の際は
   [.claude/rules/docs-workflow.md](.claude/rules/docs-workflow.md) の手順（設計ドキュメント作成→
   承認→plan→実装）に従う旨、`/ahk-implement` スキルで自動化されている旨を記載。
6. **テスト**: [tests/README.md](tests/README.md) に一覧・実行方法があることを案内。
7. **（既存）exeのビルド** ── 現行内容を維持。
8. **（既存）リリース時の手順** ── 現行内容を維持。
9. **（既存）未整備・今後整理する点** ── 現行内容を維持。

## 対象ファイル

- 変更: [README.md](../README.md)（全面書き直し）
- 変更: [DEVELOPERS.md](../DEVELOPERS.md)（冒頭に開発の始め方を追加、ビルド以降は現状維持）

新規ファイル・コード変更・`docs/spec` の変更は無し（既存仕様の記載を整理するのみのため、
`docs-workflow.md` の実装フローは対象外）。

## 確認方法

- 目視レビュー: README.mdが「exeユーザーがこれだけ読めば使える」内容になっているか、
  DEVELOPERS.mdが「開発参加者が最初に読む入り口」として機能し既存の詳細ドキュメントへ
  正しくリンクしているかを確認する。
- リンク切れが無いこと（相対パスで指しているファイルが実在すること）を確認する。
