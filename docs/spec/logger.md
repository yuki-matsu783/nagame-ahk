---
title: ロガー（Logger）
type: spec
description: ログレベル制御・コンソール/ファイル出力に対応した共通ロガーの仕様
tags: [logger, ahk, spec]
timestamp: "2026-08-16T05:31:36"
---

# ロガー（Logger）

## 背景・目的

エラー発生時の原因究明や動作確認を容易にするため、ログレベルを制御でき、コンソール・ファイルの両方に
出力できる共通ロガーを用意する。

## 仕様

- ログレベル: `DEBUG` < `INFO` < `WARN` < `ERROR` < `NONE`（`Logger.Levels` に重みを定義）。
- `Settings.LogLevel` で設定した値以上の重みのログのみ出力する（`Logger._ShouldOutput`）。未知の値が設定されていた場合は `INFO` 扱いにフォールバックする。
- 公開メソッド: `Logger.Debug(message)` / `Logger.Info(message)` / `Logger.Warn(message)` / `Logger.Error(message)`。
- 出力先1: コンソール（stdout）。`FileAppend(line, "*", "UTF-8-RAW")` を使用。エンコーディングを省略するとシステムのANSIコードページで書き込まれ、UTF-8前提でstdoutを読むツール（VSCode拡張のahk++等）で文字化けするため明示的にUTF-8を指定する。`"*"`(stdout)は永続ファイルハンドルを持たないため、BOM付きの `"UTF-8"` を指定すると行ごとにBOMが挿入されてしまう。そのためBOM無しの `"UTF-8-RAW"` を使う。AHKはGUIサブシステムのアプリのため、cmd/PowerShell等のコンソールから起動した場合のみ表示される。失敗時は握りつぶさず `OutputDebug` にフォールバックする。
- 出力先2: ファイル（`Settings.LogFilePath`、UTF-8）。失敗時は `OutputDebug` にフォールバックする。
- ログフォーマット: `yyyy-MM-dd HH:mm:ss [LEVEL] メッセージ`

## 影響範囲

- 変更: `src/lib/Logger.ahk`（レベル判定・コンソール出力を追加）
- 変更: `src/config/Settings.ahk`（`LogLevel` 追加、既定 `"INFO"`）

## 設定項目

| 設定値 | 既定値 | 説明 |
|---|---|---|
| `Settings.LogLevel` | `"INFO"` | 出力する最低ログレベル |

## 未決定事項・懸念点

- ログファイルのローテーション・サイズ上限は未実装（常駐アプリのため肥大化する可能性がある）。
- コンソール出力は、コンソールを持たない起動方法（アイコンダブルクリック等）では確認できない。DebugView等の併用が前提。
