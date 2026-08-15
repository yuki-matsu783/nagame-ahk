#Requires AutoHotkey v2.0

; 設計: docs/spec/recent-docs-watcher.md
; Windowsの「最近使ったファイル」レジストリ(RecentDocs)をポーリングし、ファイル種別・アプリを問わず
; 新しいファイルが開かれたことをJSON化してTrayTipに表示する機能。
; OfficeFileWatcher/PdfFileWatcher(lib/WindowOpenWatcher.ahkベース)とは完全に独立しており、
; どちらにも依存しない(本機能から既存filewatcherを呼び出す等の連携はしない。設計ドキュメント参照)。
class RecentDocsWatcher {
    static _RegPath := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs"

    static Enabled := false
    ; ファイル名 -> 対応する.lnkファイルの更新日時(FileGetTimeの戻り値の文字列)のMap。
    ; MRU上位N件を毎回チェックし、このMapに記録した値と比較することで新規/更新を判定する
    ; (docs/spec/recent-docs-watcher.mdの「検知方式」参照。ファイル名だけの比較だと、
    ; ファイルを開いた直後に親フォルダが再登録されてMRU先頭が入れ替わるケースで取りこぼすため、
    ; 上位N件+更新日時ベースの判定に変更した)。
    static _lastSeenTimestamps := Map()
    ; SetTimerの登録/解除には同一のコールバックオブジェクトが必要なため、staticプロパティとして
    ; 1つ保持し、Start/Stopの両方で使い回す(既存のActivityStatus/TcpServer等と同じパターン)。
    static _pollCallback := (*) => RecentDocsWatcher._Poll()

    ; 監視を開始する
    static Start() {
        if RecentDocsWatcher.Enabled {
            return
        }

        ; 起動直後に過去の履歴をまとめて通知しないよう、現時点のMRU上位N件は
        ; 「確認済み」として記録だけ行う(通知はしない)
        RecentDocsWatcher._PrimeSeenEntries()
        RecentDocsWatcher._WarnIfTrackingDisabled()

        SetTimer(RecentDocsWatcher._pollCallback, Settings.RecentDocsPollIntervalMs)
        RecentDocsWatcher.Enabled := true
        Logger.Info("最近使ったファイル監視を開始しました")
    }

    ; 監視を停止する
    static Stop() {
        if !RecentDocsWatcher.Enabled {
            return
        }

        SetTimer(RecentDocsWatcher._pollCallback, 0)
        RecentDocsWatcher.Enabled := false
        Logger.Info("最近使ったファイル監視を停止しました")
    }

    ; 監視のON/OFFを切り替える
    static Toggle() {
        if RecentDocsWatcher.Enabled {
            RecentDocsWatcher.Stop()
        } else {
            RecentDocsWatcher.Start()
        }
    }

    ; ------------------------------------------------------------
    ; 「最近使った項目の記録」設定のチェック・警告(docs/spec/recent-docs-watcher.md参照)
    ; ------------------------------------------------------------

    ; Start()時に1回だけ呼ばれる。設定がOFFと判定した場合、ログと警告TrayTipを出す。
    ; (ポーリングのたびに毎回チェックはしない。実行中に設定が変わった場合の再チェックは未対応)
    static _WarnIfTrackingDisabled() {
        if RecentDocsWatcher._IsTrackingEnabled() {
            return
        }

        Logger.Warn("Windowsの「最近使った項目の記録」がOFFのため、最近使ったファイル監視は機能しません")
        if Settings.RecentDocsWarnIfDisabled {
            FileOpenNotifier.Show(
                "最近使ったファイル通知",
                "Windowsの「最近使った項目の記録」がOFFのため、このファイルオープン通知は機能しません",
                Settings.RecentDocsTrayTipDurationMs)
        }
    }

    ; Start_TrackDocs(個人設定)・NoRecentDocsHistory(ユーザー/マシン単位のポリシー)のいずれかが
    ; OFFを意味していればfalseを返す。値が存在しない項目は既定でON扱いとする
    ; (このマシンでの実際の状態から妥当と判断した既定値。docs/spec/recent-docs-watcher.mdの
    ; 「未決定事項」参照。他のWindows環境でも同じ既定動作かは未確認)。
    static _IsTrackingEnabled() {
        startTrackDocs := RecentDocsWatcher._TryRegRead(
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "Start_TrackDocs")
        if startTrackDocs != "" && Integer(startTrackDocs) = 0 {
            return false
        }

        userPolicy := RecentDocsWatcher._TryRegRead(
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer", "NoRecentDocsHistory")
        if userPolicy != "" && Integer(userPolicy) = 1 {
            return false
        }

        machinePolicy := RecentDocsWatcher._TryRegRead(
            "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer", "NoRecentDocsHistory")
        if machinePolicy != "" && Integer(machinePolicy) = 1 {
            return false
        }

        return true
    }

    ; RegReadを例外なしで試みる。値が存在しない/読み取り失敗の場合は空文字列を返す。
    ; 戻り値は必ず文字列にする(REG_DWORDの0と「値が存在しない」を型の曖昧さ無く比較で区別するため)。
    static _TryRegRead(keyPath, valueName) {
        try {
            return String(RegRead(keyPath, valueName))
        } catch as e {
            Logger.Debug("RegReadに失敗しました(値が存在しない可能性) " keyPath "\" valueName ": " e.Message)
            return ""
        }
    }

    ; ------------------------------------------------------------
    ; ポーリング・検出
    ; ------------------------------------------------------------

    static _Poll(*) {
        try {
            RecentDocsWatcher._CheckForNewEntries()
        } catch as e {
            ; レジストリ構造の想定外の変化等で失敗しても、以降のポーリングは継続する
            Logger.Error("最近使ったファイルの確認に失敗しました: " e.Message)
        }
    }

    ; MRU上位N件(Settings.RecentDocsCheckCount)をそれぞれ確認し、新規/更新があれば通知する。
    static _CheckForNewEntries() {
        for fileName in RecentDocsWatcher._ReadRecentFileNames() {
            RecentDocsWatcher._CheckOneEntry(fileName)
        }
    }

    ; Start()時に呼ばれる。現在のMRU上位N件を「確認済み」として記録するだけで、通知はしない。
    static _PrimeSeenEntries() {
        seen := Map()
        for fileName in RecentDocsWatcher._ReadRecentFileNames() {
            seen[fileName] := RecentDocsWatcher._GetLnkModifiedTime(fileName)
        }
        RecentDocsWatcher._lastSeenTimestamps := seen
    }

    ; 1件のファイル名について、前回確認時から更新されていれば通知する。
    ; フォルダが「開かれた」場合は通知しない(ファイルのみを対象とする。docs/spec/recent-docs-watcher.mdの
    ; 「フォルダの除外」参照)。
    static _CheckOneEntry(fileName) {
        modifiedTime := RecentDocsWatcher._GetLnkModifiedTime(fileName)
        if !RecentDocsWatcher._IsNewOrUpdated(RecentDocsWatcher._lastSeenTimestamps, fileName, modifiedTime) {
            return
        }

        ; フォルダ判定の結果に関わらず「確認済み」として記録する(フォルダを毎回スキップ判定し
        ; 続けるだけの無駄な処理を防ぐため)
        RecentDocsWatcher._lastSeenTimestamps[fileName] := modifiedTime

        fullPath := ""
        try {
            fullPath := RecentDocsWatcher._ResolveFullPath(fileName)
        } catch as e {
            Logger.Error("フルパスの解決に失敗しました: " e.Message)
            Logger.Debug("fileName=" fileName)
        }

        if fullPath != "" && RecentDocsWatcher._IsFolderPath(fullPath) {
            Logger.Debug("フォルダのため通知対象外としました: " fileName " -> " fullPath)
            return
        }

        Logger.Debug("最近使ったファイルの新規/更新エントリを検出しました: " fileName)
        info := RecentDocsWatcher._BuildInfo(fileName, fullPath)
        json := RecentDocsWatcher._BuildJson(info)
        FileOpenNotifier.Show("ファイルが開かれました", json, Settings.RecentDocsTrayTipDurationMs)
    }

    ; pathがフォルダかどうかを判定する(FileExist()が返す属性文字列に"D"が含まれるかで判定)
    static _IsFolderPath(path) {
        return InStr(FileExist(path), "D") > 0
    }

    ; fileNameが新規/更新エントリかどうかを判定する(純粋なロジック。tests/test_recent_docs_watcher.ahk参照)。
    ; - まだ記録が無ければ新規(true)。
    ; - 記録はあるが更新日時が取得できない(.lnkが無い等)場合は、判定できないため既存扱い(false)
    ;   (ファイル名ベースの簡易フォールバック=初回検出時のみ通知される)。
    ; - 記録があり更新日時が取得できる場合は、前回記録した値と異なれば更新とみなす(true)。
    static _IsNewOrUpdated(seenMap, fileName, currentTimestamp) {
        if !seenMap.Has(fileName) {
            return true
        }
        if currentTimestamp = "" {
            return false
        }
        return currentTimestamp != seenMap[fileName]
    }

    ; MRUListExの上位Settings.RecentDocsCheckCount件から、各エントリのファイル名を配列で取得する
    ; (MRUの並び順=最近使った順)。取得・パースに失敗した項目はスキップする。
    static _ReadRecentFileNames() {
        mruHex := RecentDocsWatcher._TryRegRead(RecentDocsWatcher._RegPath, "MRUListEx")
        slots := RecentDocsWatcher._DecodeSlotsFromMruHex(mruHex, Settings.RecentDocsCheckCount)

        fileNames := Array()
        for slot in slots {
            entryHex := RecentDocsWatcher._TryRegRead(RecentDocsWatcher._RegPath, String(slot))
            fileName := RecentDocsWatcher._DecodeFileNameFromEntryHex(entryHex)
            if fileName != "" {
                fileNames.Push(fileName)
            }
        }
        return fileNames
    }

    ; %APPDATA%\Microsoft\Windows\Recent\<fileName>.lnk の更新日時を取得する。
    ; 存在しない/取得失敗の場合は空文字列を返す。
    static _GetLnkModifiedTime(fileName) {
        lnkPath := A_AppData "\Microsoft\Windows\Recent\" fileName ".lnk"
        try {
            if FileExist(lnkPath) {
                return FileGetTime(lnkPath, "M")
            }
        } catch as e {
            Logger.Debug("lnkの更新日時取得に失敗しました fileName=" fileName ": " e.Message)
        }
        return ""
    }

    ; ------------------------------------------------------------
    ; レジストリバイナリのパース(純粋なロジック。tests/test_recent_docs_watcher.ahk参照)
    ; ------------------------------------------------------------

    ; MRUListEx(RegReadが返す16進文字列)の先頭から、最大maxCount件のスロット番号を
    ; リトルエンディアンの整数として並び順(最近使った順)のまま配列で取り出す。
    ; 0xFFFFFFFF(終端)に達するか、maxCount件に達したら打ち切る。
    static _DecodeSlotsFromMruHex(mruHex, maxCount) {
        slots := Array()
        if mruHex = "" || StrLen(mruHex) < 8 {
            return slots
        }

        buf := RecentDocsWatcher._HexToBuffer(mruHex)
        availableSlots := Min(maxCount, buf.Size // 4)
        loop availableSlots {
            offset := (A_Index - 1) * 4
            slot := NumGet(buf, offset, "UInt")
            if slot = 0xFFFFFFFF {
                break
            }
            slots.Push(slot)
        }
        return slots
    }

    ; エントリの16進文字列(REG_BINARY)先頭にあるUTF-16null終端文字列(ファイル名)を取り出す。
    ; 末尾に付随するシェルのアイテムID列(PIDL)部分は無視する。
    static _DecodeFileNameFromEntryHex(entryHex) {
        if entryHex = "" {
            return ""
        }
        buf := RecentDocsWatcher._HexToBuffer(entryHex)
        ; Lengthを明示してバッファ境界を超えて読まないようにする(万一null終端が無い異常データの場合の保険)
        return StrGet(buf, buf.Size // 2, "UTF-16")
    }

    ; RegReadが返す16進文字列(2文字=1byte、区切り無し)をバイト列のBufferに変換する
    static _HexToBuffer(hexStr) {
        byteCount := StrLen(hexStr) // 2
        buf := Buffer(byteCount, 0)
        loop byteCount {
            offset := (A_Index - 1) * 2 + 1
            NumPut("UChar", Integer("0x" SubStr(hexStr, offset, 2)), buf, A_Index - 1)
        }
        return buf
    }

    ; ------------------------------------------------------------
    ; ファイル情報の組み立て・フルパス解決
    ; ------------------------------------------------------------

    ; ファイル名と(呼び出し元で解決済みの)フルパスから表示用の情報一式(Map)を組み立てる
    ; (表示用JSONの元データ)。フルパスの解決自体は呼び出し元(_CheckOneEntry)が行う
    ; (フォルダ判定にも同じ解決結果を使い回すため。純粋な組み立てだけのロジックにすることで
    ; 実ファイル・COM無しに単体テストできるようにする。tests/test_recent_docs_watcher.ahk参照)。
    static _BuildInfo(fileName, fullPath) {
        extension := ""
        SplitPath(fileName, , , &extension)

        pathResolved := fullPath != ""
        return Map(
            "fileName", fileName,
            "path", fullPath,
            "pathResolved", pathResolved,
            "extension", extension
        )
    }

    ; %APPDATA%\Microsoft\Windows\Recent\<fileName>.lnk 経由でフルパスを解決する
    ; (docs/spec/recent-docs-watcher.mdの「フルパス解決」参照)。解決できなければ空文字列を返す。
    static _ResolveFullPath(fileName) {
        lnkPath := A_AppData "\Microsoft\Windows\Recent\" fileName ".lnk"
        if !FileExist(lnkPath) {
            return ""
        }

        shell := ComObject("WScript.Shell")
        targetPath := shell.CreateShortcut(lnkPath).TargetPath
        if targetPath != "" && FileExist(targetPath) {
            return targetPath
        }
        return ""
    }

    ; 検出結果のMap(_BuildInfoの戻り値と同じ形)をTrayTip表示用のJSON文字列に変換する。
    ; OfficeFileWatcher/PdfFileWatcherが使うlib/FileOpenNotifier.BuildJsonは"process"情報を
    ; 前提とした形のため使わず、本機能専用の軽量な形をここで組み立てる。
    static _BuildJson(info) {
        payload := Map(
            "fileName", info["fileName"],
            "path", info["path"],
            "pathResolved", Json.Bool(info["pathResolved"]),
            "extension", info["extension"]
        )
        return Json.Stringify(payload)
    }
}
