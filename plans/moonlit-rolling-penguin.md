# tests/ の Assert() 重複解消

## Context

`tests/` 配下の6つの単体テストスクリプト（`test_office_file_watcher.ahk` /
`test_window_open_watcher.ahk` / `test_json.ahk` / `test_file_open_notifier.ahk` /
`test_pdf_file_watcher.ahk` / `test_recent_docs_watcher.ahk`）が、それぞれ独立に
全く同じ内容のグローバル関数 `Assert(actual, expected, label)` を定義している。

実行時には各ファイルが `AutoHotkey64.exe tests\xxx.ahk` として単独プロセスで動くため
問題は起きないが、VSCodeのAutoHotkey v2言語サーバはワークスペース全体をまとめてシンボル
解析するため「同名のグローバル関数が複数箇所で宣言されている」という警告
（`This function 'Assert' declaration conflicts with an existing Func`）を出し続ける。

これを解消するため、`Assert` を共通ヘルパーファイルに切り出し、各テストファイルは
`#Include` して使う形にする（`src/lib/` の「複数機能で使う処理は`lib/`に切り出す」方針を
テストにも適用する形）。

アプリ本体（`src/`）の動作・仕様には影響しないテスト基盤のみの変更のため、
`docs/spec/` への設計ドキュメント追加は行わない（`.claude/rules/docs-workflow.md` の
実装フローは新機能追加・既存動作の変更が対象であり、本変更は該当しない）。機械的で
試行錯誤の余地がないごく小さな変更のため、worklogも作成しない
（`.claude/rules/docs-workflow.md` 手順5の省略規定を適用）。

## 変更内容

### 1. ブランチ作成

`chore/tests-shared-assert-helper` を作成する。

### 2. 共通ヘルパーの新規作成: `tests/lib/Assert.ahk`

`src/lib/` の配置慣習に合わせ `tests/lib/` を新設し、以下の内容で作成する
（既存6ファイルの実装と完全に同一の挙動）。

```ahk
#Requires AutoHotkey v2.0

; tests/配下の単体テストスクリプト共通のアサーションヘルパー。
; 呼び出し元スクリプトがグローバル変数 failures / passed を宣言している前提で使う。
Assert(actual, expected, label) {
    global failures, passed
    if actual == expected {
        passed++
    } else {
        failures++
        FileAppend("FAIL: " label " expected=[" expected "] actual=[" actual "]`n", "*")
    }
}
```

`failures` / `passed` の宣言・初期化（`failures := 0` / `passed := 0`）と、末尾の
`FileAppend("passed=..." ...)` / `ExitApp(...)` は各テストファイル固有のまま変更しない
（各スクリプトは独立プロセスとして実行されるため、グローバル変数もファイルごとに独立している）。

### 3. 各テストファイルの修正（6ファイル共通の変更パターン）

対象: `test_office_file_watcher.ahk`, `test_window_open_watcher.ahk`, `test_json.ahk`,
`test_file_open_notifier.ahk`, `test_pdf_file_watcher.ahk`, `test_recent_docs_watcher.ahk`

- 既存の `#Include ..\src\...` 群の末尾に `#Include lib\Assert.ahk` を追加する。
- ファイル内に個別定義されている `Assert(actual, expected, label) { ... }` ブロック（9行）を削除する。
- それ以外（`failures := 0` / `passed := 0` の宣言、各 `Assert(...)` 呼び出し、末尾の集計・`ExitApp`）は一切変更しない。

### 4. `tests/README.md` の更新

「実行結果の見方」節の直前あたりに、`Assert` は `tests/lib/Assert.ahk` の共通ヘルパーである旨を
一文追記する。新規テスト追加時にこのヘルパーを再利用してもらうための最小限の案内。

## 影響範囲

- 追加: `tests/lib/Assert.ahk`
- 変更: `tests/test_office_file_watcher.ahk`, `tests/test_window_open_watcher.ahk`,
  `tests/test_json.ahk`, `tests/test_file_open_notifier.ahk`,
  `tests/test_pdf_file_watcher.ahk`, `tests/test_recent_docs_watcher.ahk`, `tests/README.md`
- `src/` には一切手を入れない。

## 検証方法

変更前後で各テストの `passed`/`failures` 件数が変わらないことを確認する。

1. 変更前に一度、6ファイルそれぞれを `AutoHotkey64.exe tests\<file>.ahk` で実行し、
   出力される `passed=N failures=0` の値を記録する（ベースライン）。
2. 上記の変更を適用する。
3. 再度6ファイルすべてを実行し、`failures=0` であること、`passed=N` がベースラインと
   一致することを確認する。
4. VSCode側で `Assert` の重複警告が消えていることを確認する（拡張機能のキャッシュにより
   反映が遅れる場合はファイルの再読み込み/再オープンを試す）。
