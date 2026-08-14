#Requires AutoHotkey v2.0

; 設計: docs/external-command-server.md
; TcpServer(lib)が受信した1行(JSON文字列)を解析し、コマンドをfeatures/配下へディスパッチして
; 結果をJSONで返す。core/Hotkeys.ahk と対になる「外部トリガーの集約窓口」の位置づけ。
;
; エラーハンドリングの方針:
; 同期コマンドは _syncDispatch のハンドラを try/catch で包んで一括して例外→エラー応答に変換し、
; Logger.Error に加えてリクエストのparamsをLogger.Debugへ残す。各ハンドラ内で個別にtry/catchを
; 書く代わりに、ここで一元的に処理することで実装ファイル間の重複を避けている。
; 非同期コマンド(ShowInputDialog等、ユーザー操作待ちで応答が遅れるもの)はハンドラ自身が
; respond(ok, payload) を呼ぶ責務を持つ。
class ExternalCommandServer {
    static Enabled := false
    static _authenticated := false

    ; コマンド名 → 同期ハンドラ(params) => resultMap。例外を投げるとエラー応答に変換される。
    static _syncDispatch := Map(
        "ActivateWindow", (params) => WindowControl.ActivateWindow(params),
        "MinimizeWindow", (params) => WindowControl.MinimizeWindow(params),
        "MaximizeWindow", (params) => WindowControl.MaximizeWindow(params),
        "RestoreWindow", (params) => WindowControl.RestoreWindow(params),
        "CloseWindow", (params) => WindowControl.CloseWindow(params),
        "MoveWindow", (params) => WindowControl.MoveWindow(params),
        "ArrangeWindows", (params) => WindowControl.ArrangeWindows(params),
        "SetAlwaysOnTop", (params) => WindowControl.SetAlwaysOnTop(params),
        "SetTransparency", (params) => WindowControl.SetTransparency(params),
        "ListWindows", (params) => WindowControl.ListWindows(params),
        "GetActiveWindow", (params) => WindowControl.GetActiveWindow(params),

        "SendKeys", (params) => InputControl.SendKeys(params),
        "SendText", (params) => InputControl.SendText(params),
        "MouseClick", (params) => InputControl.MouseClick(params),
        "MouseDrag", (params) => InputControl.MouseDrag(params),
        "MouseScroll", (params) => InputControl.MouseScroll(params),
        "PlayMacro", (params) => InputControl.PlayMacro(params),

        "GetClipboard", (params) => ClipboardControl.GetClipboard(params),
        "SetClipboard", (params) => ClipboardControl.SetClipboard(params),
        "GetClipboardHistory", (params) => ClipboardControl.GetClipboardHistory(params),
        "ClearClipboardHistory", (params) => ClipboardControl.ClearClipboardHistory(params),
        "PasteFormatted", (params) => ClipboardControl.PasteFormatted(params),

        "ShowToast", (params) => NotifyUI.ShowToast(params),
        "ShowMessageBox", (params) => NotifyUI.ShowMessageBox(params)
    )

    ; コマンド名 → 非同期ハンドラ(params, respond)。respondは (ok, resultMapOrErrorMessage) を受け取る関数。
    static _asyncDispatch := Map(
        "ShowInputDialog", (params, respond) => NotifyUI.ShowInputDialog(params, respond),
        "ShowChoiceDialog", (params, respond) => NotifyUI.ShowChoiceDialog(params, respond)
    )

    static Start() {
        if ExternalCommandServer.Enabled {
            return
        }
        TcpServer.OnLine := (line) => ExternalCommandServer._HandleLine(line)
        TcpServer.OnConnect := (*) => ExternalCommandServer._HandleConnect()
        TcpServer.OnDisconnect := (*) => ExternalCommandServer._HandleDisconnect()
        TcpServer.Start()
        ExternalCommandServer.Enabled := true
        Logger.Info("外部コマンド受付を有効化しました")
    }

    static Stop() {
        if !ExternalCommandServer.Enabled {
            return
        }
        TcpServer.Stop()
        ExternalCommandServer.Enabled := false
        ExternalCommandServer._authenticated := false
        Logger.Info("外部コマンド受付を無効化しました")
    }

    static Toggle() {
        if ExternalCommandServer.Enabled {
            ExternalCommandServer.Stop()
        } else {
            ExternalCommandServer.Start()
        }
    }

    static IsConnected() {
        return TcpServer.IsConnected()
    }

    static _HandleConnect() {
        ExternalCommandServer._authenticated := false
        TrayMenu.RefreshExternalCommandStatus()
    }

    static _HandleDisconnect() {
        ExternalCommandServer._authenticated := false
        TrayMenu.RefreshExternalCommandStatus()
    }

    static _HandleLine(line) {
        try {
            request := Json.Parse(line)
        } catch as e {
            Logger.Error("受信メッセージのJSON解析に失敗しました: " e.Message)
            Logger.Debug("受信内容: " line)
            return
        }

        if Type(request) != "Map" {
            Logger.Error("受信メッセージがJSONオブジェクトではありません")
            Logger.Debug("受信内容: " line)
            return
        }

        id := request.Get("id", "")
        command := request.Get("command", "")
        params := request.Get("params", Map())

        Logger.Debug("コマンド受信 command=" command " id=" id " authenticated=" ExternalCommandServer._authenticated)

        if !ExternalCommandServer._authenticated {
            if command = "Auth" {
                ExternalCommandServer._HandleAuth(id, params)
            } else {
                Logger.Info("未認証状態でのコマンドを拒否しました command=" command)
                ExternalCommandServer._RespondError(id, "authentication required")
                TcpServer.DisconnectClient()
            }
            return
        }

        if command = "Auth" {
            ; 認証済み接続への再認証は許可しない(不要な複雑化を避けるため)
            ExternalCommandServer._RespondError(id, "already authenticated")
            return
        }

        respond := (ok, payload) => ExternalCommandServer._Respond(id, ok, payload)

        if ExternalCommandServer._asyncDispatch.Has(command) {
            handler := ExternalCommandServer._asyncDispatch[command]
            try {
                handler.Call(params, respond)
            } catch as e {
                Logger.Error("非同期コマンドの起動に失敗しました command=" command ": " e.Message)
                Logger.Debug("params=" Json.Stringify(params))
                respond(false, e.Message)
            }
            return
        }

        if ExternalCommandServer._syncDispatch.Has(command) {
            handler := ExternalCommandServer._syncDispatch[command]
            try {
                result := handler.Call(params)
                respond(true, result ?? Map())
            } catch as e {
                Logger.Error("コマンド実行に失敗しました command=" command ": " e.Message)
                Logger.Debug("params=" Json.Stringify(params))
                respond(false, e.Message)
            }
            return
        }

        Logger.Info("未知のコマンドを受信しました command=" command)
        ExternalCommandServer._RespondError(id, "unknown command: " command)
    }

    static _HandleAuth(id, params) {
        token := (Type(params) = "Map") ? params.Get("token", "") : ""
        if token = Settings.AuthToken {
            ExternalCommandServer._authenticated := true
            ExternalCommandServer._RespondOk(id, Map())
            Logger.Info("クライアントの認証に成功しました")
        } else {
            ExternalCommandServer._RespondError(id, "authentication required")
            Logger.Info("クライアントの認証に失敗しました(トークン不一致)")
            TcpServer.DisconnectClient()
        }
    }

    static _Respond(id, ok, payload) {
        if ok {
            ExternalCommandServer._RespondOk(id, payload)
        } else {
            ExternalCommandServer._RespondError(id, payload)
        }
    }

    static _RespondOk(id, result) {
        response := Map("id", id, "ok", Json.Bool(true), "result", result)
        TcpServer.SendLine(Json.Stringify(response))
    }

    static _RespondError(id, message) {
        response := Map("id", id, "ok", Json.Bool(false), "error", message)
        TcpServer.SendLine(Json.Stringify(response))
    }
}
