#Requires AutoHotkey v2.0

; 設計: docs/office-file-watcher.md(検出方法), docs/pdf-file-watcher.md
; SetWinEventHookで新規ウィンドウの表示(EVENT_OBJECT_SHOW)を検出し、指定したプロセス名に一致する
; ウィンドウをコールバックに通知する汎用クラス。features/OfficeFileWatcher.ahk・features/PdfFileWatcher.ahk
; から、監視対象プロセス名とファイル情報の収集ロジックだけを差し替えて利用する
; (lib/TcpServer.ahkとcore/ExternalCommandServer.ahkの役割分担と同じ考え方)。
;
; SetWinEventHookのコールバックにはコンテキスト引数が無く、Office監視・PDF監視を独立したフックとして
; 同時に動かすにはフックごとに別々の状態(対象プロセス名・通知済みhwnd集合・フックハンドル)が要るため、
; 本プロジェクトで唯一インスタンス化可能なクラスとして実装する(他のクラスは全てstaticのみで運用している
; 点からの意図的な逸脱。理由の詳細はdocs/office-file-watcher.mdの「検出方法」節を参照)。
; 呼び出し側は1つの監視対象につき1インスタンスを生成して使う。
class WindowOpenWatcher {
    ; ---- WinEvent(user32)関連の定数 ----
    ; アプリ設定ではなくWindows APIのプロトコル定数のため、Settingsではなくここに定義する
    ; (src/lib/TcpServer.ahkのWinsock定数と同じ方針)。
    static EVENT_OBJECT_DESTROY := 0x8001
    static EVENT_OBJECT_SHOW := 0x8002
    static OBJID_WINDOW := 0
    static CHILDID_SELF := 0
    static WINEVENT_OUTOFCONTEXT := 0x0000
    static WINEVENT_SKIPOWNPROCESS := 0x0002

    Enabled := false

    ; targetProcessNames: 監視対象プロセス名の配列(例: Settings.OfficeProcessNames)
    ; onWindowShown: 対象プロセスの新規ウィンドウ検出時に呼ばれるコールバック。引数(hwnd, processName)
    __New(targetProcessNames, onWindowShown) {
        this.TargetProcessNames := targetProcessNames
        this.OnWindowShown := onWindowShown
        this._hHook := 0
        ; 検出済み(通知済み)hwndの集合。EVENT_OBJECT_SHOWが同じウィンドウに対して複数回
        ; 飛んでくることがある(最小化からの復元等)ため、重複通知を防ぐために保持する。
        ; ウィンドウが破棄されたら(EVENT_OBJECT_DESTROY)取り除く。
        this._notifiedHwnds := Map()
        ; SetWinEventHookのコールバックはOS(user32)から直接呼ばれるネイティブ関数ポインタが必要なため
        ; CallbackCreate()で作成する。Start/Stopで同一のオブジェクトを扱えるよう、また作成した
        ; トランポリンがGCされないよう、インスタンスプロパティとして1つだけ保持する。
        ; ファットアローで`this`をクロージャとして捕捉することで、インスタンスごとに独立した
        ; コールバックにする(staticメソッドを裸で参照すると暗黙のthis引数を要求する未束縛のFuncに
        ; なるため必ずこのように包んで呼び出す、という本プロジェクトの既存方針にも合わせている)。
        this._hookCallback := CallbackCreate(
            (hWinEventHook, event, hwnd, idObject, idChild, idEventThread, dwmsEventTime)
                => this._WinEventProc(event, hwnd, idObject, idChild),
            "")
    }

    ; 監視を開始する
    Start() {
        if this.Enabled {
            return
        }

        try {
            this._notifiedHwnds := Map()
            hHook := DllCall(
                "user32\SetWinEventHook",
                "UInt", WindowOpenWatcher.EVENT_OBJECT_DESTROY,
                "UInt", WindowOpenWatcher.EVENT_OBJECT_SHOW,
                "Ptr", 0,
                "Ptr", this._hookCallback,
                "UInt", 0,
                "UInt", 0,
                "UInt", WindowOpenWatcher.WINEVENT_OUTOFCONTEXT | WindowOpenWatcher.WINEVENT_SKIPOWNPROCESS,
                "Ptr")
            if hHook = 0 {
                throw Error("SetWinEventHookが0(失敗)を返しました")
            }
            this._hHook := hHook
            this.Enabled := true
            Logger.Info("ウィンドウ監視を開始しました (対象プロセス: " this._TargetProcessNamesText() ")")
        } catch as e {
            Logger.Error("ウィンドウ監視の開始に失敗しました: " e.Message)
            this._hHook := 0
        }
    }

    ; 監視を停止する
    Stop() {
        if !this.Enabled {
            return
        }

        try {
            DllCall("user32\UnhookWinEvent", "Ptr", this._hHook)
        } catch as e {
            Logger.Error("ウィンドウ監視の停止(UnhookWinEvent)に失敗しました: " e.Message)
        }
        this._hHook := 0
        this.Enabled := false
        Logger.Info("ウィンドウ監視を停止しました (対象プロセス: " this._TargetProcessNamesText() ")")
    }

    ; 監視のON/OFFを切り替える
    Toggle() {
        if this.Enabled {
            this.Stop()
        } else {
            this.Start()
        }
    }

    ; SetWinEventHookのコールバック本体。
    ; WINEVENT_OUTOFCONTEXTで登録しているため、フック設置元スレッド(AHKのメインスレッド)の
    ; メッセージキュー経由で呼ばれる。そのためコールバック内で時間のかかる処理を行っても安全。
    _WinEventProc(event, hwnd, idObject, idChild) {
        ; コントロール単位のイベントは対象外とし、ウィンドウそのものの表示/破棄イベントのみ扱う
        if idObject != WindowOpenWatcher.OBJID_WINDOW || idChild != WindowOpenWatcher.CHILDID_SELF {
            return
        }

        if event = WindowOpenWatcher.EVENT_OBJECT_DESTROY {
            ; DESTROYイベントは監視対象外のウィンドウも含め全hwndで飛んでくるため、
            ; 追跡していないhwndの方が多い。Map.Delete()は未登録キーだと例外になるため、
            ; 事前にHas()で存在確認してから削除する(実機での動作確認で発見した不具合)。
            if this._notifiedHwnds.Has(hwnd) {
                this._notifiedHwnds.Delete(hwnd)
            }
            return
        }

        if event != WindowOpenWatcher.EVENT_OBJECT_SHOW {
            return
        }

        try {
            this._HandleWindowShown(hwnd)
        } catch as e {
            ; フックコールバック内の例外でスクリプト全体を落とさないよう、ここで必ず捕捉する
            Logger.Error("ウィンドウ検出処理に失敗しました: " e.Message)
            Logger.Debug("hwnd=" hwnd " event=" event)
        }
    }

    ; 新規に表示されたウィンドウが監視対象プロセスかどうかを判定し、対象であれば通知する。
    _HandleWindowShown(hwnd) {
        if this._notifiedHwnds.Has(hwnd) {
            return
        }

        processName := ""
        try {
            processName := WinGetProcessName(hwnd)
        } catch as e {
            ; 検出直後にウィンドウが閉じられた場合などに失敗しうる。対象外として静かに抜ける
            Logger.Debug("WinGetProcessNameに失敗したためスキップしました hwnd=" hwnd ": " e.Message)
            return
        }

        if !this._IsTargetProcess(processName) {
            return
        }

        ; 通知コールバック呼び出しより前に通知済みとして記録する(コールバック処理中に同じhwndへの
        ; 再入イベントが来ても二重通知しないため)
        this._notifiedHwnds[hwnd] := true
        Logger.Debug("対象ウィンドウを検出しました hwnd=" hwnd " process=" processName)

        this.OnWindowShown.Call(hwnd, processName)
    }

    ; プロセス名がTargetProcessNamesに含まれるか判定する
    _IsTargetProcess(processName) {
        for name in this.TargetProcessNames {
            if name = processName {
                return true
            }
        }
        return false
    }

    ; ログ出力用に対象プロセス名一覧をカンマ区切りの文字列にする
    _TargetProcessNamesText() {
        text := ""
        for i, name in this.TargetProcessNames {
            text .= (i = 1 ? "" : ", ") name
        }
        return text
    }
}
