#Requires AutoHotkey v2.0

; トレイアイコン・右クリックメニューのセットアップ。
class TrayMenu {
    static Setup() {
        A_TrayMenu.Delete()
        A_TrayMenu.Add("操作状態表示", (*) => TrayMenu.ToggleActivityStatus())
        A_TrayMenu.Add("外部コマンド受付", (*) => TrayMenu.ToggleExternalCommandServer())
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

    ; 「外部コマンド受付」メニューのチェック状態・ツールチップをExternalCommandServer.Enabledに同期する
    static SyncExternalCommandCheck() {
        if ExternalCommandServer.Enabled {
            A_TrayMenu.Check("外部コマンド受付")
        } else {
            A_TrayMenu.Uncheck("外部コマンド受付")
        }
        TrayMenu._UpdateExternalCommandTip()
    }

    ; ExternalCommandServerの切り替えとメニューのチェック状態同期をまとめて行う
    static ToggleExternalCommandServer(*) {
        ExternalCommandServer.Toggle()
        TrayMenu.SyncExternalCommandCheck()
    }

    ; クライアントの接続/切断イベントからツールチップの接続状態表示を更新するために呼ばれる。
    ; メニュー項目のテキスト自体は開いている間に動的更新しづらいため、トレイアイコンの
    ; ツールチップ(A_IconTip)で接続状態を確認できるようにしている(設計ドキュメント参照)。
    static RefreshExternalCommandStatus() {
        TrayMenu._UpdateExternalCommandTip()
    }

    static _UpdateExternalCommandTip() {
        status := !ExternalCommandServer.Enabled ? "停止中" : (ExternalCommandServer.IsConnected() ? "接続中" : "待受中")
        A_IconTip := Settings.AppName " v" Settings.Version " / 外部コマンド: " status
    }
}
