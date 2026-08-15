#Requires AutoHotkey v2.0

; tests/配下の単体テストスクリプト共通のアサーションヘルパー。
; 呼び出し元スクリプトがグローバル変数 failures / passed を宣言している前提で使う
; (各テストスクリプトは独立プロセスとして実行されるため、グローバル変数もファイルごとに独立する)。
Assert(actual, expected, label) {
    global failures, passed
    if actual == expected {
        passed++
    } else {
        failures++
        FileAppend("FAIL: " label " expected=[" expected "] actual=[" actual "]`n", "*")
    }
}
