# PowerShellスクリプト・コマンドの文字コード注意事項

Windows PowerShell 5.1（`powershell.exe`。本プロジェクトの実行環境）は既定で、コンソール入出力・
`Get-Content`/`Set-Content`/`Out-File`等のファイルI/Oを**システムのANSI/OEMコードページ**
（日本語Windowsでは通常cp932）で扱う。UTF-8を前提とする`gh`/`glab` CLIとのやり取りや、日本語を含む
テキストファイルの読み書きでこれを踏まえないと、実機でのみ再現する文字化け・構文エラーが発生する
（issue #5対応時に2種類の実例で確認済み。詳細は
[dev-tools/docs/spec/issue-mr-workflow.md](../../dev-tools/docs/spec/issue-mr-workflow.md)
「セッション開始時の自動コンテキスト注入」節参照）。

## 守ること

1. **`.ps1`ファイルはBOM付きUTF-8で保存する**
   BOM無しUTF-8で保存すると、Windows PowerShell 5.1が日本語コメント等を正しく解釈できず、
   離れた箇所で構文エラーになることがある（実例: `.claude/hooks/session-start.ps1`を新規作成した際、
   BOM無しUTF-8で保存され`[Draft]`のような無関係な箇所でパースエラーになった）。既存の
   `dev-tools/src/build.ps1`と同じくBOM付きUTF-8で保存する。

2. **`gh`/`glab`等の外部コマンドとやり取りするスクリプトは、コンソールエンコーディングを
   明示的にUTF-8へ切り替える**
   `dev-tools/src/vcs/Provider.ps1`はdot-source直後に
   `[Console]::OutputEncoding`/`[Console]::InputEncoding`をUTF-8へ切り替えている。この保護は
   Provider.ps1をdot-sourceした呼び出し側すべてに及ぶ（例: `.claude/hooks/session-start.ps1`にも
   同様の切り替えを個別に入れている。hookは独立プロセスとして起動されるため、Provider.ps1側の
   設定に頼らずスクリプト自身の冒頭でも設定する）。

3. **`Get-Content`/`Set-Content`でテキストファイルを読み書きする際は`-Encoding UTF8`を明示する**
   2.のコンソールエンコーディング切り替えは、あくまで「PowerShellプロセスと外部コマンド間のI/O」を
   保護するものであり、`Get-Content -Raw`のようなファイル読み込みには効かない。BOM無しUTF-8ファイルを
   `-Encoding`指定無しで`Get-Content`すると、システムのANSIコードページとして誤読される
   （実例: issue #5のレビュー返信で、一時ファイルに書いた日本語の返信本文を`Get-Content -Raw`
   （エンコーディング未指定）で読み込み、文字化けしたままGitHubへ投稿してしまった）。
   日本語を含むテキストファイルを読み書きする際は、常に`-Encoding UTF8`を明示する。

## 影響範囲の目安

`dev-tools/src/vcs/`配下のスクリプト、`.claude/hooks/`配下のhookスクリプトなど、本プロジェクトで
新規にPowerShellスクリプトを書く・実行する場合はすべて対象。
