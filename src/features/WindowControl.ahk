#Requires AutoHotkey v2.0

; 設計: docs/external-command-server.md
; 外部コマンドサーバーのウィンドウ操作系コマンド(ActivateWindow等)の実処理。
; winTitleパラメータはAHKのWinTitle構文(ahk_exe notepad.exe 等)をそのまま受け取る。
; 例外はcore/ExternalCommandServer.ahkの側で一括してエラー応答に変換されるため、
; ここでは個別のtry/catchは行わない(ファイル冒頭のExternalCommandServer.ahkのコメント参照)。
class WindowControl {
    static ActivateWindow(params) {
        WinActivate(params["winTitle"])
        return Map()
    }

    static MinimizeWindow(params) {
        WinMinimize(params["winTitle"])
        return Map()
    }

    static MaximizeWindow(params) {
        WinMaximize(params["winTitle"])
        return Map()
    }

    static RestoreWindow(params) {
        WinRestore(params["winTitle"])
        return Map()
    }

    static CloseWindow(params) {
        WinClose(params["winTitle"])
        return Map()
    }

    static MoveWindow(params) {
        winTitle := params["winTitle"]
        WinGetPos(&curX, &curY, &curW, &curH, winTitle)
        x := params.Get("x", curX)
        y := params.Get("y", curY)
        w := params.Get("width", curW)
        h := params.Get("height", curH)
        WinMove(x, y, w, h, winTitle)
        return Map()
    }

    ; 複数ウィンドウをレイアウトに沿って整列させる
    static ArrangeWindows(params) {
        winTitles := params.Get("winTitles", Array())
        layout := params.Get("layout", "left-right")
        monitor := params.Get("monitor", 0)

        if winTitles.Length = 0 {
            throw Error("winTitlesが空です")
        }

        MonitorGetWorkArea(monitor > 0 ? monitor : MonitorGetPrimary(), &left, &top, &right, &bottom)
        areaW := right - left
        areaH := bottom - top
        count := winTitles.Length

        switch layout {
            case "left-right":
                cellW := areaW // count
                for i, winTitle in winTitles {
                    WinMove(left + cellW * (i - 1), top, cellW, areaH, winTitle)
                }
            case "top-bottom":
                cellH := areaH // count
                for i, winTitle in winTitles {
                    WinMove(left, top + cellH * (i - 1), areaW, cellH, winTitle)
                }
            case "grid":
                cols := Ceil(Sqrt(count))
                rows := Ceil(count / cols)
                cellW := areaW // cols
                cellH := areaH // rows
                for i, winTitle in winTitles {
                    col := Mod(i - 1, cols)
                    row := (i - 1) // cols
                    WinMove(left + cellW * col, top + cellH * row, cellW, cellH, winTitle)
                }
            default:
                throw Error("不明なlayoutです: " layout)
        }

        return Map()
    }

    static SetAlwaysOnTop(params) {
        winTitle := params["winTitle"]
        enabled := params.Get("enabled", false)
        WinSetAlwaysOnTop(enabled ? 1 : 0, winTitle)
        return Map()
    }

    static SetTransparency(params) {
        winTitle := params["winTitle"]
        alpha := params["alpha"]
        WinSetTransparent(alpha, winTitle)
        return Map()
    }

    static ListWindows(params) {
        windows := Array()
        for hwnd in WinGetList() {
            try {
                windows.Push(WindowUtils.DescribeWindow(hwnd))
            } catch as e {
                ; 列挙中に閉じられた等、個別ウィンドウの情報取得に失敗しても全体は止めない
                Logger.Debug("ウィンドウ情報の取得に失敗したためスキップしました hwnd=" hwnd ": " e.Message)
            }
        }
        return Map("windows", windows)
    }

    static GetActiveWindow(params) {
        hwnd := WinGetID("A")
        if !hwnd {
            throw Error("アクティブウィンドウが見つかりません")
        }
        return WindowUtils.DescribeWindow(hwnd)
    }
}
