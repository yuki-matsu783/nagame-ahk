#Requires AutoHotkey v2.0

; 設計: docs/external-command-server.md
; 外部コマンドサーバーの通知・簡易UI系コマンドの実処理。
; ShowToast/ShowMessageBoxは同期(即時応答)、ShowInputDialog/ShowChoiceDialogは
; ユーザー操作待ちのため非同期(respondコールバックをダイアログのボタン押下時に呼ぶ)。
; 例外はcore/ExternalCommandServer.ahkの側で一括してエラー応答に変換される
; (詳細はcore/ExternalCommandServer.ahk冒頭のコメント参照。ただし非同期コマンドは
; ダイアログ表示後の処理がイベント任せになるため、ここでも最低限の検証は行う)。
class NotifyUI {
    static ShowToast(params) {
        title := params.Get("title", "")
        message := params["message"]
        durationMs := params.Get("durationMs", 3000)

        TrayTip(message, title)
        ; TrayTipはOSによって自動で消えないことがあるため、指定時間後に明示的に消す
        SetTimer(() => TrayTip(), -durationMs)
        return Map()
    }

    static ShowMessageBox(params) {
        title := params.Get("title", "")
        message := params["message"]
        ; MsgBoxはモーダルでスレッドをブロックする(docs/external-command-server.md の懸念点を参照)
        MsgBox(message, title)
        return Map()
    }

    ; 非同期コマンド。ダイアログを表示し、ユーザー操作後にrespondを呼び出す。
    static ShowInputDialog(params, respond) {
        title := params.Get("title", "")
        message := params.Get("message", "")
        defaultValue := params.Get("defaultValue", "")

        dialog := Gui("+AlwaysOnTop", title)
        dialog.AddText(, message)
        edit := dialog.AddEdit("w300", defaultValue)
        dialog.AddButton("Default w80", "OK").OnEvent("Click", (*) => NotifyUI._SubmitInputDialog(dialog, edit, respond))
        dialog.AddButton("x+10 w80", "キャンセル").OnEvent("Click", (*) => NotifyUI._CancelInputDialog(dialog, respond))
        dialog.OnEvent("Close", (*) => NotifyUI._CancelInputDialog(dialog, respond))
        dialog.OnEvent("Escape", (*) => NotifyUI._CancelInputDialog(dialog, respond))

        dialog.Show()
    }

    static _SubmitInputDialog(dialog, edit, respond) {
        value := edit.Text
        dialog.Destroy()
        respond(true, Map("value", value, "cancelled", Json.Bool(false)))
    }

    static _CancelInputDialog(dialog, respond) {
        dialog.Destroy()
        respond(true, Map("value", "", "cancelled", Json.Bool(true)))
    }

    ; 非同期コマンド。選択肢一覧から1つ選ばせ、ユーザー操作後にrespondを呼び出す。
    static ShowChoiceDialog(params, respond) {
        title := params.Get("title", "")
        message := params.Get("message", "")
        choices := params.Get("choices", Array())

        if choices.Length = 0 {
            respond(false, "choicesが空です")
            return
        }

        dialog := Gui("+AlwaysOnTop", title)
        dialog.AddText(, message)
        listBox := dialog.AddListBox("w300 r" Min(choices.Length, 8), choices)
        listBox.Choose(1)
        dialog.AddButton("Default w80", "OK").OnEvent("Click", (*) => NotifyUI._SubmitChoiceDialog(dialog, listBox, choices, respond))
        dialog.AddButton("x+10 w80", "キャンセル").OnEvent("Click", (*) => NotifyUI._CancelChoiceDialog(dialog, respond))
        dialog.OnEvent("Close", (*) => NotifyUI._CancelChoiceDialog(dialog, respond))
        dialog.OnEvent("Escape", (*) => NotifyUI._CancelChoiceDialog(dialog, respond))

        dialog.Show()
    }

    static _SubmitChoiceDialog(dialog, listBox, choices, respond) {
        selected := choices[listBox.Value]
        dialog.Destroy()
        respond(true, Map("selected", selected, "cancelled", Json.Bool(false)))
    }

    static _CancelChoiceDialog(dialog, respond) {
        dialog.Destroy()
        respond(true, Map("selected", "", "cancelled", Json.Bool(true)))
    }
}
