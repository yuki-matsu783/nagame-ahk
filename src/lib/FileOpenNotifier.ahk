#Requires AutoHotkey v2.0

; 設計: docs/office-file-watcher.md(TrayTip表示内容), docs/pdf-file-watcher.md
; ウィンドウ検出結果(ファイル情報・プロセス情報)をJSON文字列に整形し、TrayTipで表示する汎用処理。
; features/OfficeFileWatcher.ahk・features/PdfFileWatcher.ahkから共通で利用する
; (lib/TcpServer.ahkとcore/ExternalCommandServer.ahkの役割分担と同じ考え方)。
class FileOpenNotifier {
    ; TrayTipを消すためのSetTimerコールバック(引数無しで呼ばれるため、既存のSetTimerパターンと
    ; 同様にstaticプロパティとして1つ保持し使い回す)
    static _clearCallback := (*) => TrayTip()

    ; 検出結果のMapをJSON文字列に変換する。
    ; info: Map("type",..,"fileName",..,"path",..,"pathResolved",bool,"windowTitle",..,
    ;           "process",Map("name",..,"pid",..,"path",..))
    ; ロジックを純粋な変換処理として分離することで、実ウィンドウ・COM無しに単体テストできるようにする
    ; (tests/test_file_open_notifier.ahk参照)。
    static BuildJson(info) {
        process := info["process"]
        payload := Map(
            "type", info["type"],
            "fileName", info["fileName"],
            "path", info["path"],
            "pathResolved", Json.Bool(info["pathResolved"]),
            "windowTitle", info["windowTitle"],
            "process", Map(
                "name", process["name"],
                "pid", process["pid"],
                "path", process["path"]
            )
        )
        return Json.Stringify(payload)
    }

    ; JSON文字列をTrayTipで表示し、durationMs後に明示的に消す
    ; (TrayTipはOSによって自動で消えないことがあるため。NotifyUI.ShowToastと同じ理由)。
    static Show(title, json, durationMs) {
        TrayTip(json, title)
        SetTimer(FileOpenNotifier._clearCallback, -durationMs)
    }
}
