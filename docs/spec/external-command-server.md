---
title: 外部コマンドサーバー（ExternalCommandServer）
type: spec
description: 外部プロセスからTCP経由でウィンドウ操作・入力操作等をJSONコマンドで呼び出せるようにする機能の仕様
tags: [external-command-server, ahk, spec]
timestamp: "2026-08-16T05:31:36"
---

# 外部コマンドサーバー（ExternalCommandServer）

## 背景・目的

Python等の外部プロセスから、AHKが得意とするウィンドウ操作・入力操作・クリップボード操作・通知/簡易UI表示を
呼び出せるようにする。`nagame-ahk` を常駐サーバーとして動作させ、TCPループバックソケット経由で受信した
JSON形式のコマンドを実行し、結果をJSON形式で応答する。

外部プロセス側は自由に実装できる（Windows上のPython、およびWSL上のPythonの両方からの利用を想定する）。

## 仕様

### 通信方式

- **トランスポート**: TCPソケット（ループバック）。`Settings.ServerHost`（既定 `"127.0.0.1"`）の
  `Settings.ServerPort`（既定 `39321`）でリッスンする。
  - Windows Named Pipeも候補だったが、WSL（1/2いずれも）のLinux側からはWin32のNamed Pipeに
    標準ではアクセスできず、`npiperelay.exe` + `socat` 等の追加リレーツールが必要になる。
    TCPループバックであれば、WSL2の「localhost forwarding」により追加ツール無しで
    `localhost:Settings.ServerPort` へ到達できるため、こちらを採用する
    （「未決定事項・懸念点」にWSL2側のフォールバック手段を記載）。
- **バインド範囲**: `127.0.0.1` のみにバインドし、LAN等の外部ネットワークからは接続できないようにする。
- **フレーミング**: 改行区切りJSON。1メッセージ = 1行のJSON + `\n`。JSON文字列内の改行は
  JSON仕様上エスケープされる（`\n`）ため、行区切りとの衝突は発生しない。
- **文字コード**: UTF-8。
- **接続数**: v1では**同時1接続のみ**を想定する。接続中に別クライアントが接続を試みた場合の挙動は
  「未決定事項」を参照。
- **接続ライフサイクル**: クライアントは常時接続を維持する想定（Pythonプロセスが起動時に接続し、
  終了時に切断）。切断を検知したらサーバーは待受状態に戻り、次の接続を待つ。
- **非ブロッキング処理**: Winsock(`ws2_32.dll`)のソケットを`ioctlsocket(FIONBIO)`で非ブロッキング
  モードにし、`Settings.ServerPollIntervalMs`(既定50ms)間隔の`SetTimer`で`accept`/`recv`/`send`の
  可否をポーリングする。ブロッキング呼び出しは行わない(AHKは単一スレッドのため、ブロックすると
  ホットキー等全体が固まる)。
  - **実装メモ(設計変更の経緯)**: 当初はよりAHKに馴染む方式として `WSAAsyncSelect` +
    `OnMessage()` のイベント駆動方式を実装したが、実機テストで**初回の接続が完了した後、
    2回目以降の接続でFD_ACCEPT等のウィンドウメッセージが一切届かなくなる**という再現性の高い
    不具合に遭遇した(`tests/test_external_command_server.sh`。当時はPowerShell版だったが
    issue #6でbash化。複数回の連続接続を検証して発覚)。
    Winsockメッセージ配信の詳細な原因切り分けよりも安定動作を優先し、実績のあるポーリング方式に
    戻した。ポーリングのため理論上は`Settings.ServerPollIntervalMs`分のレイテンシが乗るが、
    既定50msは実用上問題にならない。

### メッセージフォーマット

**リクエスト（外部プロセス → AHK）**

```json
{"id": "req-001", "command": "ActivateWindow", "params": {"winTitle": "ahk_exe notepad.exe"}}
```

- `id`: リクエスト識別子（任意の文字列）。レスポンスの対応付けに使用する。
- `command`: コマンド名（後述の一覧を参照）。
- `params`: コマンドごとのパラメータオブジェクト。

**レスポンス（AHK → 外部プロセス）**

成功時:
```json
{"id": "req-001", "ok": true, "result": {}}
```

失敗時:
```json
{"id": "req-001", "ok": false, "error": "指定されたウィンドウが見つかりません"}
```

- 全コマンドに対して必ずレスポンスを返す（値を返さないコマンドも `result: {}` で成功/失敗を通知する）。
- 未知の `command` を受信した場合は `ok: false, error: "unknown command: xxx"` を返す。
- **簡易GUI系コマンド（`ShowInputDialog` / `ShowChoiceDialog`）はユーザー操作待ちのため非同期で応答する**。
  他のコマンドの応答より遅れて返る可能性があるが、`id` で対応付けられるためリクエスト順・応答順は
  一致しなくてよい前提とする。

### 認証

ループバックのみにバインドするとはいえ、同一マシン上の他プロセスからは誰でも接続できてしまうため、
**接続確立後の最初のメッセージで共有トークンを送らせる**簡易認証で保護する。同一マシン上の他プロセスからの
誤接続・意図しない操作を防ぐことが目的であり、暗号学的に強固な認証ではない点に留意する
（「未決定事項・懸念点」参照）。

- 接続確立直後、サーバーは「未認証」状態になる。
- クライアントは最初のメッセージとして以下を送信する必要がある。
  ```json
  {"id": "auth-1", "command": "Auth", "params": {"token": "ahk-rira"}}
  ```
- `params.token` が `Settings.AuthToken`（既定値 `"ahk-rira"`）と一致すれば、
  `{"id": "auth-1", "ok": true, "result": {}}` を返し、その接続を「認証済み」にする。
  以降はその接続上で通常通りコマンドを受け付ける。
- 未認証状態で `Auth` 以外のコマンドを受信した場合、またはトークンが不一致だった場合は
  `{"id": ..., "ok": false, "error": "authentication required"}` を返した上で接続を切断する
  （ソケットをclose、再度接続待ちに戻る）。
- 認証は接続ごとに1回のみ。再接続した場合は再度 `Auth` が必要。

### ウィンドウ指定方法

`winTitle` パラメータはAHKの [WinTitle](https://www.autohotkey.com/docs/v2/misc/WinTitle.htm) 構文
（`ahk_exe notepad.exe` 等）をそのまま文字列で受け取る。独自の識別方式を新設せず、AHKが元々持つ
柔軟なウィンドウ指定機能をそのまま外部プロセスに公開する。

### コマンド一覧

#### ウィンドウ操作系（`features/WindowControl.ahk`）

| command | params | result |
|---|---|---|
| `ActivateWindow` | `winTitle` | `{}` |
| `MinimizeWindow` | `winTitle` | `{}` |
| `MaximizeWindow` | `winTitle` | `{}` |
| `RestoreWindow` | `winTitle` | `{}` |
| `CloseWindow` | `winTitle` | `{}` |
| `MoveWindow` | `winTitle, x, y, width?, height?` | `{}`（`width`/`height`省略時は現状維持） |
| `ArrangeWindows` | `winTitles: [...], layout: "left-right"\|"top-bottom"\|"grid", monitor?` | `{}` |
| `SetAlwaysOnTop` | `winTitle, enabled: bool` | `{}` |
| `SetTransparency` | `winTitle, alpha: 0-255` | `{}` |
| `ListWindows` | なし | `{windows: [{hwnd, title, processName, class, x, y, width, height, minimized, maximized}]}` |
| `GetActiveWindow` | なし | `{hwnd, title, processName, class, x, y, width, height}` |

#### 入力操作系（`features/InputControl.ahk`）

| command | params | result |
|---|---|---|
| `SendKeys` | `winTitle?, keys` | `{}`（`winTitle`指定時は `ControlSend`／未指定時はアクティブウィンドウへ `Send`） |
| `SendText` | `winTitle?, text, method: "send"\|"clipboard"` | `{}`（`clipboard`はクリップボード経由で高速貼り付け。貼り付け後に元のクリップボード内容へ復元する） |
| `MouseClick` | `x, y, button: "left"\|"right"\|"middle", winTitle?` | `{}` |
| `MouseDrag` | `fromX, fromY, toX, toY, button` | `{}` |
| `MouseScroll` | `x, y, delta` | `{}` |
| `PlayMacro` | `name` | `{}`（`Macros.Definitions`（`config/Macros.ahk`）に定義済みのマクロ名を指定） |

#### クリップボード系（`features/ClipboardControl.ahk`）

| command | params | result |
|---|---|---|
| `GetClipboard` | なし | `{text}` |
| `SetClipboard` | `text` | `{}` |
| `GetClipboardHistory` | `limit?`（既定 `Settings.ClipboardHistoryMax`） | `{items: [{text, timestamp}]}` |
| `ClearClipboardHistory` | なし | `{}` |
| `PasteFormatted` | `winTitle?, text, format: {normalizeNewline?: "CRLF"\|"LF"\|"CR", trim?: bool, trimLines?: bool}` | `{}`（整形後にクリップボード経由で貼り付け） |

- クリップボード履歴は `OnClipboardChange` で監視し、メモリ上に最大 `Settings.ClipboardHistoryMax` 件保持する。
  **永続化はしない**（再起動で消える）。

#### 通知・簡易UI系（`features/NotifyUI.ahk`）

| command | params | result |
|---|---|---|
| `ShowToast` | `title, message, durationMs?` | `{}`（`TrayTip()` を使用。即時応答） |
| `ShowMessageBox` | `title, message` | `{}`（`MsgBox` を使用。表示中はスレッドがブロックされる点に注意。「未決定事項」参照） |
| `ShowInputDialog` | `title, message, defaultValue?` | `{value, cancelled: bool}`（独自 `Gui()` で実装、非モーダル。ユーザー操作後に非同期応答） |
| `ShowChoiceDialog` | `title, message, choices: [...]` | `{selected, cancelled: bool}`（同上） |

- `ShowToast` は Windows 10以降のネイティブトースト通知（`Windows.UI.Notifications`）ではなく、
  AHK組込みの `TrayTip()`（トレイ付近のバルーン通知）で代替する。実装コストと安定性を優先した判断。
  ネイティブトーストが必要であれば別途懸念点として扱う。

### JSONエンコード/デコード

外部の完成されたライブラリをそのままvendoringするのではなく、**本プロトコルに必要な最小限の機能のみを
自作**する（オブジェクト・配列・文字列・数値・真偽値・nullのエンコード/デコード。コメントやトレイリングカンマ等JSON拡張仕様は非対応でよい）。

### 内部アーキテクチャ

```
main.ahk
  └─ core/ExternalCommandServer.ahk  … 起動・停止、受信メッセージのJSONパース、コマンドディスパッチ、応答送信
        └─ lib/TcpServer.ahk         … TCPソケットの接続待受・フレーム分割送受信のみ（コマンドの意味は知らない）
        └─ lib/Json.ahk              … JSONエンコード/デコード（自作・最小限）
        └─ features/WindowControl.ahk
        └─ features/InputControl.ahk
        └─ features/ClipboardControl.ahk
        └─ features/NotifyUI.ahk
```

- `core/ExternalCommandServer.ahk` は `core/Hotkeys.ahk` と対になる位置づけ（外部トリガーの集約窓口）とする。
- `features/*` 間の直接依存は禁止(CLAUDE.mdの既存ルール通り)。ウィンドウ特定やクリップボード操作などの
  共通処理が今後増えた場合は `lib/` に切り出す。

### トレイメニュー

- 「外部コマンド受付」のON/OFFをトレイメニューに追加する（`ActivityStatus` の表示ON/OFFと同様の構成）。
- 現在の接続状態（未接続 / 接続中）をメニュー項目のテキストまたはツールチップで確認できるようにする。

## 影響範囲

- 追加: `src/lib/TcpServer.ahk`（TCPループバックソケットの接続待受・送受信の汎用処理）
- 追加: `src/lib/Json.ahk`（JSONエンコード/デコード。自作・最小限）
- 追加: `src/core/ExternalCommandServer.ahk`（受信メッセージのディスパッチ）
- 追加: `src/features/WindowControl.ahk`
- 追加: `src/features/InputControl.ahk`
- 追加: `src/features/ClipboardControl.ahk`
- 追加: `src/features/NotifyUI.ahk`
- 追加: `src/config/Macros.ahk`（マクロ定義。`Settings` とは別ファイルとした。ステップは
  `Map("type", "key"|"text"|"sleep", "value", ...)` のDSLで表現する）
- 追加: `tests/test_json.ahk`（`lib/Json.ahk` の単体テスト。GUIを開かず結果を標準出力しExitAppする）
- 変更: `src/main.ahk`（`#Include` 追加。順序は `config → lib → core → features` を維持）
- 変更: `src/config/Settings.ahk`（設定値追加。下表参照）
- 変更: `src/core/App.ahk`（起動時に `ClipboardControl.StartWatching()` と、
  `Settings.ExternalCommandAutoStart` が true の場合に `ExternalCommandServer.Start()` を呼び出し）
- 変更: `src/core/TrayMenu.ahk`（「外部コマンド受付」メニュー項目を追加。接続状態は
  メニュー項目のチェック状態(有効/無効)とトレイアイコンのツールチップ(`A_IconTip`、
  停止中/待受中/接続中)で確認できるようにした）
- 変更: `src/lib/WindowUtils.ahk`（`DescribeWindow(hwnd)` を追加。`ListWindows`/`GetActiveWindow`
  で共通利用するウィンドウ情報Map生成処理）

## 設定項目

| 設定値 | 既定値 | 説明 |
|---|---|---|
| `Settings.ServerHost` | `"127.0.0.1"` | リッスンするアドレス（ループバック固定） |
| `Settings.ServerPort` | `39321` | リッスンするポート番号 |
| `Settings.ServerPollIntervalMs` | `50` | accept/recv/sendの可否確認のポーリング間隔(ms) |
| `Settings.ServerBufferSize` | `4096` | 読み書きバッファサイズ(byte) |
| `Settings.ExternalCommandAutoStart` | `true` | アプリ起動時にサーバーを自動起動するか |
| `Settings.ClipboardHistoryMax` | `50` | クリップボード履歴の最大保持件数 |
| `Settings.AuthToken` | `"ahk-rira"` | 接続直後の認証で要求する共有トークン |

## 未決定事項・懸念点

- **WSL2のlocalhost forwardingが効かない環境**: VPNクライアントの併用等で `localhost` 転送が無効化される
  場合がある。その場合はWSL2側の `/etc/resolv.conf` に記載されるWindowsホストIPへ接続する
  フォールバックが必要になる。クライアント側（Python）の接続先解決ロジックとしてドキュメント化するか、
  `Settings.ServerHost` を `0.0.0.0` にしてWSL2の仮想アダプタからも到達可能にするか、要検討
  （後者は到達範囲が広がるためセキュリティ上のトレードオフがある）。
- **認証トークンの秘匿性**: `Settings.AuthToken`（既定 `"ahk-rira"`）はソースコードにコミットされる
  ため、真の秘密情報ではない。あくまで「同一マシン上での誤接続・意図しない操作の防止」を目的とした
  簡易的なゲートであり、悪意ある同一マシン上のプロセスからの防御は期待できない点を関係者間で認識合わせする。
  必要に応じて環境ごとに `Settings.AuthToken` を変更できるようにする程度の運用でよいか確認したい。
- **`ShowMessageBox` のブロッキング**: `MsgBox` はモーダルでスレッドをブロックする。
  `WSAAsyncSelect`方式への変更によりソケット処理自体はイベント駆動になったため常時ポーリングの
  遅延懸念は無くなったが、`MsgBox`表示中は他のソケットイベント(=他コマンドの受信)がAHKのメッセージ
  キューに滞留し、閉じるまで処理されない点は変わらない。多用する場合は`ShowMessageBox`も
  `ShowInputDialog`同様の独自Guiベースの非モーダル実装への置き換えを検討する。
- **同時複数接続**: v1は1接続のみ想定として実装した。接続中に別クライアントが接続を試みた場合は
  即座に拒否(接続を確立せずクローズ)する(`TcpServer._HandleAccept`)。複数クライアントへの対応は
  範囲外。
- **`ArrangeWindows` のレイアウト計算**: `"grid"`は `Ceil(Sqrt(count))` で列数を決め、
  行数は `Ceil(count / cols)` から算出するシンプルな均等割り付けとして実装した
  (`WindowControl.ArrangeWindows`)。ウィンドウごとの最小サイズ等は考慮していない。
- **切断検知**: `recv()`が0を返す(相手からの正常クローズ)、または`FD_CLOSE`イベントの受信をもって
  即座に切断とみなし、次の接続を待つ状態に戻る。クライアントの異常終了(プロセスkill等)からOSが
  それを検知するまでの時間はOS/TCPスタック依存であり、アプリ側でタイムアウトの調整は行っていない。
- **`SendText` のクリップボード方式**: 貼り付け後に元のクリップボード内容を復元するが、
  復元前に外部から `GetClipboard` / `SetClipboard` が呼ばれた場合の競合は考慮していない。
