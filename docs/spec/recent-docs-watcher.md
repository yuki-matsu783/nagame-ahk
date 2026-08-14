# 最近使ったファイル監視・通知（RecentDocsWatcher）

## 背景・目的

[docs/spec/office-file-watcher.md](office-file-watcher.md) / [docs/spec/pdf-file-watcher.md](pdf-file-watcher.md)
のfilewatcher一式は、対象アプリのプロセス名を事前に`Settings`へ登録する方式のため、新しいファイル種別
（画像・テキスト・動画など）に対応するたびにプロセス名の調査・登録が必要になる。

そこで、ファイル種別・アプリを問わず「何らかのファイルが開かれたこと」を軽量に通知する、**既存の
filewatcher一式とは独立した別機能**を追加する。Windowsのシェルが管理する「最近使ったファイル」の
記録（レジストリの`RecentDocs`）を監視し、新しいエントリが増えたらTrayTipで通知する。

体験イメージ: 何らかのファイルが開かれると、本機能が「ファイルが開かれました: xxx」という軽量な
TrayTipを出す。もしそれがOffice/PDFファイルであれば、既存のfilewatcherが独立に反応し、従来通り
プロセス情報等を含む詳細なTrayTipも別途表示される（本機能から既存filewatcherを呼び出す等の連携はしない）。

## 仕様

### 監視対象

`HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs`

Windowsのタスクバー ジャンプリストやエクスプローラーの「クイックアクセス」に表示される「最近使った
ファイル」の実体。拡張子別のサブキー（`RecentDocs\.pdf`等）ではなく、**全種別が集約されたルートキー**
を見ることで、ファイル種別を問わず汎用的に拾う。

このキーは、エクスプローラーでのダブルクリックや`ShellExecute`(既定の「開く」動作)経由でファイルが
開かれた際に、Windowsのシェルによって自動的に更新される（`SHAddToRecentDocs`相当の処理）。

### レジストリ構造とパース方針

RecentDocsは、Windowsの他の「\*MRU」系レジストリキー（`RunMRU`等）と同じ、一般的なMRU
（Most Recently Used）リスト形式を採る。

- `MRUListEx`（`REG_BINARY`）: 4byte(DWORD, リトルエンディアン)ずつの配列。各DWORDは
  「最近使った順」に並んだエントリのスロット番号（後述の値名に対応する数値）を表し、`0xFFFFFFFF`で終端する。
  つまり**先頭4byteが「最新のスロット番号」**になる。
- 番号名の値（例: 値名`"18"`、`REG_BINARY`）: 各エントリの実データ。先頭にUTF-16(LE)のnull終端文字列で
  **ファイル名**が入っており、それに続けてシェルのアイテムID列（PIDL、フルパス解決やアイコン取得に
  使われるバイナリ構造）が付随する。

実装方針:
1. `MRUListEx`の先頭4byteから最新スロット番号を取得する。
2. そのスロット番号を10進文字列化した値名（例: `"18"`）の`REG_BINARY`を読む。
3. 値の先頭からUTF-16null終端文字列を読み取り、**ファイル名**として採用する
   （AHKの`StrGet(ptr, "UTF-16")`はnull終端で自動的に読み止まるため、この部分の抽出は単純な処理で済む）。
4. フルパスは、下記「フルパス解決」の手順で別途解決を試みる。解決できなければファイル名のみで表示する
   （Office/PDF watcherと同じ、取得できる範囲でベストエフォート表示するフォールバック方針）。

このキーの構造自体はサードパーティアプリ不要でこのマシン上でも直接確認できるため、設計時点で
実際のレジストリ値をPowerShellで読んで上記の想定を検証済み: 値名は10進数の文字列（例:
`"61"`）、`MRUListEx`の先頭4byteは`3D-00-00-00`(リトルエンディアンで61)で対応する値名と一致、
値`"61"`のバイナリは`70-00-6C-00-61-00-6E-00-73-00-00-00-...`(UTF-16LEで`p-l-a-n-s`+null終端)で
始まり、ファイル名`"plans"`を正しく抽出できることを確認した。

### フルパス解決（Recentフォルダのショートカット経由）

`RecentDocs`のバイナリ末尾にあるシェルのアイテムID列(PIDL)を自前でパースする方式は、構造が複雑かつ
バージョン依存なため採用しない。代わりに、**Windowsが同時に作成している`.lnk`ショートカットファイル**
を経由してフルパスを解決する。

- `SHAddToRecentDocs`は、`RecentDocs`レジストリの更新と同時に、`%APPDATA%\Microsoft\Windows\Recent\`
  フォルダへ**同名の`.lnk`ファイル**（例: `見積書_v2.xlsx.lnk`）を作成/更新する。このフォルダは
  タスクバーのジャンプリスト等が参照する標準フォルダで、`.lnk`は通常のショートカットファイルなので
  `WScript.Shell`の`CreateShortcut().TargetPath`で素直にターゲットパスを取得できる。
- 手順:
  1. 抽出した`fileName`から候補パス`A_AppData "\Microsoft\Windows\Recent\" fileName ".lnk"`を組み立てる。
  2. `FileExist()`で存在確認する。無ければ未解決としてファイル名のみで表示する。
  3. 存在すれば`ComObject("WScript.Shell")`の`CreateShortcut(lnkPath).TargetPath`でターゲットパスを取得する。
  4. 取得したパスが空文字でなく`FileExist()`で実在確認できれば、そのパスをフルパスとして採用する。
     空文字（UWPアプリのエントリ等、ファイルシステム外を指す一部のショートカットで起こりうる）や
     取得失敗の場合はファイル名のみの表示にフォールバックする。
- このマシンで実際に検証済み: `plans`というフォルダを開いた際、`%APPDATA%\Microsoft\Windows\Recent\
  plans.lnk`が存在し、`TargetPath`が実際のフルパス`C:\Users\taniyama\.claude\plans`を返すことを確認した。
  同様にテスト用の`.txt`ファイルでも`ファイル名.lnk`→正しいフルパスの解決を確認した。

### 検知方式

- `SetTimer`による**ポーリング**を採用する（`Settings.RecentDocsPollIntervalMs`、既定2000ms）。
  `RegNotifyChangeKeyValue`による非同期通知も検討したが、[src/lib/TcpServer.ahk](../src/lib/TcpServer.ahk)
  冒頭のコメントに残る「イベント駆動方式を試したが原因不明の不具合に遭遇し、実績のあるポーリング方式に
  戻した」という過去の教訓に倣い、実装・保守が容易なポーリングを採用する。
- 毎回のポーリングで上記の手順に沿って「最新エントリのファイル名」を読み取り、前回ポーリング時に
  最後に通知した内容と比較する。異なっていれば新規オープンとして通知する
  （スロット番号は使い回されることがあるため、番号ではなく**読み取ったファイル名の変化**で判定する）。
- 同じファイルを再度開いて最新エントリに返り咲いた場合も、ファイル名の変化として検知され再通知される
  （Office/PDF watcherの「同じファイルを閉じて再度開くと毎回通知される」という既存の挙動と揃える）。

### 表示内容（TrayTip / JSON）

[src/lib/FileOpenNotifier.ahk](../src/lib/FileOpenNotifier.ahk)の`Show(title, json, durationMs)`
（TrayTip表示＋自動消去）は流用するが、`BuildJson`（`process`情報を前提としたOffice/PDF用の形）は
使わない。RecentDocsからは開いたプロセスの情報が原理的に取得できないため、本機能専用の軽量な
JSONをその場で組み立てる。

- タイトル: `"ファイルが開かれました"`（Office/PDF側の「Officeファイルが開かれました」
  「PDFファイルが開かれました」と見分けが付く文言にする）
- 本文（JSON）例(フルパス解決に成功した場合):

```json
{"fileName":"見積書_v2.xlsx","path":"C:\\Users\\taniyama\\Documents\\見積書_v2.xlsx","pathResolved":true,"extension":"xlsx"}
```

  解決できなかった場合は`path`が空文字列、`pathResolved`が`false`になる（フォールバック表示）。
- `extension`はファイル名から`SplitPath`で取り出した拡張子（小文字化はしない。取得できなければ空文字列）。
- `Settings.RecentDocsTrayTipDurationMs`（既定5000ms）後に自動で消す。

### 「最近使った項目の記録」設定の確認と通知

本機能はWindowsの「最近使った項目の記録」機能に完全に依存するため、この設定がOFFの環境では
黙って何も検知できないままになってしまう。ユーザーが原因に気づけるよう、`Start()`時に設定を
チェックし、OFFと判定した場合は起動時に1回だけ警告のTrayTipを表示する。

- チェックする項目（いずれか1つでも「OFF」を意味する値であれば無効と判定する）:
  - `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` の `Start_TrackDocs`
    （`REG_DWORD`。個人設定「スタートまたはタスクバーのジャンプリストに最近開いた項目を表示する」の実体。
    `0`ならOFF。**値が存在しない場合は既定でON扱い**とする ―― このマシンでは値が存在せず、実際に
    RecentDocsへの記録は機能している状態だったため、「未設定=ON」という扱いで実機の挙動と一致することを
    確認済み）
  - `HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer` の `NoRecentDocsHistory`
    （`REG_DWORD`。ユーザー単位のグループポリシー。`1`ならOFF。値が存在しなければON扱い）
  - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer` の `NoRecentDocsHistory`
    （同上のマシン単位のグループポリシー。`1`ならOFF。値が存在しなければON扱い。このマシンでは
    このキー・値自体は存在し`0`（＝制限なし）だったことを確認済み）
- 判定・通知は`Start()`が呼ばれた時点の1回のみ行う（ポーリングのたびに毎回チェックはしない）。
  アプリ実行中にユーザーが設定を変更した場合に追従するかは「未決定事項」を参照。
- OFFと判定した場合:
  - `Logger.Warn`でログに残す。
  - `FileOpenNotifier.Show`を使い、タイトル「最近使ったファイル通知」・本文にJSONではなく
    「Windowsの「最近使った項目の記録」がOFFのため、このファイルオープン通知は機能しません」旨の
    説明文を表示する（`Settings.RecentDocsTrayTipDurationMs`後に自動で消える点は他の通知と同じ）。
  - この警告表示の有無は`Settings.RecentDocsWarnIfDisabled`（既定`true`）で無効化できるようにする
    （意図的にOFFにして使っている場合に毎起動で警告されるのを防げるように）。
  - 警告を表示した場合でも、ポーリング自体は通常通り開始する（設定はユーザーがいつでも変更しうるため、
    アプリを再起動しなくても後から有効化されれば自動的に検知できるようにする）。

### 操作方法

- アプリ起動時に`Settings.RecentDocsWatchAutoStart`（既定`true`）が`true`であれば自動的に監視を開始する
  （`App.Start()`から`RecentDocsWatcher.Start()`を呼び出し）。
- トレイメニュー「最近使ったファイル通知」からON/OFFを切り替え可能。チェック状態は
  `RecentDocsWatcher.Enabled`と同期する（`TrayMenu.SyncRecentDocsWatchCheck`、既存2機能と同様のパターン）。
- 専用ホットキーは設けない（自動検出のため、既存2機能と同様）。

## 影響範囲

- 追加: `src/features/RecentDocsWatcher.ahk`（レジストリのポーリング・パース・通知、
  `WScript.Shell`(COM)経由の`.lnk`ターゲットパス解決、「最近使った項目の記録」設定のチェックを行う。
  `WindowOpenWatcher`には依存しない独立機能）
- 変更: `src/config/Settings.ahk`（`RecentDocsPollIntervalMs` / `RecentDocsWatchAutoStart` /
  `RecentDocsTrayTipDurationMs` / `RecentDocsWarnIfDisabled` 追加）
- 変更: `src/core/App.ahk`（起動時に`RecentDocsWatcher.Start()`呼び出し）
- 変更: `src/core/TrayMenu.ahk`（メニュー項目「最近使ったファイル通知」・チェック同期メソッド追加）
- 変更: `src/main.ahk`（`#Include features\RecentDocsWatcher.ahk`追加。既存の`OfficeFileWatcher.ahk`/
  `PdfFileWatcher.ahk`と並列に配置し、依存関係は持たせない）

## 設定項目

| 設定値 | 既定値 | 説明 |
|---|---|---|
| `Settings.RecentDocsPollIntervalMs` | `2000` | RecentDocsのポーリング間隔(ms) |
| `Settings.RecentDocsWatchAutoStart` | `true` | アプリ起動時に自動的に監視を開始するか |
| `Settings.RecentDocsTrayTipDurationMs` | `5000` | TrayTip（JSON表示）を明示的に消すまでの時間(ms) |
| `Settings.RecentDocsWarnIfDisabled` | `true` | 「最近使った項目の記録」がOFFの場合に起動時警告TrayTipを出すか |

## 未決定事項・懸念点

- **Windowsの「最近使った項目の記録」設定に完全に依存する。** 個人設定やグループポリシーでOFFに
  されている環境では本機能は一切機能しない（既存2機能のようなOS標準の常時有効な仕組みとは異なる、
  既知の重要な制約）。起動時に検知して警告TrayTipを出す方針にはしたが、警告が出た場合にユーザー
  自身が設定を変更しない限り機能しない点は変わらない。
- `Start_TrackDocs`の「値が存在しない場合はON扱い」という判定は、このマシンでの実際の状態
  （値が存在せず、かつ実際にRecentDocsへの記録が機能していた）から妥当と判断したものであり、
  他のWindowsバージョン/エディションでも同じ既定動作かは未確認。
- 設定チェックは`Start()`時の1回のみで、実行中に設定が変更された場合の再チェックは行わない
  （ポーリングでのファイルオープン検知自体は設定が後から有効化されれば自動的に追従するが、
  「OFFです」という警告が古いまま残る可能性がある）。必要なら定期的な再チェックを別途検討する。
- **ブラウザでダウンロードしたファイルが自動的に開かれるケースの挙動は未検証。** `ShellExecuteEx`
  経由であれば記録される可能性が高いが、ブラウザの実装・バージョンによっては記録されないことがある。
  実装後に実機（Edge/Chrome等）で確認し、結果をこの節に追記する。
- アプリが`SHAddToRecentDocs`相当を自ら呼ばない場合は記録されない（主要アプリは通常呼ぶが、
  簡易・古いアプリは記録されない可能性がある）。
- フルパス解決は`%APPDATA%\Microsoft\Windows\Recent\`内の同名`.lnk`ファイルに依存する。この
  フォルダの内容は一定件数を超えると古いものから自動整理される可能性があり、`.lnk`が既に無い/
  RecentDocsの方が先に更新されている等のタイミング差で解決に失敗する場合がある
  （その場合はファイル名のみのフォールバック表示になる）。
- 本機能と既存filewatcher(Office/PDF)は連携しないため、Office/PDFファイルを開くと2つの独立した
  TrayTipが表示される（意図した仕様として許容する）。
- TrayTipの表示・上書きに関する懸念（[docs/spec/office-file-watcher.md](office-file-watcher.md)の該当節参照）
  は本機能にも同様に当てはまる。
