#Requires AutoHotkey v2.0
#SingleInstance Force

; 設計: docs/spec/office-file-watcher.md
; features/OfficeFileWatcher.ahk のうち、実ウィンドウ・COM・SetWinEventHookを使わずに検証できる
; 純粋なロジック(種類名マッピング/ファイル名抽出/WindowOpenWatcherへの委譲設定)の単体テスト。
; GUIを開かず、アサーション結果を標準出力してExitApp()する。
; 実行例: AutoHotkey64.exe tests\test_office_file_watcher.ahk
;
; 対象プロセス判定・通知済みhwnd重複排除はlib/WindowOpenWatcher.ahkに、
; JSON整形はlib/FileOpenNotifier.ahkに切り出したため、それぞれ
; tests/test_window_open_watcher.ahk・tests/test_file_open_notifier.ahk で検証する。
;
; 対象外(このテストではカバーしない。tests/README.md の「対象外」節も参照):
; - SetWinEventHookによる実ウィンドウ検出
; - AccessibleObjectFromWindow経由でのOffice COM連携(実際のWord/Excel/PowerPoint/Visioが必要)
; - TrayTipの実表示
#Include ..\src\config\Settings.ahk
#Include ..\src\lib\Logger.ahk
#Include ..\src\lib\Json.ahk
#Include ..\src\lib\WindowOpenWatcher.ahk
#Include ..\src\lib\FileOpenNotifier.ahk
#Include ..\src\features\OfficeFileWatcher.ahk
#Include lib\Assert.ahk

failures := 0
passed := 0

; ---- WindowOpenWatcherへの委譲設定 ----
Assert(Type(OfficeFileWatcher._watcher), "WindowOpenWatcher", "OfficeFileWatcherはWindowOpenWatcherのインスタンスを保持する")
Assert(OfficeFileWatcher.Enabled, false, "生成直後はEnabled=false(Start()を呼ぶまで)")
Assert(OfficeFileWatcher._watcher._IsTargetProcess("WINWORD.EXE"), true, "監視対象にWordが含まれる")
Assert(OfficeFileWatcher._watcher._IsTargetProcess("EXCEL.EXE"), true, "監視対象にExcelが含まれる")
Assert(OfficeFileWatcher._watcher._IsTargetProcess("POWERPNT.EXE"), true, "監視対象にPowerPointが含まれる")
Assert(OfficeFileWatcher._watcher._IsTargetProcess("VISIO.EXE"), true, "監視対象にVisioが含まれる")
Assert(OfficeFileWatcher._watcher._IsTargetProcess("AcroRd32.exe"), false, "監視対象にPDFリーダーは含まれない(PdfFileWatcher側の責務)")

; ---- TypeNames: プロセス名 -> 表示用の種類名 ----
Assert(OfficeFileWatcher.TypeNames.Get("WINWORD.EXE", ""), "Word", "WINWORD.EXEはWordと表示")
Assert(OfficeFileWatcher.TypeNames.Get("EXCEL.EXE", ""), "Excel", "EXCEL.EXEはExcelと表示")
Assert(OfficeFileWatcher.TypeNames.Get("POWERPNT.EXE", ""), "PowerPoint", "POWERPNT.EXEはPowerPointと表示")
Assert(OfficeFileWatcher.TypeNames.Get("VISIO.EXE", ""), "Visio", "VISIO.EXEはVisioと表示")

; ---- _ExtractFileName: フルパス -> ファイル名 ----
Assert(OfficeFileWatcher._ExtractFileName("C:\Users\taniyama\Documents\議事録.docx"), "議事録.docx", "フルパスからファイル名を抽出")
Assert(OfficeFileWatcher._ExtractFileName("\\server\share\report.xlsx"), "report.xlsx", "UNCパスからもファイル名を抽出")

FileAppend("passed=" passed " failures=" failures "`n", "*")
ExitApp(failures = 0 ? 0 : 1)
