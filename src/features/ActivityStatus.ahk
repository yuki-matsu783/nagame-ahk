#Requires AutoHotkey v2.0

; 設計: docs/activity-status.md
; マウス・キーボード操作の有無（アクティブ / 非アクティブ）をカーソル付近にツールチップ表示する機能。
; A_TimeIdlePhysical（直近の物理入力からの経過時間）が Settings.IdleThresholdMs 以上であれば
; 「非アクティブ」と判定する。物理入力のみを見るため Send 等による合成入力には反応しない。
class ActivityStatus {
    static Enabled := false
    static _lastState := ""
    ; SetTimer の ON/OFF は同一のコールバックオブジェクトを渡す必要があるため、
    ; static メソッドをファットアローで包んだものを1つだけ保持して Start/Stop で使い回す。
    ; （static メソッドを ActivityStatus._Update のように裸で参照すると、暗黙の this 引数を
    ; 　要求する未束縛の Func になり、引数0個で呼ばれる SetTimer からは
    ; 　"Invalid callback function" エラーになるため）
    static _timerCallback := (*) => ActivityStatus._Update()

    ; 表示を開始する
    static Start() {
        if ActivityStatus.Enabled {
            return
        }
        ActivityStatus.Enabled := true
        ActivityStatus._lastState := ""
        SetTimer(ActivityStatus._timerCallback, Settings.ActivityCheckIntervalMs)
        Logger.Info("操作状態ツールチップを開始しました")
    }

    ; 表示を停止する
    static Stop() {
        if !ActivityStatus.Enabled {
            return
        }
        SetTimer(ActivityStatus._timerCallback, 0)
        ToolTip()
        ActivityStatus.Enabled := false
        Logger.Info("操作状態ツールチップを停止しました")
    }

    ; 表示のON/OFFを切り替える
    static Toggle() {
        if ActivityStatus.Enabled {
            ActivityStatus.Stop()
        } else {
            ActivityStatus.Start()
        }
    }

    ; タイマーコールバック: 状態を判定してツールチップを更新する
    static _Update(*) {
        isActive := A_TimeIdlePhysical < Settings.IdleThresholdMs
        state := isActive ? "アクティブ" : "非アクティブ"

        ; 状態が変化した時だけログを残す（毎回書くとログが埋まるため）
        if state != ActivityStatus._lastState {
            Logger.Info("操作状態が変化: " state)
            ActivityStatus._lastState := state
        }

        MouseGetPos(&mouseX, &mouseY)
        ToolTip(state, mouseX + 16, mouseY + 16)
    }
}
