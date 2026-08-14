#Requires AutoHotkey v2.0

; 設計: docs/external-command-server.md
; JSONのエンコード/デコードを行う最小限の自作実装。
; プロトコルに必要な範囲(object/array/string/number/true/false/null)のみをサポートする。
;
; 型に関する制約(実装時の判断。詳細は docs/external-command-server.md の「JSONエンコード/デコード」参照):
; - AHKには真偽値専用の型が無いため、デコード結果の true/false はそれぞれ整数 1/0 を返す
;   (if文での真偽判定にはそのまま使える)。エンコード時に明示的にJSONのtrue/falseを出力したい場合は
;   Json.Bool(value) でラップしてから渡すこと。
; - null はデコード時に空文字列 "" として扱う(エンコード方向のnullサポートは本プロトコルでは不要のため範囲外)。
; - 数値と文字列の判別には IsNumber() ではなく Type() を使う。AHK v2は数値に見える文字列
;   (例: "123") と実際の数値型を Type() で区別できるため、"123" という文字列を渡した場合は
;   JSON文字列として、実際の整数 123 を渡した場合はJSON数値として出力される
;   (WinGetPos等が返す座標・ハンドルは整数型なので正しく数値として出力される)。
; - \u エスケープのサロゲートペアは、AHKの文字列がUTF-16内部表現であるため、
;   上位/下位サロゲートをそれぞれ個別に Chr() して連結するだけで正しい文字列になる
;   (特別な合成処理は不要)。
class Json {
    ; エンコード時にJSONのtrue/falseを明示したい値をラップするためのマーカークラス。
    ; デコード結果はこのクラスを経由しない(単純な1/0を返す)ため、if文での真偽判定を妨げない。
    class BoolValue {
        __New(value) {
            this.Value := value
        }
    }
    static True := Json.BoolValue(true)
    static False := Json.BoolValue(false)
    
    ; 任意の値(真偽として評価できるもの)をJSONのtrue/falseとしてエンコードするためのラッパー
    static Bool(nativeValue) {
        return nativeValue ? Json.True : Json.False
    }
    
    ; ------------------------------------------------------------
    ; エンコード
    ; ------------------------------------------------------------
    
    static Stringify(value) {
        out := ""
        Json._WriteValue(value, &out)
        return out
    }
    
    static _WriteValue(value, &out) {
        if value is Json.BoolValue {
            out .= value.Value ? "true" : "false"
        } else if value is Map {
            Json._WriteObject(value, &out)
        } else if value is Array {
            Json._WriteArray(value, &out)
        } else if Type(value) = "Integer" || Type(value) = "Float" {
            out .= value
        } else {
            out .= Json._WriteString(String(value))
        }
    }
    
    static _WriteObject(map, &out) {
        out .= "{"
            first := true
            for key, val in map {
                if !first {
                    out .= ","
                }
                first := false
                out .= Json._WriteString(String(key))
                out .= ":"
                Json._WriteValue(val, &out)
            }
        out .= "}"
    }
    
    static _WriteArray(arr, &out) {
        out .= "["
        first := true
        for _, val in arr {
            if !first {
                out .= ","
            }
            first := false
            Json._WriteValue(val, &out)
        }
        out .= "]"
    }
    
    static _WriteString(str) {
        ; バックスラッシュを最初にエスケープしないと、後続の置換で追加したバックスラッシュまで
        ; 二重にエスケープしてしまうため順序が重要
        escaped := StrReplace(str, "\", "\\")
        escaped := StrReplace(escaped, '"', '\"')
        escaped := StrReplace(escaped, "`n", "\n")
        escaped := StrReplace(escaped, "`r", "\r")
        escaped := StrReplace(escaped, "`t", "\t")
        
        ; 上記以外の制御文字(0x00-0x1F)を \u00XX 形式でエスケープする
        out := ""
        loop parse escaped {
            code := Ord(A_LoopField)
            if code < 0x20 {
                out .= "\u" Format("{:04x}", code)
            } else {
                out .= A_LoopField
                }
        }
        return '"' out '"'
    }
    
    ; ------------------------------------------------------------
    ; デコード
    ; ------------------------------------------------------------
    
    static Parse(text) {
        pos := 1
        len := StrLen(text)
        value := Json._ParseValue(text, &pos, len)
        Json._SkipWhitespace(text, &pos, len)
        if pos <= len {
            throw Error("JSONの末尾に余分な文字があります (pos=" pos ")")
        }
        return value
    }
    
    static _SkipWhitespace(text, &pos, len) {
        while pos <= len && InStr(" `t`r`n", SubStr(text, pos, 1)) {
            pos++
        }
    }
    
    static _ParseValue(text, &pos, len) {
        Json._SkipWhitespace(text, &pos, len)
        if pos > len {
            throw Error("JSONが予期せず終了しました")
        }
        switch SubStr(text, pos, 1) {
            case "{":
                return Json._ParseObject(text, &pos, len)
                case "[":
                return Json._ParseArray(text, &pos, len)
                case '"':
                return Json._ParseString(text, &pos, len)
                case "t":
                    Json._Expect(text, &pos, len, "true")
                return 1
                case "f":
                    Json._Expect(text, &pos, len, "false")
                return 0
                case "n":
                    Json._Expect(text, &pos, len, "null")
                return ""
                default:
                return Json._ParseNumber(text, &pos, len)
            }
        }
        
        static _Expect(text, &pos, len, literal) {
            actual := SubStr(text, pos, StrLen(literal))
            if actual != literal {
                throw Error("不正なJSONリテラルです (pos=" pos ")")
            }
            pos += StrLen(literal)
        }
        
        static _ParseObject(text, &pos, len) {
            result := Map()
            pos++ ; skip '{'
            Json._SkipWhitespace(text, &pos, len)
        if SubStr(text, pos, 1) = "}" {
            pos++
            return result
        }
        loop {
            Json._SkipWhitespace(text, &pos, len)
            if SubStr(text, pos, 1) != '"' {
                throw Error("JSONオブジェクトのキーは文字列である必要があります (pos=" pos ")")
            }
            key := Json._ParseString(text, &pos, len)
            Json._SkipWhitespace(text, &pos, len)
            if SubStr(text, pos, 1) != ":" {
                throw Error("JSONオブジェクトで ':' が期待されます (pos=" pos ")")
            }
            pos++
            result[key] := Json._ParseValue(text, &pos, len)
            Json._SkipWhitespace(text, &pos, len)
            ch := SubStr(text, pos, 1)
            if ch = "," {
                pos++
                continue
            } else if ch = "}" {
                pos++
                break
            } else {
                throw Error("JSONオブジェクトの区切り文字が不正です (pos=" pos ")")
            }
        }
        return result
    }
    
    static _ParseArray(text, &pos, len) {
        result := Array()
        pos++ ; skip '['
        Json._SkipWhitespace(text, &pos, len)
        if SubStr(text, pos, 1) = "]" {
            pos++
            return result
        }
        loop {
            result.Push(Json._ParseValue(text, &pos, len))
            Json._SkipWhitespace(text, &pos, len)
            ch := SubStr(text, pos, 1)
            if ch = "," {
                pos++
                continue
            } else if ch = "]" {
                pos++
                break
            } else {
                throw Error("JSON配列の区切り文字が不正です (pos=" pos ")")
            }
        }
        return result
    }
    
    static _ParseString(text, &pos, len) {
        pos++ ; skip opening quote
        out := ""
        loop {
            if pos > len {
                throw Error("JSON文字列が閉じられていません")
            }
            ch := SubStr(text, pos, 1)
            if ch = '"' {
                pos++
                break
            } else if ch = "\" {
                pos++
                esc := SubStr(text, pos, 1)
                switch esc {
                case '"':
                    out .= '"'
                case "\":
                    out .= "\"
                case "/":
                    out .= "/"
                case "b":
                    out .= Chr(0x08)
                case "f":
                    out .= Chr(0x0C)
                case "n":
                    out .= "`n"
                case "r":
                    out .= "`r"
                case "t":
                    out .= "`t"
                case "u":
                    out .= Chr("0x" SubStr(text, pos + 1, 4))
                    pos += 4
                default:
                    throw Error("不正なエスケープシーケンスです (pos=" pos ")")
                }
                pos++
            } else {
                out .= ch
                pos++
            }
        }
        return out
    }
    
    static _ParseNumber(text, &pos, len) {
        start := pos
        if SubStr(text, pos, 1) = "-" {
            pos++
        }
        while pos <= len && InStr("0123456789", SubStr(text, pos, 1)) {
            pos++
        }
        if pos <= len && SubStr(text, pos, 1) = "." {
            pos++
            while pos <= len && InStr("0123456789", SubStr(text, pos, 1)) {
                pos++
            }
        }
        if pos <= len && (SubStr(text, pos, 1) = "e" || SubStr(text, pos, 1) = "E") {
            pos++
            if pos <= len && (SubStr(text, pos, 1) = "+" || SubStr(text, pos, 1) = "-") {
                pos++
            }
            while pos <= len && InStr("0123456789", SubStr(text, pos, 1)) {
                pos++
            }
        }
        numStr := SubStr(text, start, pos - start)
        if numStr = "" || numStr = "-" {
            throw Error("不正な数値です (pos=" start ")")
        }
        return Number(numStr)
    }
}
