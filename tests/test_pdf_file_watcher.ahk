#Requires AutoHotkey v2.0
#SingleInstance Force

; 設計: docs/spec/pdf-file-watcher.md
; features/PdfFileWatcher.ahk のうち、実ウィンドウ・WMI・SetWinEventHookを使わずに検証できる
; 純粋なロジック(コマンドラインからの.pdfパス抽出/ファイル名抽出/WindowOpenWatcherへの委譲設定)の
; 単体テスト。GUIを開かず、アサーション結果を標準出力してExitApp()する。
; 実行例: AutoHotkey64.exe tests\test_pdf_file_watcher.ahk
;
; 対象プロセス判定・通知済みhwnd重複排除はlib/WindowOpenWatcher.ahkに、
; JSON整形はlib/FileOpenNotifier.ahkに切り出したため、それぞれ
; tests/test_window_open_watcher.ahk・tests/test_file_open_notifier.ahk で検証する。
;
; 対象外(このテストではカバーしない。tests/README.md の「対象外」節も参照):
; - SetWinEventHookによる実ウィンドウ検出
; - WMI(Win32_Process)経由での実際のコマンドライン取得(実際のPDFリーダーが必要)
; - TrayTipの実表示
#Include ..\src\config\Settings.ahk
#Include ..\src\lib\Logger.ahk
#Include ..\src\lib\Json.ahk
#Include ..\src\lib\WindowOpenWatcher.ahk
#Include ..\src\lib\FileOpenNotifier.ahk
#Include ..\src\features\PdfFileWatcher.ahk

failures := 0
passed := 0

Assert(actual, expected, label) {
    global failures, passed
    if actual == expected {
        passed++
    } else {
        failures++
        FileAppend("FAIL: " label " expected=[" expected "] actual=[" actual "]`n", "*")
    }
}

; ---- WindowOpenWatcherへの委譲設定 ----
Assert(Type(PdfFileWatcher._watcher), "WindowOpenWatcher", "PdfFileWatcherはWindowOpenWatcherのインスタンスを保持する")
Assert(PdfFileWatcher.Enabled, false, "生成直後はEnabled=false(Start()を呼ぶまで)")
Assert(PdfFileWatcher._watcher._IsTargetProcess("AcroRd32.exe"), true, "監視対象にAdobe Acrobat Readerが含まれる")
Assert(PdfFileWatcher._watcher._IsTargetProcess("Acrobat.exe"), true, "監視対象にAdobe Acrobatが含まれる")
Assert(PdfFileWatcher._watcher._IsTargetProcess("SumatraPDF.exe"), true, "監視対象にSumatraPDFが含まれる")
Assert(PdfFileWatcher._watcher._IsTargetProcess("FoxitPDFReader.exe"), true, "監視対象にFoxit Reader(新表記)が含まれる")
Assert(PdfFileWatcher._watcher._IsTargetProcess("FoxitReader.exe"), true, "監視対象にFoxit Reader(旧表記)が含まれる")
Assert(PdfFileWatcher._watcher._IsTargetProcess("WINWORD.EXE"), false, "監視対象にOfficeプロセスは含まれない(OfficeFileWatcher側の責務)")
Assert(PdfFileWatcher._watcher._IsTargetProcess("msedge.exe"), false, "ブラウザ内蔵ビューアは監視対象外")

; ---- _ExtractPdfPath: コマンドライン文字列 -> .pdfパスの抽出 ----
Assert(
    PdfFileWatcher._ExtractPdfPath('"C:\Program Files (x86)\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe" "C:\Users\taniyama\Documents\仕様書.pdf"'),
    "C:\Users\taniyama\Documents\仕様書.pdf",
    "引用符付きの.pdfパスを抽出できる")
Assert(
    PdfFileWatcher._ExtractPdfPath('"C:\Program Files\SumatraPDF\SumatraPDF.exe" "C:\Users\taniyama\My Documents\report v2.pdf"'),
    "C:\Users\taniyama\My Documents\report v2.pdf",
    "パスに空白を含む場合も引用符内を正しく抽出できる")
Assert(
    PdfFileWatcher._ExtractPdfPath("C:\Program Files\SumatraPDF\SumatraPDF.exe C:\Users\taniyama\Documents\report.pdf"),
    "C:\Users\taniyama\Documents\report.pdf",
    "引用符が無い場合は末尾トークンが.pdfならそれを使う")
Assert(
    PdfFileWatcher._ExtractPdfPath('"C:\Users\taniyama\Documents\FILE.PDF"'),
    "C:\Users\taniyama\Documents\FILE.PDF",
    "拡張子の大文字小文字を区別せず抽出できる")
Assert(
    PdfFileWatcher._ExtractPdfPath('"C:\Windows\System32\notepad.exe"'),
    "",
    ".pdfが含まれないコマンドラインは空文字を返す")
Assert(
    PdfFileWatcher._ExtractPdfPath(""),
    "",
    "空文字のコマンドラインは空文字を返す")

; ---- _ExtractFileName: フルパス -> ファイル名 ----
Assert(PdfFileWatcher._ExtractFileName("C:\Users\taniyama\Documents\仕様書.pdf"), "仕様書.pdf", "フルパスからファイル名を抽出")
Assert(PdfFileWatcher._ExtractFileName("\\server\share\report.pdf"), "report.pdf", "UNCパスからもファイル名を抽出")

FileAppend("passed=" passed " failures=" failures "`n", "*")
ExitApp(failures = 0 ? 0 : 1)
