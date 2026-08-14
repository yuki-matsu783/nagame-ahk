#Requires AutoHotkey v2.0

; 設計: docs/spec/external-command-server.md(DescribeWindowのみ)
; ウィンドウ操作系の汎用処理。features/ 間で使い回す部品を置く。
class WindowUtils {
    ; 指定タイトルのウィンドウがあればアクティブ化し、無ければ起動する
    static ActivateOrRun(winTitle, runPath) {
        if WinExist(winTitle) {
            WinActivate
        } else {
            Run(runPath)
        }
    }

    ; 指定ウィンドウの情報をMapにまとめて返す。
    ; features/WindowControl.ahk の ListWindows / GetActiveWindow から共通で利用する。
    static DescribeWindow(hwnd) {
        WinGetPos(&x, &y, &w, &h, hwnd)
        minMax := WinGetMinMax(hwnd)
        return Map(
            "hwnd", hwnd,
            "title", WinGetTitle(hwnd),
            "processName", WinGetProcessName(hwnd),
            "class", WinGetClass(hwnd),
            "x", x,
            "y", y,
            "width", w,
            "height", h,
            "minimized", Json.Bool(minMax = -1),
            "maximized", Json.Bool(minMax = 1)
        )
    }
}
