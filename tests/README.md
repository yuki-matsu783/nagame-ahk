# tests/

手動/自動テスト用スクリプトを置くディレクトリ（`CLAUDE.md` 参照）。
機能の動作確認に使ったスクリプトは使い捨てにせず、ここに残して再実行できるようにする。

## 一覧

| ファイル | 対象 | 副作用 | 実行方法 |
|---|---|---|---|
| `test_json.ahk` | `src/lib/Json.ahk`（エンコード/デコード） | なし。GUIを開かずアサーション結果を標準出力してExitApp() | `AutoHotkey64.exe tests\test_json.ahk` |
| `test_external_command_server.ps1` | `docs/external-command-server.md` の実装一式（TCPサーバー・認証・コマンドディスパッチ） | あり。`src/main.ahk` を実際に起動し、クリップボードを書き換え、トースト通知を表示する。実行中の `AutoHotkey64.exe` プロセスを名前で終了させる | `powershell -File tests\test_external_command_server.ps1` |

## 実行結果の見方

どちらも最後に `passed=<成功数> failures=<失敗数>` を出力し、失敗が1件でもあれば終了コード1を返す。
個別の失敗は `FAIL: <ラベル> expected=[...] actual=[...]` 形式で出力される。

## 対象外(手動確認が必要)

以下は実機の入力・GUI表示を伴い、自動テストで実行すると意図しない副作用(誤入力・マウス操作等)が
発生するため、自動テストの対象から外している。変更した場合は手動で動作確認すること。

- `SendKeys` / `MouseClick` / `MouseDrag` / `MouseScroll` / `PlayMacro`（実際のキー入力・マウス操作）
- `ShowInputDialog` / `ShowChoiceDialog`（ユーザー操作待ちのGUIダイアログ）
- `ShowMessageBox`（モーダルダイアログ。表示したままだとテストが進行しなくなる）

## 新しい機能を追加したとき

`/ahk-implement` で機能を実装した際は、可能な範囲でここにテストスクリプトを追加する。
- ロジックが単体で切り出せる場合（`lib/` 配下など）は `test_json.ahk` のようなAHKの単体テストにする。
- IPC・複数モジュールの結合確認が必要な場合は `test_external_command_server.ps1` のような
  PowerShellスクリプトで、実プロセスを起動してTCP/ファイル等の外部インターフェース越しに検証する。
- 実機の入力操作やGUI表示など自動化すると副作用が大きいものは、対象外として上の表に理由を記載し、
  手動確認の手順をコメントか設計ドキュメントに残す。
