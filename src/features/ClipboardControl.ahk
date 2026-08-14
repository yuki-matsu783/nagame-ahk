#Requires AutoHotkey v2.0

; 設計: docs/spec/external-command-server.md
; 外部コマンドサーバーのクリップボード系コマンド(GetClipboard/PasteFormatted等)の実処理。
; 履歴はメモリ上にのみ保持し、永続化はしない(再起動で消える。設計ドキュメント参照)。
; 例外はcore/ExternalCommandServer.ahkの側で一括してエラー応答に変換される
; (詳細はcore/ExternalCommandServer.ahk冒頭のコメント参照)。
class ClipboardControl {
    ; 各要素: Map("text", ..., "timestamp", ...)。先頭が最新。
    static _history := []
    static _watching := false
    ; OnClipboardChangeの登録/解除には同一のコールバックオブジェクトが必要なため、
    ; static プロパティとして1つ保持する。
    static _onClipChangeCallback := (type) => ClipboardControl._OnClipboardChange(type)

    ; クリップボード監視を開始する。App起動時に一度だけ呼ばれる想定(常時監視)。
    static StartWatching() {
        if ClipboardControl._watching {
            return
        }
        OnClipboardChange(ClipboardControl._onClipChangeCallback)
        ClipboardControl._watching := true
        Logger.Debug("クリップボード履歴の監視を開始しました")
    }

    static _OnClipboardChange(type) {
        ; type: 0=空, 1=テキスト, 2=非テキスト(画像等)。テキストのみ履歴に残す。
        if type != 1 {
            return
        }
        try {
            ClipboardControl._history.InsertAt(1, Map("text", A_Clipboard, "timestamp", FormatTime(, "yyyy-MM-dd HH:mm:ss")))
            if ClipboardControl._history.Length > Settings.ClipboardHistoryMax {
                ClipboardControl._history.Pop()
            }
        } catch as e {
            Logger.Error("クリップボード履歴の記録に失敗しました: " e.Message)
        }
    }

    static GetClipboard(params) {
        return Map("text", A_Clipboard)
    }

    static SetClipboard(params) {
        A_Clipboard := params["text"]
        return Map()
    }

    static GetClipboardHistory(params) {
        limit := params.Get("limit", Settings.ClipboardHistoryMax)
        items := Array()
        for i, entry in ClipboardControl._history {
            if i > limit {
                break
            }
            items.Push(entry)
        }
        return Map("items", items)
    }

    static ClearClipboardHistory(params) {
        ClipboardControl._history := []
        return Map()
    }

    ; テキストを整形してからクリップボード経由で貼り付ける
    static PasteFormatted(params) {
        text := ClipboardControl._ApplyFormat(params["text"], params.Get("format", Map()))
        winTitle := params.Get("winTitle", "")

        if winTitle != "" {
            WinActivate(winTitle)
        }

        previous := ClipboardAll()
        A_Clipboard := text
        if !ClipWait(1) {
            Logger.Debug("ClipWaitがタイムアウトしました")
        }
        Send("^v")
        Sleep(50)
        A_Clipboard := previous
        return Map()
    }

    static _ApplyFormat(text, format) {
        newline := format.Get("normalizeNewline", "")
        if newline != "" {
            ; 改行コードを一旦LFに統一してから指定コードへ変換する
            text := StrReplace(text, "`r`n", "`n")
            text := StrReplace(text, "`r", "`n")
            switch newline {
                case "CRLF":
                    text := StrReplace(text, "`n", "`r`n")
                case "CR":
                    text := StrReplace(text, "`n", "`r")
                case "LF":
                    ; 既にLFへ統一済みのため何もしない
                default:
                    throw Error("不明なnormalizeNewlineです: " newline)
            }
        }

        if format.Get("trimLines", false) {
            lines := StrSplit(text, "`n")
            result := ""
            for i, line in lines {
                result .= (i = 1 ? "" : "`n") Trim(line)
            }
            text := result
        }

        if format.Get("trim", false) {
            text := Trim(text)
        }

        return text
    }
}
