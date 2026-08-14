#Requires AutoHotkey v2.0
#SingleInstance Force

; lib/Json.ahk の単体テスト。GUIを開かず、アサーション結果をコンソール出力してExitApp()する。
; 実行例: AutoHotkey64.exe tests\test_json.ahk
#Include ..\src\lib\Json.ahk

failures := 0
passed := 0

Assert(actual, expected, label) {
    global failures, passed
    if actual == expected {
        passed++
    } else {
        failures++
        FileAppend("FAIL: " label " expected=[" expected "] actual=[" actual "]`n", "*")
    }
}

; ---- Stringify ----
Assert(Json.Stringify(Map("a", 1, "b", "hello")), '{"a":1,"b":"hello"}', "stringify basic object")
Assert(Json.Stringify(Array(1, 2, 3)), "[1,2,3]", "stringify array")
Assert(Json.Stringify("123"), '"123"', "stringify numeric-looking string stays a string")
Assert(Json.Stringify(123), "123", "stringify real integer is a number")
Assert(Json.Stringify(Json.Bool(true)), "true", "stringify Json.Bool(true)")
Assert(Json.Stringify(Json.Bool(false)), "false", "stringify Json.Bool(false)")
Assert(Json.Stringify("a`nb"), '"a\nb"', "stringify escapes newline")
Assert(Json.Stringify('a"b\c'), '"a\"b\\c"', "stringify escapes quote and backslash")
Assert(Json.Stringify(Map("x", Array(Map("y", 1)))), '{"x":[{"y":1}]}', "stringify nested structures")

; ---- Parse ----
parsed := Json.Parse('{"id":"req-1","command":"ActivateWindow","params":{"winTitle":"ahk_exe notepad.exe"}}')
Assert(Type(parsed), "Map", "parse object -> Map")
Assert(parsed["id"], "req-1", "parse string field")
Assert(Type(parsed["params"]), "Map", "parse nested object -> Map")
Assert(parsed["params"]["winTitle"], "ahk_exe notepad.exe", "parse nested string field")

arr := Json.Parse('[1, 2.5, -3, true, false, null, "txt"]')
Assert(Type(arr), "Array", "parse array -> Array")
Assert(arr[1], 1, "parse integer element")
Assert(arr[2], 2.5, "parse float element")
Assert(arr[3], -3, "parse negative integer element")
Assert(arr[4], 1, "parse true -> 1")
Assert(arr[5], 0, "parse false -> 0")
Assert(arr[6], "", "parse null -> empty string")
Assert(arr[7], "txt", "parse string element")

escaped := Json.Parse('"line1\nline2\t\"quoted\"\\backslash"')
Assert(escaped, "line1`nline2`t`"quoted`"\backslash", "parse string escapes")

unicodeEscaped := Json.Parse('"あい"')
Assert(unicodeEscaped, "あい", "parse \\u escapes (Japanese)")

; 数値文字列と実数値の型がラウンドトリップで区別できること
Assert(Json.Stringify(Json.Parse('"42"')), '"42"', "roundtrip: JSON string stays a string")
Assert(Json.Stringify(Json.Parse("42")), "42", "roundtrip: JSON number stays a number")

; エラーケース
threw := false
try {
    Json.Parse("{invalid")
} catch {
    threw := true
}
Assert(threw, true, "parse throws on malformed JSON")

FileAppend("passed=" passed " failures=" failures "`n", "*")
ExitApp(failures = 0 ? 0 : 1)
