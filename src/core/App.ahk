#Requires AutoHotkey v2.0

; アプリのライフサイクル管理（起動処理の集約）。
class App {
    static Start() {
        TrayMenu.Setup()
        Hotkeys.Register()
        ActivityStatus.Start()
        TrayMenu.SyncActivityStatusCheck()

        ClipboardControl.StartWatching()
        if Settings.ExternalCommandAutoStart {
            ExternalCommandServer.Start()
        }
        TrayMenu.SyncExternalCommandCheck()

        if Settings.OfficeWatchAutoStart {
            OfficeFileWatcher.Start()
        }
        TrayMenu.SyncOfficeWatchCheck()

        if Settings.PdfWatchAutoStart {
            PdfFileWatcher.Start()
        }
        TrayMenu.SyncPdfWatchCheck()

        Logger.Info(Settings.AppName " を起動しました")
    }
}
