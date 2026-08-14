#Requires AutoHotkey v2.0

; 設計: docs/spec/office-file-watcher.md
; Word/Excel/PowerPoint/Visioでファイルが開かれたことを検知し、ファイル情報・プロセス情報を
; JSON化してTrayTipに表示する機能。ウィンドウ検出(SetWinEventHook)はlib/WindowOpenWatcher.ahk、
; JSON整形・TrayTip表示はlib/FileOpenNotifier.ahkに委譲し、ここではOffice/Visio固有の
; ファイルパス解決(AccessibleObjectFromWindow経由)のみを担当する。
class OfficeFileWatcher {
    ; ---- oleacc(AccessibleObjectFromWindow)関連の定数 ----
    ; アプリ設定ではなくWindows APIのプロトコル定数のため、Settingsではなくここに定義する
    ; (src/lib/TcpServer.ahkのWinsock定数と同じ方針)。
    static OBJID_NATIVEOM := -16
    static IID_IDispatch := "{00020400-0000-0000-C000-000000000046}"

    ; プロセス名 -> 表示用の種類名
    static TypeNames := Map(
        "WINWORD.EXE", "Word",
        "EXCEL.EXE", "Excel",
        "POWERPNT.EXE", "PowerPoint",
        "VISIO.EXE", "Visio"
    )

    static Enabled := false
    ; ウィンドウ検出はWindowOpenWatcher(lib)に委譲する。監視対象プロセス名(Settings.OfficeProcessNames)と
    ; 検出時コールバックを渡してインスタンス化し、Start/Stop/Toggleはそのまま委譲する。
    static _watcher := WindowOpenWatcher(
        Settings.OfficeProcessNames,
        (hwnd, processName) => OfficeFileWatcher._OnDetected(hwnd, processName))

    ; Office監視を開始する
    static Start() {
        OfficeFileWatcher._watcher.Start()
        OfficeFileWatcher.Enabled := OfficeFileWatcher._watcher.Enabled
    }

    ; Office監視を停止する
    static Stop() {
        OfficeFileWatcher._watcher.Stop()
        OfficeFileWatcher.Enabled := OfficeFileWatcher._watcher.Enabled
    }

    ; 監視のON/OFFを切り替える
    static Toggle() {
        OfficeFileWatcher._watcher.Toggle()
        OfficeFileWatcher.Enabled := OfficeFileWatcher._watcher.Enabled
    }

    ; WindowOpenWatcherが対象ウィンドウを検出した際に呼ばれるコールバック。
    ; ファイル情報を集めてJSON化し、TrayTipに表示する。
    static _OnDetected(hwnd, processName) {
        info := OfficeFileWatcher._CollectFileInfo(hwnd, processName)
        json := FileOpenNotifier.BuildJson(info)
        FileOpenNotifier.Show("Officeファイルが開かれました", json, Settings.OfficeWatchTrayTipDurationMs)
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

        fullPath := ""
        try {
            fullPath := OfficeFileWatcher._ResolveFullPath(hwnd, processName)
        } catch as e {
            ; AccessibleObjectFromWindow/COM経由の取得はOfficeのバージョンや状態に依存し
            ; 失敗しうるため、ここで捕捉してタイトルのみのフォールバック表示に切り替える
            Logger.Error("ファイルパスの取得に失敗しました: " e.Message)
            Logger.Debug("hwnd=" hwnd " process=" processName " windowTitle=" windowTitle)
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

        pathResolved := fullPath != ""
        return Map(
            "type", OfficeFileWatcher.TypeNames.Get(processName, processName),
            "fileName", pathResolved ? OfficeFileWatcher._ExtractFileName(fullPath) : "",
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

    ; AccessibleObjectFromWindow(OBJID_NATIVEOM)経由でhwndから直接オートメーションオブジェクトを
    ; 取得し、アプリ種別ごとにドキュメントのFullNameを取得する(docs/spec/office-file-watcher.md参照)。
    ; Documents/Windowsコレクションを列挙して.Hwndが一致するものを探す方式は、複数ウィンドウ・
    ; 複数インスタンスがある場合に対応を誤りうるため採用しない。
    static _ResolveFullPath(hwnd, processName) {
        disp := OfficeFileWatcher._GetNativeOm(hwnd)
        if !disp {
            return ""
        }

        switch processName {
            case "WINWORD.EXE", "VISIO.EXE":
                ; Word/Visioともに、取得できるのはWindow相当のオブジェクトで
                ; .Documentからファイルを辿れる
                return disp.Document.FullName
            case "EXCEL.EXE":
                ; ExcelのWindow.ParentはWorkbook
                return disp.Parent.FullName
            case "POWERPNT.EXE":
                return disp.Presentation.FullName
            default:
                return ""
        }
    }

    ; oleacc!AccessibleObjectFromWindowでhwndに紐づくIDispatchを取得し、ComObjectとして返す。
    ; 取得できなければ0を返す(呼び出し元でフォールバック処理する)。
    static _GetNativeOm(hwnd) {
        iid := Buffer(16, 0)
        if DllCall("ole32\IIDFromString", "WStr", OfficeFileWatcher.IID_IDispatch, "Ptr", iid) != 0 {
            throw Error("IIDFromStringに失敗しました")
        }

        pDisp := 0
        hr := DllCall(
            "oleacc\AccessibleObjectFromWindow",
            "Ptr", hwnd,
            "UInt", OfficeFileWatcher.OBJID_NATIVEOM & 0xFFFFFFFF,
            "Ptr", iid,
            "Ptr*", &pDisp,
            "Int")
        if hr != 0 || pDisp = 0 {
            return 0
        }
        return ComValue(9, pDisp) ; 9 = VT_DISPATCH
    }

    ; フルパスからファイル名部分だけを取り出す
    static _ExtractFileName(fullPath) {
        SplitPath(fullPath, &fileName)
        return fileName
    }
}
