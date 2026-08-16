---
title: Windows用exe配布方法
type: spec
description: Ahk2Exeを使ったnagame-ahkのexeビルド・社内配布方法の仕様
tags: [distribution, ahk2exe, spec]
keywords: [ビルドスクリプト, ahk2exe, exe配布, アイコン, バージョン, ファイルサーバー]
---

# Windows用exe配布方法

## 背景・目的

`nagame-ahk` は現状 `src/main.ahk` をAutoHotkey v2ランタイムで直接実行する運用のみで、
AutoHotkey本体をインストールしていない人には使ってもらえない。開発者以外にも使ってもらうため、
Ahk2Exe（AutoHotkey v2付属のコンパイラ）で単体のexeを生成し、社内ファイルサーバーに置いて案内する
運用を整備する。開発者向けのビルド・配布まわりはアプリ本体の機能（`src/`, `docs/`）とは分離し、
`dev-tools/` 配下で独立管理する（`.claude/rules/directory-structure.md` 参照）。

## 仕様

- **ビルド方法**: Ahk2Exeで `src/main.ahk` を単一のexeにコンパイルする。開発者PCに
  AutoHotkey v2 本体（Ahk2Exeを含む）がインストール済みであることを前提とする。
  Ahk2Exeの `/base` にAutoHotkey v2本体（`AutoHotkey64.exe`）を明示的に指定してコンパイルする
  （環境によっては既定のbaseがv1系になっていることがあるため。経緯は
  [dev-tools/docs/ddr/0001-ahk2exeビルドの環境依存対応.md](../ddr/0001-ahk2exeビルドの環境依存対応.md)参照）。
- **ビルドスクリプト**: `dev-tools/src/build.sh`（bash、実機で動作確認済み。git bash経由で実行する）。
  実行するとローカルのAhk2Exeを呼び出し、`build/nagame-ahk-vX.Y.Z.exe`（バージョン付きファイル名）を
  生成する。`build/` はリポジトリ直下に生成し、`.gitignore` の `/build/` 指定によりコミット対象外と
  する。Ahk2Exe本体・AutoHotkey v2本体のパスは環境変数 `AHK2EXE_PATH` / `AHK_V2_EXE_PATH` で
  上書きできる。Ahk2Exeへ渡す`/in` `/out` `/base` `/icon`はDOS形式の単一スラッシュ引数のため、
  git bashのパス自動変換を避けるために`//in`のように先頭を`//`にしている（詳細:
  `dev-tools/docs/spec/shell-scripts.md`「git bashのパス変換」節）。
- **バージョン・アプリ名の埋め込み**: `src/main.ahk` の先頭にAhk2Exeディレクティブ
  （`;@Ahk2Exe-SetName`, `;@Ahk2Exe-SetVersion`, `;@Ahk2Exe-SetProductName` 等）を追加し、
  `src/config/Settings.ahk` の `AppName` / `Version` の値と一致させる（自動連携はせず、
  リリース時に手動で両方の値を更新する運用とする）。
- **アイコン**: `assets/icons/icon.ico` にアプリアイコンを配置し、`src/main.ahk` の
  Ahk2Exeディレクティブ（`;@Ahk2Exe-SetMainIcon`）で指定する。ビルドスクリプト側でも
  同ファイルの存在を確認し `/icon` オプションとして渡す（保険として、ファイルが無い場合は
  Ahk2Exe既定アイコンのままビルドされる）。
- **配布ファイル名**: バージョンを含める（例: `nagame-ahk-v0.1.0.exe`）。
- **配布パッケージ**: exe本体と簡易説明書（ホットキー一覧・使い方等）をセットにする。
  説明書の内容・置き場所は `dev-tools/docs/` 配下に別途整理する（未決定事項参照）。
- **配布先**: GitHub Releasesは使わず、社内ファイルサーバーの所定フォルダにビルド成果物を
  手動でコピーし、配置先パスをチャット等で案内する運用とする（自動アップロードの仕組みは対象外）。

## 影響範囲

- 新規: `dev-tools/src/build.sh`（Ahk2Exe呼び出しビルドスクリプト）
- 新規: `dev-tools/docs/README.md`（dev-tools配下の目次）
- 新規: `dev-tools/docs/spec/distribution.md`（本ドキュメント）
- 変更: `.claude/rules/directory-structure.md`（`dev-tools/` の追記・完了済み）
- 変更: `src/main.ahk`（Ahk2Exeディレクティブコメント追加）
- 変更: `DEVELOPERS.md`（ビルド・配布手順を記載し `dev-tools/docs/` への導線とする）
- 変更: `assets/icons/icon.ico`（アプリアイコンを追加・完了済み）

## 設定項目

新規の `Settings` 値は不要。既存の `Settings.AppName` / `Settings.Version`
（`src/config/Settings.ahk`）をAhk2Exeディレクティブ側の値と手動で同期させる。

## 未決定事項・懸念点

- 配布に同梱する使い方説明書のフォーマット・具体的な置き場所（`dev-tools/docs/` 配下に
  新規ファイルを作る想定だが、ファイル名・内容は未確定）
- ファイルサーバー上の配置パス・命名規則の具体（フォルダ構成、旧バージョンの扱い等）
- バージョン更新（`Settings.Version` とAhk2Exeディレクティブの手動同期）の運用ルール
  （リリースのたびに誰が・どのタイミングで上げるか）
- `dev-tools/` 配下に `HANDOFF.md` 相当のものを別途持たせるか、
  ルート直下の既存ファイルをそのまま使うか
