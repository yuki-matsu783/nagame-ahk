#Requires AutoHotkey v2.0

; トレイアイコン・右クリックメニューのセットアップ。
class TrayMenu {
    static Setup() {
        A_TrayMenu.Delete()
        A_TrayMenu.Add("操作状態表示", (*) => TrayMenu.ToggleActivityStatus())
        A_TrayMenu.Add()
        A_TrayMenu.Add("再読み込み", (*) => Reload())
        A_TrayMenu.Add("終了", (*) => ExitApp())
        A_TrayMenu.Default := "再読み込み"
        A_IconTip := Settings.AppName " v" Settings.Version
    }

    ; 「操作状態表示」メニューのチェック状態を ActivityStatus.Enabled に同期する
    static SyncActivityStatusCheck() {
        if ActivityStatus.Enabled {
            A_TrayMenu.Check("操作状態表示")
        } else {
            A_TrayMenu.Uncheck("操作状態表示")
        }
    }

    ; ActivityStatus の切り替えとメニューのチェック状態同期をまとめて行う
    ; （トレイメニューのクリックからも Hotkeys からも、このメソッド経由で統一する）
    static ToggleActivityStatus(*) {
        ActivityStatus.Toggle()
        TrayMenu.SyncActivityStatusCheck()
    }
}
