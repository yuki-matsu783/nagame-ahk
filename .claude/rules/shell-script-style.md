# bashスクリプトの規約

issue #6でリポジトリ内の開発補助スクリプトを全てPowerShellからbashへ移行した際に定めた規約。
設計方針・移行の経緯は [dev-tools/docs/spec/shell-scripts.md](../../dev-tools/docs/spec/shell-scripts.md)
を参照（このファイルは規約のみを記載し、経緯の重複は避ける）。

## 前提・保存形式

- 実行環境はgit bash（Git for Windows付属のMSYS bash）。WSL/Linux実機での動作確認は行っていない
  （`dev-tools/docs/spec/shell-scripts.md`の未決定事項参照）。
- ファイルはUTF-8・**BOM無し**・LF改行で保存する（PowerShellの`.ps1`と異なり、BOMは不要かつ
  有害。シバン行`#!/usr/bin/env bash`の直前にBOMがあるとインタプリタ判定に失敗する処理系がある）。
  このリポジトリは`core.autocrlf=input`のためコミット時にCRLFはLFへ変換されるが、Write/Editツール
  で新規作成した時点で既にLFになっていることを前提にしており、そこに依存しない保証がほしい場合は
  `.gitattributes`に`*.sh text eol=lf`を追加する運用も検討できる（未導入）。
- 先頭に `#!/usr/bin/env bash` を置く。

## エラー方針

- スクリプト冒頭で `set -euo pipefail` を宣言する（PowerShellの`$ErrorActionPreference = "Stop"`
  相当。「失敗したら即座に止まる」を既定にする）。
- **bashでのtry/catch相当の書き方**: 「失敗しても処理を継続したい／握りつぶしたい」箇所は、
  該当処理を関数化し、コマンド置換 `$(func)` または明示的な実サブシェル `( func )` の中で呼ぶ。
  ```bash
  if result="$(risky_func)"; then
    use "$result"
  else
    fallback
  fi
  ```
  - **理由**: bashは`if cmd; then...else...fi`や`cmd1 || cmd2`のような条件式の中では、`set -e`に
    よる「コマンド失敗時に即座にシェルを終了する」動作が一時停止される仕様があり、この一時停止は
    条件式として評価される間、そこで呼ばれる関数の内部にまで及ぶ。関数呼び出しをそのまま条件式に
    置くと、内部の複数コマンドが途中で失敗しても最後まで実行され続けてしまう。
  - コマンド置換・明示サブシェルは実行時に必ず新しいプロセスへフォークされるため、フォークされた
    側では「条件式の中にいる」制約を受けず`set -e`が正しく機能し、内部で失敗した時点で
    サブシェルごと終了する。その終了コードは呼び出し元の`if`/`||`から正しく検知できる。
  - 実例: `.claude/hooks/session-start.sh` の `build_context`、
    `.claude/hooks/post-push-usage-report.sh` の `main`。

## JSON操作

- JSONの生成・パースは `jq` を使う（PowerShellの`ConvertFrom-Json`/`ConvertTo-Json`相当。新規の
  外部依存としてインストールが必要。`dev-tools/docs/spec/shell-scripts.md`「前提」参照）。
- 関数の戻り値はPSCustomObjectに代えてJSON文字列をstdoutへ出力する設計にする。呼び出し側は
  `jq`でフィールドを取り出す（例: `get_issue 6 | jq -r '.title'`）。JSONのキー名はPascalCaseでは
  なくcamelCase（`number`/`title`/...）に統一する。
- Windows PowerShell 5.1の`ConvertFrom-Json`が`-AsHashtable`を持たないための回避策
  （`ConvertTo-HashtableDeep`等）は、jqのネイティブなJSON操作機能により不要になる。移植の際に
  引き継がないこと。

## 命名規則

- 関数名はsnake_caseにする（PowerShellの`Verb-Noun`規約から移植する場合は
  `Get-Issue`→`get_issue`のように変換する）。
- プロバイダ固有の実装（GitHub/GitLab等）は `github_xxx` / `gitlab_xxx` のように接頭辞を付ける
  （PowerShell版の`GitHub-Xxx`/`GitLab-Xxx`に相当）。

## git bashのパス変換の落とし穴

`/in`のようなDOS形式の単一スラッシュ引数を、Windowsネイティブの非MSYS実行ファイル
（`Ahk2Exe.exe`, `tasklist.exe`, `taskkill.exe`等）に渡すと、git bash（MSYS）が「POSIXパスらしき
文字列」と誤認しWindowsパスへ自動変換してしまう既知の問題がある（実機確認: `/in`が
`C:/Program Files/Git/in`に化け`Unrecognised parameter`エラーになった）。**先頭を`//`にする
（`//in`）とこの自動変換を回避でき、ネイティブ側には`/in`として渡る。** DOS形式フラグを持つ
ネイティブコマンドを呼ぶ際は必ずこの対策を行う（`dev-tools/src/build.sh`の`//in` `//out` `//base`
`//icon`、`tests/test_external_command_server.sh`の`//FI` `//IM` `//F`が実例）。

## 文字コード

- git bashの標準入出力・パイプ・`jq`/`gh`とのやり取りはシステムのANSI/OEMコードページの影響を
  受けない。PowerShell版で必要だった明示的なUTF-8切り替え（`.claude/rules/powershell-encoding.md`
  参照）はbash版には不要。
- ただし`tasklist.exe`のような非MSYSネイティブコマンドの出力はシステムのコードページ（cp932等）の
  ままになる。この種のコマンドの出力を判定に使う場合は、日本語メッセージの文字列一致を避け、
  終了コードやASCII文字列（イメージ名等）での判定に留める。

## Claude Code hookとして登録する場合

`.claude/settings.json`のhook `command`は `"bash"` とだけ指定する（フルパス直書きはしない。他環境
への移植性を優先）。ただし環境によっては、Windowsの`PATH`で`C:\Windows\System32\bash.exe`
（WSL起動用スタブ）が`Git\bin`より先に解決され、エラーも出さずgit bashではなくWSLが起動する
可能性がある（このマシンで実機確認済み。Git for Windowsのインストーラは既定で`bash.exe`のある
`Git\bin`を`PATH`に追加しないことが原因）。**ユーザー環境変数`Path`に`Git\bin`
（例: `C:\Program Files\Git\bin`）を`C:\Windows\System32`より前に来る位置で追加する**ことで
解決する（具体的な手順は
[dev-tools/docs/spec/shell-scripts.md](../../dev-tools/docs/spec/shell-scripts.md)
「Claude Code hookの起動コマンド」参照）。`${CLAUDE_PROJECT_DIR}`（Windows形式パス）はこの
`bash.exe`へargvで渡しても正しく解決される。

## テスト

- 副作用の無い純粋ロジック（文字列変換・正規表現マッチ等）は、外部コマンド呼び出しを伴わない
  単体テストスクリプトを`tests/`に置く（実例: `tests/test_vcs_provider.sh`）。
- 実プロセス起動・TCP通信等の結合確認は、既存のAHKテストと同じ「`passed=N failures=N`を出力し
  失敗があれば終了コード1」という規約に合わせる（実例: `tests/test_external_command_server.sh`）。
- 作成した`.sh`は最低限 `bash -n <file>` で構文チェックする。
