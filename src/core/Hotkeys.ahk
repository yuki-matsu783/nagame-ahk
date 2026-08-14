#Requires AutoHotkey v2.0

; ホットキー登録を集約するクラス。
; 実際の処理は features/ 配下の各モジュールに委譲し、ここでは登録のみ行う。
class Hotkeys {
    static Register() {
        ; 例: Ctrl+Alt+N でサンプル処理を実行
        HotKey("^!n", (*) => Logger.Info("サンプルホットキーが押されました"))

        ; Ctrl+Alt+A で操作状態ツールチップの表示をON/OFF切り替え
        HotKey("^!a", (*) => TrayMenu.ToggleActivityStatus())
    }
}
