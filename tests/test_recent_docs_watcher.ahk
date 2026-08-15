#Requires AutoHotkey v2.0
#SingleInstance Force

; 設計: docs/spec/recent-docs-watcher.md
; features/RecentDocsWatcher.ahk のうち、実レジストリ・COMを使わずに検証できる純粋なロジック
; (RegReadの16進文字列から上位スロット/ファイル名を取り出すバイナリパース、新規/更新判定、JSON整形)
; の単体テスト。GUIを開かず、アサーション結果を標準出力してExitApp()する。
; 実行例: AutoHotkey64.exe tests\test_recent_docs_watcher.ahk
;
; 対象外(このテストではカバーしない。tests/README.md の「対象外」節も参照):
; - 実際のRecentDocsレジストリのポーリング(Start()は呼ばない)
; - WScript.Shell(COM)経由の.lnkターゲットパス解決、FileGetTimeによる実際の更新日時取得
; - 「最近使った項目の記録」設定の実読み取り(_IsTrackingEnabled。マシンごとに状態が異なるため)
; - TrayTipの実表示
#Include ..\src\config\Settings.ahk
#Include ..\src\lib\Logger.ahk
#Include ..\src\lib\Json.ahk
#Include ..\src\lib\FileOpenNotifier.ahk
#Include ..\src\features\RecentDocsWatcher.ahk
#Include lib\Assert.ahk

failures := 0
passed := 0

; ---- _DecodeSlotsFromMruHex: MRUListExの16進文字列 -> 上位スロット番号の配列 ----
; スロット1,2,3 + 終端(0xFFFFFFFF)。DWORDはリトルエンディアン
mruHex3 := "010000000200000003000000FFFFFFFF"
slots := RecentDocsWatcher._DecodeSlotsFromMruHex(mruHex3, 5)
Assert(slots.Length, 3, "maxCountが十分大きければ終端までの全スロットを取得できる")
Assert(slots[1], 1, "1件目のスロット番号")
Assert(slots[2], 2, "2件目のスロット番号")
Assert(slots[3], 3, "3件目のスロット番号")

slotsLimited := RecentDocsWatcher._DecodeSlotsFromMruHex(mruHex3, 2)
Assert(slotsLimited.Length, 2, "maxCountで打ち切られる")
Assert(slotsLimited[2], 2, "打ち切り時も並び順は維持される")

; "3D000000..." はこのマシンの実レジストリで実際に観測した値(設計ドキュメント参照。リトルエンディアンで61)
slotsReal := RecentDocsWatcher._DecodeSlotsFromMruHex("3D000000FFFFFFFF", 5)
Assert(slotsReal.Length, 1, "実機で観測した値を正しくデコードできる(件数)")
Assert(slotsReal[1], 61, "実機で観測した値を正しくデコードできる(値=0x3D=61)")

Assert(RecentDocsWatcher._DecodeSlotsFromMruHex("", 5).Length, 0, "空文字列は空配列を返す")
Assert(RecentDocsWatcher._DecodeSlotsFromMruHex("3D", 5).Length, 0, "4byte未満(短すぎる)場合は空配列を返す")
Assert(RecentDocsWatcher._DecodeSlotsFromMruHex("FFFFFFFF", 5).Length, 0, "先頭が終端(リスト空)なら空配列を返す")

; ---- _DecodeFileNameFromEntryHex: エントリの16進文字列 -> ファイル名 ----
; "70006C0061006E0073000000" はこのマシンの実レジストリで実際に観測した"plans"エントリの
; 先頭部分(p,l,a,n,s,null)の16進表現(設計ドキュメント参照)
Assert(RecentDocsWatcher._DecodeFileNameFromEntryHex("70006C0061006E0073000000"), "plans", "実機で観測したバイナリから'plans'を正しく抽出できる")
; null終端後に付随するPIDL相当のダミーバイトが続いていても、null以降は無視されること
Assert(RecentDocsWatcher._DecodeFileNameFromEntryHex("610062000000" "5C003200"), "ab", "null終端後のPIDL相当のダミーバイトは無視される")
Assert(RecentDocsWatcher._DecodeFileNameFromEntryHex(""), "", "空文字列は空文字列を返す")

; ---- _IsNewOrUpdated: 新規/更新判定の純粋ロジック ----
emptySeen := Map()
Assert(RecentDocsWatcher._IsNewOrUpdated(emptySeen, "a.txt", "20260815090000"), true, "未記録のファイル名は新規として扱う")

seenWithTimestamp := Map("a.txt", "20260815090000")
Assert(RecentDocsWatcher._IsNewOrUpdated(seenWithTimestamp, "a.txt", "20260815090000"), false, "更新日時が前回と同じなら変化なし")
Assert(RecentDocsWatcher._IsNewOrUpdated(seenWithTimestamp, "a.txt", "20260815100000"), true, "更新日時が前回と異なれば更新とみなす(同じファイル名の再オープンを検知できる)")

seenWithoutTimestamp := Map("b.txt", "")
Assert(RecentDocsWatcher._IsNewOrUpdated(seenWithoutTimestamp, "b.txt", ""), false, ".lnkが無く更新日時が取れない場合、既に記録済みのファイル名は再通知しない(既知のフォールバック)")

; ---- _BuildJson: 検出結果のMap -> JSON文字列 ----
infoResolved := Map("fileName", "見積書_v2.xlsx", "path", "C:\Users\taniyama\Documents\見積書_v2.xlsx", "pathResolved", true, "extension", "xlsx")
jsonResolved := RecentDocsWatcher._BuildJson(infoResolved)
parsedResolved := Json.Parse(jsonResolved)
Assert(parsedResolved["fileName"], "見積書_v2.xlsx", "JSON: fileName")
Assert(parsedResolved["path"], "C:\Users\taniyama\Documents\見積書_v2.xlsx", "JSON: path")
Assert(parsedResolved["pathResolved"], 1, "JSON: pathResolved(true)はJSONのtrue(パース後は1)")
Assert(parsedResolved["extension"], "xlsx", "JSON: extension")

infoFallback := Map("fileName", "readme.txt", "path", "", "pathResolved", false, "extension", "txt")
jsonFallback := RecentDocsWatcher._BuildJson(infoFallback)
parsedFallback := Json.Parse(jsonFallback)
Assert(parsedFallback["path"], "", "JSON: パス未解決時はpathが空文字")
Assert(parsedFallback["pathResolved"], 0, "JSON: パス未解決時はpathResolvedがfalse(パース後は0)")

; ---- _BuildInfo: フルパスは呼び出し元(_CheckOneEntry)から渡される純粋な組み立てロジック ----
infoNotFound := RecentDocsWatcher._BuildInfo("test-nonexistent-xyz.pdf", "")
Assert(infoNotFound["fileName"], "test-nonexistent-xyz.pdf", "_BuildInfo: fileNameはそのまま保持される")
Assert(infoNotFound["pathResolved"], false, "_BuildInfo: フルパスが空文字ならpathResolvedはfalse")
Assert(infoNotFound["path"], "", "_BuildInfo: フルパスが空文字ならpathも空文字")
Assert(infoNotFound["extension"], "pdf", "_BuildInfo: 拡張子はSplitPathで正しく取り出される")

infoWithPath := RecentDocsWatcher._BuildInfo("report.pdf", "C:\Users\taniyama\Documents\report.pdf")
Assert(infoWithPath["pathResolved"], true, "_BuildInfo: フルパスがあればpathResolvedはtrue")
Assert(infoWithPath["path"], "C:\Users\taniyama\Documents\report.pdf", "_BuildInfo: フルパスがそのまま保持される")

; ---- _IsFolderPath: フォルダ判定(ファイルのみを通知対象とするためのフィルタ) ----
; マシン環境に依存しない安定した既知パスで検証する
; (A_WinDirは必ずフォルダ、A_AhkPathは実行中のexeで必ずファイルとして存在する)
Assert(RecentDocsWatcher._IsFolderPath(A_WinDir), true, "既知のフォルダ(A_WinDir)はフォルダと判定される")
Assert(RecentDocsWatcher._IsFolderPath(A_AhkPath), false, "既知のファイル(A_AhkPath)はフォルダと判定されない")
Assert(RecentDocsWatcher._IsFolderPath("C:\this-path-should-not-exist-xyz123"), false, "存在しないパスはフォルダと判定されない")

FileAppend("passed=" passed " failures=" failures "`n", "*")
ExitApp(failures = 0 ? 0 : 1)
