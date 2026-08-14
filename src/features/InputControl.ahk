#Requires AutoHotkey v2.0

; 設計: docs/spec/external-command-server.md
; 外部コマンドサーバーの入力操作系コマンド(SendKeys/MouseClick/PlayMacro等)の実処理。
; 例外はcore/ExternalCommandServer.ahkの側で一括してエラー応答に変換される
; (詳細はcore/ExternalCommandServer.ahk冒頭のコメント参照)。
class InputControl {
    static SendKeys(params) {
        keys := params["keys"]
        winTitle := params.Get("winTitle", "")
        if winTitle != "" {
            ControlSend(keys, , winTitle)
        } else {
            Send(keys)
        }
        return Map()
    }

    ; AHK組み込み関数 SendText() と同名のメソッドだが、クラスメソッドは
    ; InputControl.SendText(...) のように必ずクラス名経由でしか呼ばれないため、
    ; メソッド内部でのbareな SendText(...) 呼び出しは組み込み関数を指し、衝突・再帰は発生しない。
    static SendText(params) {
        text := params["text"]
        winTitle := params.Get("winTitle", "")
        method := params.Get("method", "send")

        if winTitle != "" {
            WinActivate(winTitle)
        }

        if method = "clipboard" {
            InputControl._PasteViaClipboard(text)
        } else {
            SendText(text)
        }
        return Map()
    }

    ; クリップボード経由で高速に貼り付ける。貼り付け後は元のクリップボード内容へ復元する。
    static _PasteViaClipboard(text) {
        previous := ClipboardAll()
        A_Clipboard := text
        ; クリップボードへの反映を待つ(即座にSendすると反映前のデータが貼り付けられることがある)
        if !ClipWait(1) {
            Logger.Debug("ClipWaitがタイムアウトしました")
        }
        Send("^v")
        Sleep(50) ; 貼り付け処理が終わるまで少し待ってから元の内容へ復元する
        A_Clipboard := previous
    }

    ; AHK組み込み関数 MouseClick() と同名のメソッドだが、SendTextと同様の理由で衝突しない。
    static MouseClick(params) {
        x := params["x"]
        y := params["y"]
        button := params.Get("button", "left")
        winTitle := params.Get("winTitle", "")

        if winTitle != "" {
            WinActivate(winTitle)
        }
        MouseClick(InputControl._ToAhkButton(button), x, y)
        return Map()
    }

    static MouseDrag(params) {
        fromX := params["fromX"]
        fromY := params["fromY"]
        toX := params["toX"]
        toY := params["toY"]
        button := InputControl._ToAhkButton(params.Get("button", "left"))

        MouseClick(button, fromX, fromY, , , "D")
        MouseMove(toX, toY)
        MouseClick(button, toX, toY, , , "U")
        return Map()
    }

    static MouseScroll(params) {
        x := params["x"]
        y := params["y"]
        delta := params["delta"]
        wheelButton := delta > 0 ? "WheelUp" : "WheelDown"
        MouseClick(wheelButton, x, y, Abs(delta))
        return Map()
    }

    static PlayMacro(params) {
        name := params["name"]
        if !Macros.Definitions.Has(name) {
            throw Error("未定義のマクロです: " name)
        }
        for step in Macros.Definitions[name] {
            InputControl._RunMacroStep(step)
        }
        return Map()
    }

    static _RunMacroStep(step) {
        switch step["type"] {
            case "key":
                Send(step["value"])
            case "text":
                SendText(step["value"])
            case "sleep":
                Sleep(step["value"])
            default:
                throw Error("不明なマクロステップtypeです: " step["type"])
        }
    }

    static _ToAhkButton(button) {
        switch button {
            case "left":
                return "Left"
            case "right":
                return "Right"
            case "middle":
                return "Middle"
            default:
                throw Error("不明なbuttonです: " button)
        }
    }
}
