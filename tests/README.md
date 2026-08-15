# tests/

手動/自動テスト用スクリプトを置くディレクトリ（`CLAUDE.md` 参照）。
機能の動作確認に使ったスクリプトは使い捨てにせず、ここに残して再実行できるようにする。

## 一覧

| ファイル | 対象 | 副作用 | 実行方法 |
|---|---|---|---|
| `test_json.ahk` | `src/lib/Json.ahk`（エンコード/デコード） | なし。GUIを開かずアサーション結果を標準出力してExitApp() | `AutoHotkey64.exe tests\test_json.ahk` |
| `test_external_command_server.ps1` | `docs/spec/external-command-server.md` の実装一式（TCPサーバー・認証・コマンドディスパッチ） | あり。`src/main.ahk` を実際に起動し、クリップボードを書き換え、トースト通知を表示する。実行中の `AutoHotkey64.exe` プロセスを名前で終了させる | `powershell -File tests\test_external_command_server.ps1` |
| `test_window_open_watcher.ahk` | `src/lib/WindowOpenWatcher.ahk`のうち、対象プロセス判定・複数インスタンスの独立性・通知済みhwnd管理など実ウィンドウ/実フック無しで検証できるロジック（`OfficeFileWatcher`/`PdfFileWatcher`共通の検出基盤） | なし。GUIを開かずアサーション結果を標準出力してExitApp() | `AutoHotkey64.exe tests\test_window_open_watcher.ahk` |
| `test_file_open_notifier.ahk` | `src/lib/FileOpenNotifier.ahk`のうち、検出結果のJSON整形ロジック（`OfficeFileWatcher`/`PdfFileWatcher`共通の表示基盤） | なし。GUIを開かずアサーション結果を標準出力してExitApp() | `AutoHotkey64.exe tests\test_file_open_notifier.ahk` |
| `test_office_file_watcher.ahk` | `src/features/OfficeFileWatcher.ahk`（`docs/spec/office-file-watcher.md`）のうち、種類名マッピング・ファイル名抽出・`WindowOpenWatcher`への委譲設定など実ウィンドウ/COM無しで検証できるロジック | なし。GUIを開かずアサーション結果を標準出力してExitApp() | `AutoHotkey64.exe tests\test_office_file_watcher.ahk` |
| `test_pdf_file_watcher.ahk` | `src/features/PdfFileWatcher.ahk`（`docs/spec/pdf-file-watcher.md`）のうち、コマンドラインからの`.pdf`パス抽出・ファイル名抽出・`WindowOpenWatcher`への委譲設定など実ウィンドウ/WMI無しで検証できるロジック | なし。GUIを開かずアサーション結果を標準出力してExitApp() | `AutoHotkey64.exe tests\test_pdf_file_watcher.ahk` |
| `test_recent_docs_watcher.ahk` | `src/features/RecentDocsWatcher.ahk`（`docs/spec/recent-docs-watcher.md`）のうち、`MRUListEx`/エントリの16進バイナリからの最新スロット・ファイル名抽出、JSON整形など実レジストリ/COM無しで検証できるロジック | なし。GUIを開かずアサーション結果を標準出力してExitApp() | `AutoHotkey64.exe tests\test_recent_docs_watcher.ahk` |

## 実行環境（AutoHotkey64.exeの場所）

上表の実行方法は `AutoHotkey64.exe` がPATHに通っている前提で書いているが、既定のインストーラでは
PATHに追加されない。PATHが通っていない場合はフルパスで実行する。

```
"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\test_json.ahk
```

インストール先が異なる場合は `C:\Program Files\AutoHotkey\` 以下を探す（v1/v2共存環境では
`AutoHotkey\v2\` 配下がv2用の実行ファイル）。

## 実行結果の見方

いずれも最後に `passed=<成功数> failures=<失敗数>` を出力し、失敗が1件でもあれば終了コード1を返す。
個別の失敗は `FAIL: <ラベル> expected=[...] actual=[...]` 形式で出力される。
各テストスクリプト共通の `Assert(actual, expected, label)` は `tests/lib/Assert.ahk` に切り出して
あり、各テストファイルはこれを `#Include` して使う（新規テストを追加する際も同様にする）。

## 対象外(手動確認が必要)

以下は実機の入力・GUI表示を伴い、自動テストで実行すると意図しない副作用(誤入力・マウス操作等)が
発生するため、自動テストの対象から外している。変更した場合は手動で動作確認すること。

- `SendKeys` / `MouseClick` / `MouseDrag` / `MouseScroll` / `PlayMacro`（実際のキー入力・マウス操作）
- `ShowInputDialog` / `ShowChoiceDialog`（ユーザー操作待ちのGUIダイアログ）
- `ShowMessageBox`（モーダルダイアログ。表示したままだとテストが進行しなくなる）
- `OfficeFileWatcher` の `SetWinEventHook`（`WindowOpenWatcher`経由）による実ウィンドウ検出、
  `AccessibleObjectFromWindow` 経由のOffice COM連携、`TrayTip` の実表示（実際にWord/Excel/PowerPoint/
  Visioがインストールされた環境が必要。手動確認手順は下記「OfficeFileWatcherの手動確認」を参照）
- `PdfFileWatcher` の `SetWinEventHook`（`WindowOpenWatcher`経由）による実ウィンドウ検出、WMI
  （`Win32_Process.CommandLine`）経由でのファイルパス取得、`TrayTip` の実表示（実際にAdobe Acrobat/
  Reader・SumatraPDF・Foxit Readerのいずれかがインストールされた環境が必要。手動確認手順は下記
  「PdfFileWatcherの手動確認」を参照）
- `RecentDocsWatcher` の実レジストリ（`RecentDocs`）ポーリング、`WScript.Shell`（COM）経由の`.lnk`
  ターゲットパス解決、「最近使った項目の記録」設定の実読み取り、`TrayTip` の実表示（実機のWindows設定・
  実際のファイルオープン操作が必要。手動確認手順は下記「RecentDocsWatcherの手動確認」を参照）

## OfficeFileWatcherの手動確認

`test_office_file_watcher.ahk` は対象プロセス判定・JSON整形など純粋なロジックのみを検証しており、
実際の検出動作（`SetWinEventHook`によるウィンドウ検出・COM経由のファイルパス取得・`TrayTip`表示）は
Word/Excel/PowerPoint/Visioがインストールされた環境で手動確認する。

1. `src/main.ahk` を起動する（トレイメニューの「Office監視」がチェック済みであること）。
2. Word/Excel/PowerPoint/Visioでファイルを開く。
3. 画面右下にTrayTipが表示され、本文が `{"type":...,"fileName":...,"path":...,...}` 形式の
   JSONになっていること、`path`に実際のファイルのフルパスが入っていることを確認する。
4. `nagame-ahk.log`（リポジトリ直下）にエラーが出ていないことを確認する
   （`AccessibleObjectFromWindow`が失敗した場合は`ERROR`ログとともに`pathResolved:false`の
   フォールバック表示になる）。
5. 同じウィンドウを最小化→復元しても再度TrayTipが表示されない（通知済みhwndとして重複除外される）
   ことを確認する。
6. ウィンドウを閉じたあと、トレイメニュー「Office監視」のON/OFF切り替えが正常に動作することを確認する。

## PdfFileWatcherの手動確認

`test_pdf_file_watcher.ahk` は`.pdf`パス抽出・対象プロセス判定など純粋なロジックのみを検証しており、
実際の検出動作（`SetWinEventHook`によるウィンドウ検出・WMI経由のファイルパス取得・`TrayTip`表示）は
Adobe Acrobat/Reader・SumatraPDF・Foxit Readerのいずれかがインストールされた環境で手動確認する。

1. `src/main.ahk` を起動する（トレイメニューの「PDF監視」がチェック済みであること）。
2. 対象のPDFリーダーで、エクスプローラー等からPDFファイルをダブルクリックして開く
   （新規プロセスとして起動するケース。既に起動中のリーダーで2つ目以降のファイルを開くケースは
   手順5で別途確認する）。
3. 画面右下にTrayTipが表示され、本文が `{"type":"PDF","fileName":...,"path":...,...}` 形式の
   JSONになっていること、`path`に実際のファイルのフルパスが入っていることを確認する。
4. `nagame-ahk.log`（リポジトリ直下）にエラーが出ていないことを確認する
   （WMIでのコマンドライン取得・パス抽出に失敗した場合は`ERROR`ログとともに`pathResolved:false`の
   フォールバック表示になる）。
5. 既に起動中の同じリーダーで2つ目以降のPDFを開いた場合、`docs/spec/pdf-file-watcher.md`に記載の既知の
   制約通り`pathResolved:false`のフォールバック表示になることを確認する。
6. ウィンドウを閉じたあと、トレイメニュー「PDF監視」のON/OFF切り替えが正常に動作することを確認する。
7. Officeのファイルを開いてもPDF監視側のTrayTipが誤って表示されない（逆も同様）ことを確認する。

## RecentDocsWatcherの手動確認

`test_recent_docs_watcher.ahk`はレジストリバイナリのパース・JSON整形など純粋なロジックのみを検証して
おり、実際の検出動作（レジストリポーリング・`.lnk`経由のパス解決・`TrayTip`表示）は実機で手動確認する。

1. `src/main.ahk`を起動する（トレイメニューの「最近使ったファイル通知」がチェック済みであること）。
2. `nagame-ahk.log`に`最近使ったファイル監視を開始しました`が出ており、`Windowsの「最近使った項目の
   記録」がOFF`という`WARN`が出ていないことを確認する（出ている場合はWindows設定を確認する。
   設定のON/OFF確認手順は`docs/spec/recent-docs-watcher.md`の該当節を参照）。
3. 適当なファイル（テキスト等）をエクスプローラーでダブルクリックして開く。
4. `Settings.RecentDocsPollIntervalMs`（既定2000ms）程度待ち、画面右下にTrayTipが表示され、
   本文が`{"fileName":...,"path":...,"pathResolved":...,"extension":...}`形式のJSONになっている
   ことを確認する。`path`にフルパスが入っていれば`pathResolved:true`、入っていなければ`false`。
5. **既知の制約（実機確認済み）**: ファイルを開くと、ファイルを開いたアプリによっては直後に
   *ファイルの親フォルダ自体*も「最近使った項目」として再登録されることがある（テキストエディタの
   File>Open初期フォルダ記憶など）。この場合、ポーリング時点でのMRUの先頭が「開いたファイル」ではなく
   「親フォルダ」になり、直前に同じフォルダ名で既に通知済みだと新規オープンとして検知されない
   （フォルダ名の変化が無いため）ことがある。これは`docs/spec/recent-docs-watcher.md`の
   未決定事項に追記済みの既知の制約であり、バグではない。気になる場合は普段使わないフォルダの
   新規ファイルで試すと現象が発生しにくい。
6. ウィンドウを閉じたあと、トレイメニュー「最近使ったファイル通知」のON/OFF切り替えが正常に動作する
   ことを確認する。

## 新しい機能を追加したとき

`/ahk-implement` で機能を実装した際は、可能な範囲でここにテストスクリプトを追加する。
- ロジックが単体で切り出せる場合（`lib/` 配下など）は `test_json.ahk` のようなAHKの単体テストにする。
- IPC・複数モジュールの結合確認が必要な場合は `test_external_command_server.ps1` のような
  PowerShellスクリプトで、実プロセスを起動してTCP/ファイル等の外部インターフェース越しに検証する。
- 実機の入力操作やGUI表示など自動化すると副作用が大きいものは、対象外として上の表に理由を記載し、
  手動確認の手順をコメントか設計ドキュメントに残す。
