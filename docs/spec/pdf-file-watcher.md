---
title: PDFファイル監視・情報表示（PdfFileWatcher）
type: spec
description: デスクトップPDFリーダーで開かれたファイルの名前・パス・プロセス情報を表示する機能の仕様
tags: [pdf-file-watcher, ahk, spec]
keywords: [setwineventhook, wmi, commandline, windowopenwatcher, traytip, acrobat]
---

# PDFファイル監視・情報表示（PdfFileWatcher）

## 背景・目的

[docs/spec/office-file-watcher.md](office-file-watcher.md) で実装したWord/Excel/PowerPoint/Visioのファイル
情報表示を、PDFファイルにも同じ体験で対応してほしいという要望を受けて追加する。
デスクトップ専用のPDFリーダーでファイルが開かれた際に、そのファイル名・保存先パスと、ファイルを開いている
プロセスの情報をすぐに確認できるようにする。

## 仕様

### 検出方法

- `docs/spec/office-file-watcher.md` の実装過程で `SetWinEventHook` によるウィンドウ検出・hwnd重複排除ロジックを
  `lib/WindowOpenWatcher.ahk` に共通化した（詳細・移行理由は[docs/spec/office-file-watcher.md](office-file-watcher.md)
  の「検出方法」節を参照）。`PdfFileWatcher`はこの共通基盤を、対象プロセス名を`Settings.PdfProcessNames`に
  差し替えて利用する。検出の仕組み自体（`EVENT_OBJECT_SHOW`監視、通知済みhwndでの重複排除等）はOffice側と同一。

### 対象プロセス

デスクトップ専用のPDFリーダーのみを対象とする（ブラウザ内蔵ビューアは対象外。理由は「未決定事項・懸念点」参照）。

| リーダー | プロセス名 |
|---|---|
| Adobe Acrobat Reader | `AcroRd32.exe` |
| Adobe Acrobat | `Acrobat.exe` |
| SumatraPDF | `SumatraPDF.exe` |
| Foxit Reader | `FoxitPDFReader.exe` / `FoxitReader.exe`（バージョンにより名称が異なる。両方登録しておく） |

`Settings.PdfProcessNames` にこれらをまとめる。

### ファイル情報の取得

Office版のように全リーダー共通で使える自動化オブジェクトモデル（`AccessibleObjectFromWindow` +
`OBJID_NATIVEOM`相当）は無いため、**WMI経由でプロセスの起動コマンドラインを取得し、そこから`.pdf`パスを
抽出する**方式を採る。

1. `WinGetPID(hwnd)` で対象ウィンドウのプロセスIDを取得する。
2. WMI（`ComObjGet("winmgmts:\\.\root\cimv2")` → `Win32_Process`）で該当PIDの`CommandLine`プロパティを取得する。
   ```
   wmi := ComObjGet("winmgmts:\\.\root\cimv2")
   results := wmi.ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" pid)
   ```
3. 取得したコマンドライン文字列から、正規表現で`.pdf`で終わるパスを抽出する。
   - まず `"..."` で囲まれた`.pdf`パスを優先的に探す（パスにスペースを含む場合の引用符付き引数に対応するため）。
   - 見つからなければ、空白区切りの最後のトークンが`.pdf`で終わっていればそれを使う。
4. 抽出できたパスが`FileExist()`で実在確認できた場合のみ採用する。
5. 上記いずれかの手順（WMI取得・正規表現抽出・実在確認）に失敗した場合は空文字列を返し、`_CollectFileInfo`
   相当のロジックで`pathResolved:false`・ウィンドウタイトルのみのフォールバック表示に切り替える
   （Office版と同じフォールバック方針）。

この方式は「PDFをエクスプローラー等からダブルクリックして新規プロセスとして開く」典型的な操作では機能するが、
既に起動中のリーダーで2つ目以降のファイルを開いた場合は機能しない（「未決定事項・懸念点」参照）。

### プロセス情報の取得

Office版と同様、`WinGetProcessName(hwnd)` / `WinGetPID(hwnd)` / `WinGetProcessPath(hwnd)` でプロセス名・
プロセスID・実行ファイルのフルパスを取得する。

### TrayTip表示内容（JSON）

`lib/FileOpenNotifier.ahk`（Office版と共通）を使い、以下の形のJSONをTrayTipで表示する。

- タイトル: `"PDFファイルが開かれました"`
- 本文（JSON）:

```json
{"type":"PDF","fileName":"仕様書.pdf","path":"C:\\Users\\...\\仕様書.pdf","pathResolved":true,"windowTitle":"仕様書.pdf - Adobe Acrobat Reader","process":{"name":"AcroRd32.exe","pid":23456,"path":"C:\\Program Files (x86)\\Adobe\\Acrobat Reader DC\\Reader\\AcroRd32.exe"}}
```

- `type`はOffice版のようにアプリ種別ごとに変えず、常に `"PDF"` 固定とする。開いたリーダーの区別は
  `process.name`で判別できるため、`type`は「ファイルの種類」を表す値として単純化する。
- `path`/`pathResolved`/`windowTitle`のフォールバック方針はOffice版と同じ。

### 操作方法

- アプリ起動時に `Settings.PdfWatchAutoStart`（既定 `true`）が `true` であれば自動的に監視を開始する
  （`App.Start()` から `PdfFileWatcher.Start()` を呼び出し）。
- トレイメニュー「PDF監視」からON/OFFを切り替え可能。チェック状態は `PdfFileWatcher.Enabled` と同期する
  （`TrayMenu.SyncPdfWatchCheck`、Office監視と同様のパターン）。
- 専用ホットキーは設けない（自動検出のため、Office版と同様）。

## 影響範囲

- 追加: `src/features/PdfFileWatcher.ahk`
- 追加（Office側と共通化のためのリファクタ。詳細は[docs/spec/office-file-watcher.md](office-file-watcher.md)参照）:
  `src/lib/WindowOpenWatcher.ahk`、`src/lib/FileOpenNotifier.ahk`
- 変更: `src/config/Settings.ahk`（`PdfProcessNames` / `PdfWatchAutoStart` / `PdfWatchTrayTipDurationMs` 追加）
- 変更: `src/core/App.ahk`（起動時に `PdfFileWatcher.Start()` 呼び出し）
- 変更: `src/core/TrayMenu.ahk`（メニュー項目「PDF監視」・チェック同期メソッド追加）
- 変更: `src/main.ahk`（`#Include`追加。lib 2ファイル、features 1ファイル）
- 変更: `src/features/OfficeFileWatcher.ahk`（共通ロジックを`lib/`側に委譲するリファクタ。詳細は
  [docs/spec/office-file-watcher.md](office-file-watcher.md)参照）

## 設定項目

| 設定値 | 既定値 | 説明 |
|---|---|---|
| `Settings.PdfProcessNames` | `Array("AcroRd32.exe", "Acrobat.exe", "SumatraPDF.exe", "FoxitPDFReader.exe", "FoxitReader.exe")` | 監視対象のPDFリーダーのプロセス名 |
| `Settings.PdfWatchAutoStart` | `true` | アプリ起動時に自動的に監視を開始するか |
| `Settings.PdfWatchTrayTipDurationMs` | `5000` | TrayTip（JSON表示）を明示的に消すまでの時間(ms) |

## 未決定事項・懸念点

- 対象exeの正確な名称・パスは実機未確認。特にFoxit Readerはバージョンによって`FoxitReader.exe`と
  `FoxitPDFReader.exe`が混在しているため両方登録しているが、他にも表記揺れがある可能性がある。
  実際にインストールされている環境で確認・調整が必要。
- Adobe Acrobat/Readerが保護モード（Protected Mode / サンドボックス）で動作している場合、実際に
  ドキュメントを保持しているプロセスと、ユーザーに見えるトップレベルウィンドウのプロセスが分離している
  可能性がある。その場合`WinGetPID(hwnd)`で取得できるPIDのコマンドラインにファイルパスが含まれず、
  フォールバック表示になる可能性がある（実機での挙動要確認）。
- 既に起動中のリーダーに2つ目以降のPDFを開いた場合（新規プロセスではなく既存プロセス内に新規ウィンドウ/
  タブが増えるケース）、WMIから取得できるコマンドラインは最初に開いたファイルのままなので、2つ目以降の
  ファイルは正しく取得できない（タイトルのみのフォールバック表示になる）。これはOffice版の
  `AccessibleObjectFromWindow`方式に比べた明確な制約として許容する。
- ブラウザ内蔵PDFビューア（Microsoft Edge/Chrome等）は対象外とした。ブラウザは常時起動している
  タブ共有プロセスであり、「新規ウィンドウの表示=PDFファイルが開かれた」という前提が成立しにくく
  誤検知が多くなること、コマンドラインからも個別のPDFパスを特定できないことが理由。将来的に対応する
  場合は別途設計が必要。
- TrayTipの表示・上書きに関する懸念（[docs/spec/office-file-watcher.md](office-file-watcher.md)の該当節参照）は
  Office版と共通。
