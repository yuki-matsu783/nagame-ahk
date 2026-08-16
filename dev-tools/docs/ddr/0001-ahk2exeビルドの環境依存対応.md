---
title: "0001. Ahk2Exeビルドの環境依存対応（`/base`指定・BOM必須・出力ファイルでの成否判定）"
type: ddr
description: "Ahk2Exeビルドで発生した環境依存問題（AutoHotkey v1/v2混在・BOM・出力判定）への対応を記録したDDR"
tags: [ahk2exe, build, ddr]
keywords: [base-option, bom, v1-v2-conflict, exit-code, output-file-check, ahk2exe]
---

# 0001. Ahk2Exeビルドの環境依存対応（`/base`指定・BOM必須・出力ファイルでの成否判定）

## 背景

`dev-tools/src/build.ps1`（設計: [dev-tools/docs/spec/distribution.md](../../dev-tools/docs/spec/distribution.md)）の
実装・動作確認中に、開発者PC固有の環境要因により以下の問題が発生した。

## 決定

### 1. Ahk2Exeに `/base` でAutoHotkey v2本体を明示指定する

開発者PCには AutoHotkey v1系とv2系が共存しており、既定の `Ahk2Exe.exe`（`...\AutoHotkey\Compiler\`配下）は
v1系のbaseファイル（`.bin`）を既定として使う構成だった。そのため `/base` を省略すると、
`#Requires AutoHotkey v2.0` を含む `main.ahk` のコンパイル時に
「This script requires AutoHotkey v2.0, but you have v1.1.34.02」で失敗する。
`build.ps1` では `/base` に AutoHotkey v2 本体（既定 `...\AutoHotkey\v2\AutoHotkey64.exe`、
環境変数 `AHK_V2_EXE_PATH` で上書き可）を明示的に渡すことで回避する。

### 2. `build.ps1` の `.ps1` ファイル自体をUTF-8 BOM付きで保存する

Windows PowerShell 5.1は、BOMの無いUTF-8スクリプトを実行時にシステムのANSIコードページ
（日本語環境ではShift-JIS）として解釈するため、スクリプト中の日本語コメントが文字化けし、
文字化けした文字が構文解析を壊してパースエラーを引き起こした（`tests/*.ps1` も同様にBOM付きUTF-8）。
`dev-tools/src/build.ps1` もBOM付きUTF-8で保存する。

### 3. ビルド成否を `$LASTEXITCODE` ではなく出力ファイルの存在で判定する

`Ahk2Exe.exe` はGUIサブシステムのアプリで、`$LASTEXITCODE` が信頼できる値を返さない
（コンパイル成功時でも空になることがある）。また、呼び出し元への制御復帰後もファイル書き込みが
数秒遅れて完了することがある。そのため `build.ps1` では、呼び出し後に出力exeファイルの存在を
最大20秒リトライしながら確認する方式で成否判定する。

## 却下した案

- `$LASTEXITCODE` をそのまま信用する: 実機で成功時にも空になるケースを確認したため不採用。
- 出力ファイルの存在チェックをリトライ無し（即時1回のみ）にする: 実機でファイル生成が
  呼び出し元への復帰より数秒遅れるケースを確認したため、リトライを入れた。
