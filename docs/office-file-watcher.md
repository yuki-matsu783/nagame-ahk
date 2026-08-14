# MS Officeファイル監視・情報表示（OfficeFileWatcher）

## 背景・目的

Word / Excel / PowerPoint / Visio でファイルが開かれた際に、そのファイル名・保存先パスと、
ファイルを開いているプロセスの情報をすぐに確認できるようにする。
誤って想定と異なるファイルを開いてしまった場合の早期発見や、ネットワークドライブ上のファイルパスを
すぐに確認したい場面を想定している。

## 仕様

### 検出方法

- `SetWinEventHook`（user32.dll）によるイベント駆動検出とする。ポーリング方式（`SetTimer`で定期的に
  `WinGetList()`を取得して差分を見る）も検討したが、検出の即時性・CPU負荷の両面で `SetWinEventHook` を
  採用する。
- [docs/pdf-file-watcher.md](pdf-file-watcher.md) でPDFファイルにも同じ検出方式を使う機能を追加する際に、
  この節で説明する検出ロジック（フックの設置/解除、対象プロセス名でのフィルタ、通知済みhwndの重複排除）は
  `src/lib/WindowOpenWatcher.ahk` に汎用クラスとして切り出した（`src/lib/TcpServer.ahk`と
  `src/core/ExternalCommandServer.ahk`の役割分担と同じ考え方）。`OfficeFileWatcher`は
  `WindowOpenWatcher(Settings.OfficeProcessNames, onWindowShown)` のインスタンスを1つ保持し、
  `Start`/`Stop`/`Toggle`を委譲する。
  - `SetWinEventHook`のコールバックにはコンテキスト引数が無く、Office監視・PDF監視を独立したフックとして
    同時に動かすにはフックごとに別々の状態（対象プロセス名・通知済みhwnd集合・フックハンドル）が要るため、
    `WindowOpenWatcher`は本プロジェクトで初めての**インスタンス化可能なクラス**にした
    （他のクラスは全てstaticのみで運用している点からの意図的な逸脱）。
- `EVENT_OBJECT_SHOW`(0x8002) をフックする。コールバックでは以下の条件を満たすイベントのみ処理する。
  - `idObject == OBJID_WINDOW`(0) かつ `idChild == CHILDID_SELF`(0)（コントロール単位のイベントを除外し、
    ウィンドウそのものの表示イベントのみ扱うため）
  - `WinGetProcessName(hwnd)` がコンストラクタに渡した対象プロセス名配列（`OfficeFileWatcher`の場合は
    `Settings.OfficeProcessNames` = `WINWORD.EXE` / `EXCEL.EXE` / `POWERPNT.EXE` / `VISIO.EXE`）のいずれかに一致する
- 同一hwndに対して複数回イベントが飛んでくることがある（最小化からの復元時等）ため、通知済みhwndの集合
  （`_notifiedHwnds`）を保持し、初回検出時のみ通知する。ウィンドウが閉じられたら集合から取り除く
  （`EVENT_OBJECT_DESTROY` も合わせてフックする）。
  - 実装時の注意: `EVENT_OBJECT_DESTROY`は監視対象外のウィンドウも含め全hwndで飛んでくるため、
    追跡していないhwndの方が多い。`Map.Delete()`は未登録キーだと例外になるため、`Has()`で存在確認して
    から削除する（実機での動作確認時に遭遇した不具合。詳細はコード中のコメント参照）。
- フックは `WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS` で登録する。`OUTOFCONTEXT`により、
  コールバックはフック設置元スレッド（AHKのメインスレッド）のメッセージキュー経由で呼ばれるため、
  コールバック内でCOM呼び出しなど時間のかかる処理を直接行っても安全（別スレッドへの割り込みではない）。
- コールバックは`DllCall`に渡すため`CallbackCreate()`で作成する。`SetTimer`の既存パターン
  （[docs/activity-status.md](activity-status.md)）と同様、GC対策と`UnhookWinEvent`時の一貫性のため、
  作成したコールバックはインスタンスプロパティとして1つ保持し使い回す。
- 監視終了時（`Stop()`）は `UnhookWinEvent` でフックを解除する。

### ファイル情報の取得（hwnd→ドキュメントの対応付け）

- `AccessibleObjectFromWindow`（oleacc.dll）を `dwId = OBJID_NATIVEOM`(-16) で呼び出し、検出対象の
  hwndから**直接そのウィンドウに紐づくオートメーションオブジェクト（IDispatch）を取得する**。
  - Documents/Workbooks/Presentationsコレクションを列挙して`.Hwnd`が一致する要素を探す方式は、
    複数ウィンドウ・複数インスタンスがある場合に対応付けを誤る可能性があったため採用しない。
    `AccessibleObjectFromWindow`は問い合わせたhwndに一意に対応するオブジェクトを直接返すため、
    この曖昧性が生じない。
  - Word: 返るオブジェクトはWindow相当 → `.Document.FullName` でパス取得
  - Excel: `.Parent.FullName`（Excelの`Window.Parent`はWorkbook）
  - PowerPoint: `.Presentation.FullName`
  - Visio: 同様の手順を想定するが、`OBJID_NATIVEOM`をサポートしているか未確認のため実装時に確認する
    （未決定事項参照）。
- 取得失敗時（`DllCall`失敗、COM例外等）は`try/catch`で捕捉し`Logger.Error`に記録した上で、
  ウィンドウタイトルのみのフォールバック表示に切り替える（処理は継続し、フック自体は止めない）。

### プロセス情報の取得

- ファイルパスに加えて、ファイルを開いているプロセスの情報も表示する。
  - プロセス名: `WinGetProcessName(hwnd)`（既存の検出条件で取得済みの値を再利用）
  - プロセスID: `WinGetPID(hwnd)`
  - 実行ファイルのフルパス: `WinGetProcessPath(hwnd)`

### TrayTip表示内容（JSON）

`MsgBox`はモーダルでスレッドをブロックするため使用しない。代わりに`TrayTip`（`lib/Json.ahk`の
`Json.Stringify`を使ってJSON文字列化した本文）で表示する。JSON整形とTrayTip表示・自動消去のロジックも
検出方法と同様の理由でPDF監視と共用するため `src/lib/FileOpenNotifier.ahk` に切り出した
（`FileOpenNotifier.BuildJson(info)` / `FileOpenNotifier.Show(title, json, durationMs)`）。
`OfficeFileWatcher`は検出時コールバックで`_CollectFileInfo`の結果をこの2つに渡すだけになる。

- タイトル: `"Officeファイルが開かれました"`
- 本文: 検出結果を`Map`にまとめて`Json.Stringify`した1行のJSON文字列。例:

```json
{"type":"Word","fileName":"議事録.docx","path":"C:\\Users\\...\\議事録.docx","pathResolved":true,"windowTitle":"議事録.docx - Word","process":{"name":"WINWORD.EXE","pid":12345,"path":"C:\\Program Files\\Microsoft Office\\root\\Office16\\WINWORD.EXE"}}
```

- `type`: プロセス名から Word / Excel / PowerPoint / Visio に変換した値。
- `path` / `pathResolved`: パスが取得できた場合は`path`にフルパス・`pathResolved`は`true`。
  取得できなかった場合は`path`は空文字列・`pathResolved`は`false`とし、`windowTitle`（フォールバック用の
  ウィンドウタイトル）で代替情報を確認できるようにする。
- `process`: プロセス名・プロセスID・実行ファイルのフルパスをまとめたオブジェクト。
- `TrayTip(text, title)`呼び出し後、`Settings.OfficeWatchTrayTipDurationMs`（既定5000ms）経過後に
  `TrayTip()`（引数無し呼び出し）で明示的に消す（`NotifyUI.ShowToast`と同じ理由：TrayTipはOSによって
  自動で消えないことがあるため）。

### 操作方法

- アプリ起動時に `Settings.OfficeWatchAutoStart`（既定 `true`）が `true` であれば自動的に監視を開始する
  （`App.Start()` から `OfficeFileWatcher.Start()` を呼び出し）。
- トレイメニュー「Office監視」からON/OFFを切り替え可能。チェック状態は `OfficeFileWatcher.Enabled` と
  同期する（`TrayMenu.SyncOfficeWatchCheck`、`ActivityStatus`と同様のパターン）。
- 専用ホットキーは設けない（自動検出のため）。

## 影響範囲

- 追加: `src/lib/WindowOpenWatcher.ahk`（`SetWinEventHook`の設置・解除、対象プロセス名でのフィルタ、
  hwnd重複排除を行う汎用クラス。PDF監視（[docs/pdf-file-watcher.md](pdf-file-watcher.md)）と共用）
- 追加: `src/lib/FileOpenNotifier.ahk`（検出結果のJSON整形・TrayTip表示・自動消去を行う汎用クラス。
  こちらもPDF監視と共用）
- 追加: `src/features/OfficeFileWatcher.ahk`（`WindowOpenWatcher`のインスタンスを保持し、
  `AccessibleObjectFromWindow`呼び出しによるOffice/Visio固有のファイルパス解決を行う。
  `lib/Json.ahk`は`main.ahk`で既に`features`より前に`#Include`済みのため新規includeは不要）
- 変更: `src/config/Settings.ahk`（`OfficeProcessNames` / `OfficeWatchAutoStart` /
  `OfficeWatchTrayTipDurationMs` 追加。`EVENT_OBJECT_SHOW`等のWinAPI定数はユーザー設定ではないため
  `Settings`には入れず、`WindowOpenWatcher`クラス内のstaticプロパティとして定義する。
  `TcpServer`のWinsock定数と同じ方針）
- 変更: `src/core/App.ahk`（起動時に `OfficeFileWatcher.Start()` 呼び出し）
- 変更: `src/core/TrayMenu.ahk`（メニュー項目「Office監視」・チェック同期メソッド追加）
- 変更: `src/main.ahk`（`#Include`順序に沿って`lib\WindowOpenWatcher.ahk` / `lib\FileOpenNotifier.ahk` /
  `features\OfficeFileWatcher.ahk` を追加）

## 設定項目

| 設定値 | 既定値 | 説明 |
|---|---|---|
| `Settings.OfficeProcessNames` | `Array("WINWORD.EXE", "EXCEL.EXE", "POWERPNT.EXE", "VISIO.EXE")` | 監視対象のOfficeプロセス名 |
| `Settings.OfficeWatchAutoStart` | `true` | アプリ起動時に自動的に監視を開始するか |
| `Settings.OfficeWatchTrayTipDurationMs` | `5000` | TrayTip（JSON表示）を明示的に消すまでの時間(ms) |

## 未決定事項・懸念点

- Visioが `AccessibleObjectFromWindow` + `OBJID_NATIVEOM` をサポートしているか未確認。サポートされていない
  場合はタイトルのみのフォールバック表示になる（実装時に実機で検証する）。
- `EVENT_OBJECT_SHOW` は最小化からの復元時にも発火しうるため、通知済みhwnd管理と`EVENT_OBJECT_DESTROY`での
  クリーンアップが想定通り機能するか、実装時に実際の挙動を確認する
  （`EVENT_OBJECT_DESTROY`が監視対象外のウィンドウも含め大量に発火し、未登録hwndへの`Map.Delete()`が
  例外になる不具合は実機確認で発見・修正済み。「検出方法」節参照）。
- `TrayTip`は非モーダルだが、短時間に複数のOfficeファイルが連続して開かれた場合、前の通知が
  `Settings.OfficeWatchTrayTipDurationMs`の間に読み切られないうちに次の`TrayTip`呼び出しで上書きされる
  可能性がある（`NotifyUI.ShowToast`と同様の制約。履歴を残したい場合はログ出力と併用する運用でカバーする）。
- Windowsの通知設定（集中モード等）によっては、トレイの吹き出し通知自体が表示されない・即座に消える
  場合がある。
- 同じファイルを閉じて再度開いた場合、新しいhwndとして検出されるため毎回表示される（意図した挙動として許容する想定）。
- 新規作成した未保存ファイル（保存先パスが存在しない状態）を開いた／作成した場合の表示内容は
  「パス: 取得できませんでした」で代用する想定だが、`Document.FullName`は未保存でも仮の名前を返すため、
  実際の表示内容は実装時に確認する。
- 起動済み（監視開始前から開いていた）のOfficeファイルは検出対象外（監視開始後に新規で開かれたものだけが対象）。
