#Requires AutoHotkey v2.0

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
}
