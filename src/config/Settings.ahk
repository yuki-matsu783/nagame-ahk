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

    ; ExternalCommandServer: リッスンするアドレス(ループバック固定。docs/external-command-server.md 参照)
    static ServerHost := "127.0.0.1"
    ; ExternalCommandServer: リッスンするポート番号
    static ServerPort := 39321
    ; ExternalCommandServer: accept/recv/sendの可否確認のポーリング間隔(ms)
    static ServerPollIntervalMs := 50
    ; ExternalCommandServer: 読み書きバッファサイズ(byte)
    static ServerBufferSize := 4096
    ; ExternalCommandServer: アプリ起動時にサーバーを自動起動するか
    static ExternalCommandAutoStart := true
    ; ExternalCommandServer: 接続直後の認証で要求する共有トークン
    static AuthToken := "ahk-rira"
    ; ClipboardControl: クリップボード履歴の最大保持件数
    static ClipboardHistoryMax := 50
}
