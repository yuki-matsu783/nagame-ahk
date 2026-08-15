# 開発補助スクリプトのシェル言語方針

## 背景・目的

[issue #6](https://github.com/yuki-matsu783/nagame-ahk/issues/6)「スクリプトを可能な限りbashで記載する」
への対応。PowerShellはWSL等の非Windows的なシェル環境から扱いにくいため、git bash経由で同等の
ことが行えるスクリプトはbash化し、行えないものだけPowerShellのまま残す方針とした。

実機で変換可否を検証した結果、リポジトリ内にあった全PowerShellスクリプト（issue-mr-flowの
中核であるVCS抽象化層、ビルドスクリプト、Claude Code hook、結合テストスクリプト）が git bash +
`jq` + 標準的なWindowsコマンド呼び出しの組み合わせで同等の動作を実現できることが分かり、
2026-08-16時点で `.ps1` ファイルはリポジトリ内に1つも残っていない。

## 仕様

### 対象スクリプト一覧（旧ファイル→新ファイル）

| 旧ファイル(`.ps1`) | 新ファイル(`.sh`) | 役割 |
|---|---|---|
| `dev-tools/src/vcs/Provider.ps1` | `dev-tools/src/vcs/Provider.sh` | issue-mr-flowの中核。GitHub/GitLab差異吸収 |
| `dev-tools/src/vcs/Github.ps1` | `dev-tools/src/vcs/Github.sh` | `gh` CLIラッパー |
| `dev-tools/src/vcs/Gitlab.ps1` | `dev-tools/src/vcs/Gitlab.sh` | `glab` CLIラッパー（未検証。GitLab実remoteが無いため） |
| `dev-tools/src/build.ps1` | `dev-tools/src/build.sh` | Ahk2Exeビルド |
| `.claude/hooks/session-start.ps1` | `.claude/hooks/session-start.sh` | SessionStart hook |
| `.claude/hooks/post-push-usage-report.ps1` | `.claude/hooks/post-push-usage-report.sh` | PostToolUse hook（使用量レポート） |
| `.claude/hooks/lib/UsageTracking.ps1` | `.claude/hooks/lib/UsageTracking.sh` | 上記hookの共通集計ロジック |
| `tests/test_external_command_server.ps1` | `tests/test_external_command_server.sh` | 結合スモークテスト |

新規（PowerShell版に対応物が無い）:
- `tests/test_vcs_provider.sh`: `Provider.sh` の純粋ロジック（`to_slug`, `test_issue_sections`,
  `get_issue_number_from_branch`）に対する単体テスト。受け入れ条件「スクリプトをテストするための
  スクリプトを作成する」に対応。

### 前提（新規追加）

- git bash（Git for Windows付属のMSYS bash。既存の`git`利用が前提のため追加インストール不要）
- `jq`（JSON操作。PowerShellの`ConvertFrom-Json`/`ConvertTo-Json`相当。**新規の外部依存として
  インストールが必要**）
- 既存: `gh`/`glab` CLI、AutoHotkey v2（テスト対象アプリ）

### 実行環境の検証状況（開発機で確認済み、2026-08-16）

- git bash: mingw64同梱bash 5.2、`/dev/tcp`（TCPソケット。`/dev/tcp/host/port`構文）対応、
  `ps -W`でWindowsプロセス一覧取得可
- `jq` 1.6
- `gh` CLI、AutoHotkey v2

### 設計方針

- **戻り値**: PowerShell版のPSCustomObjectに代えて、JSON文字列をstdoutへ出力する設計に統一した。
  呼び出し側は`jq`でフィールドを取り出す（例: `get_issue 6 | jq -r '.title'`）。JSONのキー名は
  PowerShell版のPascalCase（`Number`/`Title`/...）ではなく、bash/jqのエコシステムに合わせて
  camelCase（`number`/`title`/...）に統一した。
- **関数命名**: PowerShellの`Verb-Noun`規約からbashのsnake_case関数へ移植した
  （例: `Get-Issue`→`get_issue`、`New-IssueBranch`→`new_issue_branch`）。
- **エラー方針**: `set -euo pipefail`をPowerShell版の`$ErrorActionPreference = "Stop"`相当として
  採用する。
- **bashでのtry/catch相当の書き方**: 本体処理を関数化し、コマンド置換`$(func)`または明示的な
  実サブシェル`( func )`の中で呼ぶ。
  - **理由**: bashは`if cmd; then...else...fi`や`cmd1 || cmd2`のような条件式の中では、`set -e`
    による「コマンド失敗時に即座にシェルを終了する」動作が一時停止される仕様がある。この一時停止は
    条件式として評価される間、そこで呼ばれる関数の内部にまで及ぶため、関数呼び出しをそのまま
    条件式に置くと、内部で複数のコマンドが順に実行される場合、途中で失敗があっても最後まで
    実行され続けてしまい、PowerShellのtry/catchのような「最初の失敗で即座に中断」という直感的な
    動作にならない。
  - **対策**: コマンド置換 `$(...)` や `( ... )` は実行時に必ず新しいプロセス（サブシェル）へ
    フォークされる。フォークされたサブシェルの内部では、そのサブシェル自身の視点で見て
    「条件式の中にいる」わけではないため、`set -e`（呼び出し元から継承される）が正しく機能し、
    内部で失敗したコマンドの時点で即座にサブシェルごと終了する。その終了コードは呼び出し元の
    `if`/`||`から正しく検知できる。
  - **採用箇所**: `session-start.sh`（`build_context`関数。成功時はstdout経由でコンテキスト文字列を
    受け取り、失敗時はフォールバックメッセージを出す）、`post-push-usage-report.sh`（`main`関数。
    失敗はすべて握りつぶしgit push自体はブロックしない）。
- **git bashのパス変換**: `/in`のようなDOS形式の単一スラッシュ引数を、Windowsネイティブの
  非MSYS実行ファイル（`Ahk2Exe.exe`, `tasklist.exe`, `taskkill.exe`等）に渡すと、git bash（MSYS）が
  「POSIXパスらしき文字列」と誤認しWindowsパスへ自動変換してしまう既知の問題がある（実機確認:
  `build.sh`の初期実装で`/in`が`C:/Program Files/Git/in`に化け、`Ahk2Exe.exe`が
  `Unrecognised parameter`エラーダイアログを出して停止した）。先頭を`//`にする（`//in`）と
  MSYSの自動変換対象から外れ、ネイティブ側には`/in`として渡る。`build.sh`の`//in` `//out` `//base`
  `//icon`、`test_external_command_server.sh`の`tasklist`/`taskkill`の`//FI` `//IM` `//F`が実例。
- **文字コード**: PowerShell版が必要としていたANSI/OEMコードページ対策
  （`[Console]::OutputEncoding`の明示切り替え等。`.claude/rules/powershell-encoding.md`参照）は
  bash版では不要（git bashの標準入出力・パイプ・`jq`/`gh`とのやり取りはコードページの影響を
  受けないため）。ただし`tasklist.exe`のような非MSYSネイティブコマンドの出力はシステムの
  コードページ（cp932）のまま返る（実機確認: 日本語メッセージが文字化けした）。この種のコマンドの
  出力を判定に使う場合は、日本語メッセージの文字列一致を避け、終了コードやASCII文字列
  （イメージ名等）での判定に留める（`test_external_command_server.sh`の`proc_running`参照）。
- **Claude Code hookの起動コマンド**: `.claude/settings.json`のhook `command`に素の`"bash"`を
  指定すると、このマシンでは`where.exe bash`の解決結果が`C:\Windows\System32\bash.exe`
  （WSL起動用スタブ）を優先してしまい、git bashではなくWSLが起動する（実機確認）。
  git bash本体`C:\Program Files\Git\bin\bash.exe`をフルパスで指定する必要がある。単一開発者運用の
  ためGit for Windowsの標準インストール先を前提としており、別環境で異なる場合はパスを書き換える
  （「未決定事項・懸念点」参照）。`${CLAUDE_PROJECT_DIR}`（Windows形式パス）をそのままこの
  `bash.exe`へargvで渡しても正しく解決されることは実機確認済み。
- **PowerShell版からの簡略化点**: `ConvertTo-HashtableDeep`（Windows PowerShell 5.1の
  `ConvertFrom-Json`が`-AsHashtable`を持たないための回避策）はjqのネイティブなJSON操作機能により
  不要になったため、bash版（`UsageTracking.sh`）には存在しない。

## 影響範囲

新規:
- `dev-tools/src/vcs/{Provider,Github,Gitlab}.sh`
- `dev-tools/src/build.sh`
- `.claude/hooks/{session-start,post-push-usage-report}.sh`
- `.claude/hooks/lib/UsageTracking.sh`
- `tests/test_external_command_server.sh`
- `tests/test_vcs_provider.sh`
- 本ドキュメント

削除:
- 上記に対応する全`.ps1`ファイル

変更:
- `.claude/settings.json`（hook `command`を`powershell.exe`からgit bash本体のフルパスへ）
- `.claude/skills/issue-mr-flow/SKILL.md`（コード例・関数名の更新、前提に`jq`を追加）
- `dev-tools/docs/spec/issue-mr-workflow.md`（コンポーネント構成・提供関数表・各hookの説明を更新）
- `dev-tools/docs/spec/distribution.md`（`build.ps1`→`build.sh`）
- `tests/README.md`
- `.claude/rules/directory-structure.md`（`.sh`配置ルール・jq前提の追記）
- `.claude/rules/shell-script-style.md`（新規。bashスクリプトの規約）
- `.claude/rules/powershell-encoding.md`（「PowerShellを直接書く場合のみ適用」である旨を明確化）

## 設定項目

新規のSettings値は不要。

## 未決定事項・懸念点

- **GitLab版の実機動作未検証**: `Gitlab.sh`はPowerShell版`Gitlab.ps1`と同様、このリポジトリの
  実remoteがGitHubのみのため未検証。GitLabリポジトリで実際に使う前に動作確認が必要。
- **hook起動コマンドのパス固定**: `.claude/settings.json`のgit bashフルパスは、単一開発者である
  このマシンの標準インストール先を前提にしている。将来複数人での利用や別マシンへの展開時は、
  環境ごとにパスを書き換える必要がある（`${CLAUDE_PROJECT_DIR}`のような変数展開の仕組みが
  `command`フィールド自体には無いため、環境変数での切り替えはできない）。
- **"PowerShellのまま残すべきスクリプト"の実例が無い**: 本issueの対応で最終的に全PowerShell
  スクリプトがbash化されたため、判断基準（git bashで実行不可能なもの）を実際に適用した例が
  今のところ無い。今後、PowerShell固有機能（COM操作・.NETクラスの直接利用等）に依存する新規
  スクリプトが必要になった場合の判断基準は、その時点で改めて検討する。
- **`jq`のインストール確認手順が無い**: `gh`/`glab`と異なりインストール状況を確認する仕組みが
  スクリプト側に無い。未インストール時は`jq: command not found`のような分かりにくいエラーになる
  （実害は小さいが改善余地がある）。
