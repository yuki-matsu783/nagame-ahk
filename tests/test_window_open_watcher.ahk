#Requires AutoHotkey v2.0
#SingleInstance Force

; 設計: docs/office-file-watcher.md(検出方法), docs/pdf-file-watcher.md
; lib/WindowOpenWatcher.ahk のうち、実ウィンドウ・SetWinEventHookを使わずに検証できる
; 対象プロセス判定ロジック・複数インスタンスの独立性の単体テスト。
; GUIを開かず、アサーション結果を標準出力してExitApp()する。
; 実行例: AutoHotkey64.exe tests\test_window_open_watcher.ahk
;
; 対象外(このテストではカバーしない。tests/README.md の「対象外」節も参照):
; - SetWinEventHookによる実ウィンドウ検出(Start()は呼ばない。Start/Stopの実挙動は
;   test_office_file_watcher.ahk / test_pdf_file_watcher.ahk 経由の手動確認を参照)
#Include ..\src\config\Settings.ahk
#Include ..\src\lib\Logger.ahk
#Include ..\src\lib\WindowOpenWatcher.ahk

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

; Start()を呼ばなければ実フックは張られないため、コンストラクタ・内部ロジックのみを検証できる
watcher := WindowOpenWatcher(Array("WINWORD.EXE", "EXCEL.EXE"), (*) => 0)

Assert(watcher.Enabled, false, "生成直後はEnabled=false")
Assert(watcher._IsTargetProcess("WINWORD.EXE"), true, "対象プロセス名は一致")
Assert(watcher._IsTargetProcess("winword.exe"), true, "大文字小文字を区別せず一致(プロジェクトの既存比較方針と同じ)")
Assert(watcher._IsTargetProcess("notepad.exe"), false, "対象外プロセスは一致しない")
Assert(watcher._IsTargetProcess(""), false, "空文字は一致しない")
Assert(watcher._TargetProcessNamesText(), "WINWORD.EXE, EXCEL.EXE", "対象プロセス名一覧のテキスト化(ログ出力用)")

; 複数インスタンスが独立した状態を持つこと(Office監視・PDF監視を同時に動かす前提の確認)
watcherB := WindowOpenWatcher(Array("AcroRd32.exe"), (*) => 0)
Assert(watcher._IsTargetProcess("AcroRd32.exe"), false, "あるインスタンスの対象プロセス名は他のインスタンスに混ざらない")
Assert(watcherB._IsTargetProcess("AcroRd32.exe"), true, "別インスタンス自身の対象プロセス名は正しく判定される")
Assert(watcherB._IsTargetProcess("WINWORD.EXE"), false, "別インスタンスは元のインスタンスの対象プロセス名を持たない")

; 通知済みhwndの重複排除(実ウィンドウ無しでMapを直接操作して検証)
watcher._notifiedHwnds[12345] := true
Assert(watcher._notifiedHwnds.Has(12345), true, "通知済みhwndとして記録される")
watcher._notifiedHwnds.Delete(12345)
Assert(watcher._notifiedHwnds.Has(12345), false, "削除後は記録が残らない")

FileAppend("passed=" passed " failures=" failures "`n", "*")
ExitApp(failures = 0 ? 0 : 1)
