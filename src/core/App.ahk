#Requires AutoHotkey v2.0

; アプリのライフサイクル管理（起動処理の集約）。
class App {
    static Start() {
        TrayMenu.Setup()
        Hotkeys.Register()
        ActivityStatus.Start()
        TrayMenu.SyncActivityStatusCheck()
        Logger.Info(Settings.AppName " を起動しました")
    }
}
