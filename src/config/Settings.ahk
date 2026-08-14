#Requires AutoHotkey v2.0

; アプリ全体の設定値・定数を集約するクラス。
; マジックナンバーやリテラルをコード中に直書きせず、ここに定義する。
class Settings {
    static AppName := "nagame-ahk"
    static Version := "0.1.0"
    static LogFilePath := A_ScriptDir "\..\nagame-ahk.log"
    ; Logger: 出力する最低ログレベル。"DEBUG" | "INFO" | "WARN" | "ERROR" | "NONE"（Logger.Levels 参照）
    ; ここで設定したレベル以上のログのみ、コンソール・ファイルの両方に出力される。
    static LogLevel := "INFO"

    ; ActivityStatus: 非アクティブと判定するまでの無操作時間(ms)
    static IdleThresholdMs := 3000
    ; ActivityStatus: 状態判定・ツールチップ更新の間隔(ms)
    static ActivityCheckIntervalMs := 200
}
