#Requires AutoHotkey v2.0

; 設計: docs/external-command-server.md
; features/InputControl.ahk の PlayMacro コマンドから参照するマクロ定義。
; 名前ごとにキー操作のステップ列(Array)を持つ。
;
; ステップは Map("type", "key"|"text"|"sleep", "value", ...) の形式。
;   type="key"  : value を Send() にそのまま渡す(例: "{Enter}", "^c" などAHKの送信構文)
;   type="text" : value の文字列をそのまま入力する(SendText相当。キー構文は解釈しない)
;   type="sleep": value にミリ秒を指定し、その時間だけ待機する
class Macros {
    static Definitions := Map(
        ; 記述例(必要に応じてコメントを外して調整する):
        ; "ExampleGreeting", [
        ;     Map("type", "text", "value", "こんにちは"),
        ;     Map("type", "key", "value", "{Enter}")
        ; ]
    )
}
