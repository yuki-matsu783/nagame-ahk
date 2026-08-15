#Requires AutoHotkey v2.0

; 設計: docs/spec/logger.md
; ログ出力用のユーティリティ。core/ や features/ から共通で利用する。
; Settings.LogLevel で設定したレベル以上のログのみ、コンソール・ファイルの両方に出力する。
class Logger {
    ; レベルの重み。数値が大きいほど重要度が高い。
    static Levels := Map(
        "DEBUG", 0,
        "INFO", 1,
        "WARN", 2,
        "ERROR", 3,
        "NONE", 4
    )

    static Debug(message) {
        Logger._Write("DEBUG", message)
    }

    static Info(message) {
        Logger._Write("INFO", message)
    }

    static Warn(message) {
        Logger._Write("WARN", message)
    }

    static Error(message) {
        Logger._Write("ERROR", message)
    }

    static _Write(level, message) {
        if !Logger._ShouldOutput(level) {
            return
        }

        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" level "] " message

        Logger._WriteConsole(line)
        Logger._WriteFile(line)
    }

    ; Settings.LogLevel と比較し、出力すべきレベルかどうかを判定する
    static _ShouldOutput(level) {
        threshold := Logger.Levels.Get(Settings.LogLevel, Logger.Levels["INFO"])
        return Logger.Levels[level] >= threshold
    }

    ; 標準出力(stdout)に書き出す。
    ; AHKはGUIサブシステムのため、cmd/PowerShell等のコンソールから起動した場合のみ表示される。
    ; アイコンダブルクリック等コンソールが無い状態で実行した場合は何もしない（例外を握りつぶす）。
    static _WriteConsole(line) {
        try {
            ; エンコーディング省略時はシステムのANSIコードページで書き込まれ、
            ; UTF-8前提でstdoutを読むツール（VSCode拡張のahk++等）で文字化けするため明示する。
            ; "*"(stdout)は永続ハンドルを持たず毎回BOMが付与されてしまうため、BOM無しの UTF-8-RAW を使う。
            FileAppend(line "`n", "*", "UTF-8-RAW")
        } catch as e {
            ; コンソール未接続時は stdout への書き込みが失敗するため、代わりにDebugView等で拾えるよう出力する
            OutputDebug(line)
        }
    }

    static _WriteFile(line) {
        try {
            FileAppend(line "`n", Settings.LogFilePath, "UTF-8")
        } catch as e {
            OutputDebug(line)
        }
    }
}
