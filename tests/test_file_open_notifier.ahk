#Requires AutoHotkey v2.0
#SingleInstance Force

; 設計: docs/spec/office-file-watcher.md(TrayTip表示内容), docs/spec/pdf-file-watcher.md
; lib/FileOpenNotifier.ahk のうち、TrayTipの実表示を使わずに検証できるJSON整形ロジックの単体テスト。
; GUIを開かず、アサーション結果を標準出力してExitApp()する。
; 実行例: AutoHotkey64.exe tests\test_file_open_notifier.ahk
;
; 対象外: TrayTipの実表示(FileOpenNotifier.Show)。手動確認は tests/README.md の
; 「OfficeFileWatcherの手動確認」「PdfFileWatcherの手動確認」を参照。
#Include ..\src\config\Settings.ahk
#Include ..\src\lib\Logger.ahk
#Include ..\src\lib\Json.ahk
#Include ..\src\lib\FileOpenNotifier.ahk

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

; ---- BuildJson: パス取得成功時(Officeを例に) ----
infoResolved := Map(
    "type", "Word",
    "fileName", "議事録.docx",
    "path", "C:\Users\taniyama\Documents\議事録.docx",
    "pathResolved", true,
    "windowTitle", "議事録.docx - Word",
    "process", Map("name", "WINWORD.EXE", "pid", 12345, "path", "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE")
)
jsonResolved := FileOpenNotifier.BuildJson(infoResolved)
parsedResolved := Json.Parse(jsonResolved)
Assert(parsedResolved["type"], "Word", "JSON: type")
Assert(parsedResolved["fileName"], "議事録.docx", "JSON: fileName")
Assert(parsedResolved["path"], "C:\Users\taniyama\Documents\議事録.docx", "JSON: path")
Assert(parsedResolved["pathResolved"], 1, "JSON: pathResolved(true)はJSONのtrue(パース後は1)")
Assert(parsedResolved["process"]["name"], "WINWORD.EXE", "JSON: process.name")
Assert(parsedResolved["process"]["pid"], 12345, "JSON: process.pid")
Assert(Type(parsedResolved["process"]["pid"]), "Integer", "JSON: process.pidは数値としてエンコードされる")
Assert(parsedResolved["process"]["path"], "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE", "JSON: process.path")

; ---- BuildJson: パス取得失敗時(フォールバック) ----
infoFallback := Map(
    "type", "Excel",
    "fileName", "",
    "path", "",
    "pathResolved", false,
    "windowTitle", "予算表.xlsx - Excel",
    "process", Map("name", "EXCEL.EXE", "pid", 999, "path", "C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE")
)
jsonFallback := FileOpenNotifier.BuildJson(infoFallback)
parsedFallback := Json.Parse(jsonFallback)
Assert(parsedFallback["path"], "", "JSON: パス未取得時はpathが空文字")
Assert(parsedFallback["pathResolved"], 0, "JSON: パス未取得時はpathResolvedがfalse(パース後は0)")
Assert(parsedFallback["windowTitle"], "予算表.xlsx - Excel", "JSON: フォールバック時はwindowTitleで代替情報を確認できる")

; ---- BuildJson: PDF用(typeが常に"PDF"固定になるケース)も同じ形で扱えること ----
infoPdf := Map(
    "type", "PDF",
    "fileName", "仕様書.pdf",
    "path", "C:\Users\taniyama\Documents\仕様書.pdf",
    "pathResolved", true,
    "windowTitle", "仕様書.pdf - Adobe Acrobat Reader",
    "process", Map("name", "AcroRd32.exe", "pid", 23456, "path", "C:\Program Files (x86)\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe")
)
jsonPdf := FileOpenNotifier.BuildJson(infoPdf)
parsedPdf := Json.Parse(jsonPdf)
Assert(parsedPdf["type"], "PDF", "JSON: PDFのtypeは固定値")
Assert(parsedPdf["process"]["name"], "AcroRd32.exe", "JSON: PDFのprocess.name")

FileAppend("passed=" passed " failures=" failures "`n", "*")
ExitApp(failures = 0 ? 0 : 1)
