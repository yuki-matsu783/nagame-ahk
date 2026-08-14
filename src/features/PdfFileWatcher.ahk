#Requires AutoHotkey v2.0

; 設計: docs/pdf-file-watcher.md
; デスクトップ用PDFリーダー(Adobe Acrobat/Reader, SumatraPDF, Foxit Reader)でファイルが
; 開かれたことを検知し、ファイル情報・プロセス情報をJSON化してTrayTipに表示する機能。
; ウィンドウ検出(SetWinEventHook)はlib/WindowOpenWatcher.ahk、JSON整形・TrayTip表示は
; lib/FileOpenNotifier.ahkに委譲し、ここではPDF固有のファイルパス解決(WMI経由)のみを担当する。
class PdfFileWatcher {
    static Enabled := false
    ; ウィンドウ検出はWindowOpenWatcher(lib)に委譲する。監視対象プロセス名(Settings.PdfProcessNames)と
    ; 検出時コールバックを渡してインスタンス化し、Start/Stop/Toggleはそのまま委譲する。
    static _watcher := WindowOpenWatcher(
        Settings.PdfProcessNames,
        (hwnd, processName) => PdfFileWatcher._OnDetected(hwnd, processName))

    ; PDF監視を開始する
    static Start() {
        PdfFileWatcher._watcher.Start()
        PdfFileWatcher.Enabled := PdfFileWatcher._watcher.Enabled
    }

    ; PDF監視を停止する
    static Stop() {
        PdfFileWatcher._watcher.Stop()
        PdfFileWatcher.Enabled := PdfFileWatcher._watcher.Enabled
    }

    ; 監視のON/OFFを切り替える
    static Toggle() {
        PdfFileWatcher._watcher.Toggle()
        PdfFileWatcher.Enabled := PdfFileWatcher._watcher.Enabled
    }

    ; WindowOpenWatcherが対象ウィンドウを検出した際に呼ばれるコールバック。
    ; ファイル情報を集めてJSON化し、TrayTipに表示する。
    static _OnDetected(hwnd, processName) {
        info := PdfFileWatcher._CollectFileInfo(hwnd, processName)
        json := FileOpenNotifier.BuildJson(info)
        FileOpenNotifier.Show("PDFファイルが開かれました", json, Settings.PdfWatchTrayTipDurationMs)
    }

    ; hwndからファイル情報・プロセス情報を集めてMapにまとめる(表示用JSONの元データ)。
    ; 個々の取得は互いに独立してtry/catchするため、一部の取得に失敗しても他の情報は表示できる。
    static _CollectFileInfo(hwnd, processName) {
        windowTitle := ""
        try {
            windowTitle := WinGetTitle(hwnd)
        } catch as e {
            Logger.Debug("WinGetTitleに失敗しました hwnd=" hwnd ": " e.Message)
        }

        pid := 0
        processPath := ""
        try {
            pid := WinGetPID(hwnd)
            processPath := WinGetProcessPath(hwnd)
        } catch as e {
            Logger.Error("プロセス情報の取得に失敗しました: " e.Message)
            Logger.Debug("hwnd=" hwnd " process=" processName)
        }

        fullPath := ""
        try {
            fullPath := PdfFileWatcher._ResolveFullPath(pid)
        } catch as e {
            ; WMI経由でのコマンドライン取得はプロセスの状態(保護モード等)に依存し失敗しうるため、
            ; ここで捕捉してタイトルのみのフォールバック表示に切り替える(docs/pdf-file-watcher.md参照)
            Logger.Error("ファイルパスの取得に失敗しました: " e.Message)
            Logger.Debug("hwnd=" hwnd " process=" processName " pid=" pid " windowTitle=" windowTitle)
        }

        pathResolved := fullPath != ""
        return Map(
            ; リーダーの種類を問わず常に"PDF"固定。具体的なリーダーはprocess.nameで判別する
            "type", "PDF",
            "fileName", pathResolved ? PdfFileWatcher._ExtractFileName(fullPath) : "",
            "path", fullPath,
            "pathResolved", pathResolved,
            "windowTitle", windowTitle,
            "process", Map(
                "name", processName,
                "pid", pid,
                "path", processPath
            )
        )
    }

    ; プロセスの起動コマンドラインをWMI経由で取得し、そこから.pdfパスを抽出する
    ; (docs/pdf-file-watcher.mdの「ファイル情報の取得」参照)。
    ; 既に起動済みのプロセスに2つ目以降のファイルを開いた場合はコマンドラインが最初のファイルの
    ; ままになるため取得できない(既知の制約)。抽出できても実在しなければ空文字列を返す。
    static _ResolveFullPath(pid) {
        if pid = 0 {
            return ""
        }

        cmdLine := PdfFileWatcher._GetProcessCommandLine(pid)
        if cmdLine = "" {
            return ""
        }

        path := PdfFileWatcher._ExtractPdfPath(cmdLine)
        if path != "" && FileExist(path) {
            return path
        }
        return ""
    }

    ; WMI(Win32_Process)経由で指定PIDの起動コマンドラインを取得する
    static _GetProcessCommandLine(pid) {
        wmi := ComObjGet("winmgmts:\\.\root\cimv2")
        results := wmi.ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" pid)
        for proc in results {
            return proc.CommandLine
        }
        return ""
    }

    ; コマンドライン文字列から.pdfファイルのパスを抽出する簡易パーサ。
    ; 1. まず引用符 "..." で囲まれた.pdfパスを優先して探す(パスに空白を含む場合の引用符付き引数に対応)。
    ; 2. 見つからなければ、空白区切りの最後のトークンが.pdfで終わっていればそれを使う。
    ; どちらも見つからなければ空文字列を返す(呼び出し元がフォールバック表示に切り替える)。
    static _ExtractPdfPath(cmdLine) {
        if RegExMatch(cmdLine, 'i)"([^"]+\.pdf)"', &m) {
            return m[1]
        }

        tokens := StrSplit(Trim(cmdLine), " ")
        if tokens.Length > 0 {
            lastToken := tokens[tokens.Length]
            if RegExMatch(lastToken, "i)\.pdf$") {
                return lastToken
            }
        }
        return ""
    }

    ; フルパスからファイル名部分だけを取り出す
    static _ExtractFileName(fullPath) {
        SplitPath(fullPath, &fileName)
        return fileName
    }
}
