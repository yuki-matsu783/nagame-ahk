---
title: bashスクリプトの規約
type: rule
description: 開発補助bashスクリプトの保存形式・エラー方針・命名規則等を定めたルール
tags: [bash, shell-script, rule]
keywords: [bashスクリプト, jq, サブシェル, 命名規則, パス変換, 文字コード, 改行コード, claude-code-hook]
---

# bashスクリプトの規約

issue #6でリポジトリ内の開発補助スクリプトを全てPowerShellからbashへ移行した際に定めた規約。
設計方針・移行の経緯は [.claude/scripts/docs/spec/shell-scripts.md](../../.claude/scripts/docs/spec/shell-scripts.md)
を参照（このファイルは規約のみを記載し、経緯の重複は避ける）。

## 前提・保存形式

- 実行環境はgit bash（Git for Windows付属のMSYS bash）。WSL/Linux実機での動作確認は行っていない
  （`.claude/scripts/docs/spec/shell-scripts.md`の未決定事項参照）。
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
  外部依存としてインストールが必要。`.claude/scripts/docs/spec/shell-scripts.md`「前提」参照）。
- 関数の戻り値はPSCustomObjectに代えてJSON文字列をstdoutへ出力する設計にする。呼び出し側は
  `jq`でフィールドを取り出す（例: `get_issue 6 | jq -r '.title'`）。JSONのキー名はPascalCaseでは
  なくcamelCase（`number`/`title`/...）に統一する。
- Windows PowerShell 5.1の`ConvertFrom-Json`が`-AsHashtable`を持たないための回避策
  （`ConvertTo-HashtableDeep`等）は、jqのネイティブなJSON操作機能により不要になる。移植の際に
  引き継がないこと。
- **Windows版jq（`C:\Program Files\jq\jq.exe`等のネイティブ実行ファイル）は`strptime`/`mktime`が
  未実装**（実機確認: `jq -n '"..." | fromdateiso8601'` が
  `strptime/1 not implemented on this platform`で失敗する。issue #28対応時に判明）。
  `fromdateiso8601`/`fromdate`/`strptime`/`mktime`はいずれも内部で`strptime`/`mktime`を使うため
  **使用不可**（日付文字列→エポック秒の変換に使えない）。`gmtime`/`strftime`（エポック秒→日付文字列の
  向き）は問題なく動作する。日付文字列→エポック秒の変換が必要な場合は、`strptime`に依存しない
  自前実装（`days_from_civil`アルゴリズムによる四則演算のみの変換）を使う。実装例・境界値検証は
  `.claude/hooks/lib/UsageTracking.sh`の`epoch_from_iso8601`を参照。
  - 加えて、この`strptime`未実装エラーが、直前段階の`try ... catch empty`と組み合わさると、
    jqがエラーメッセージを一切出さず出力全体が`null`になるという実機確認済みの現象があった
    （原因調査が非常に困難だったため記録に残す）。日付変換を含むjqフィルタを`try/catch`と
    組み合わせる場合は、この現象を疑ってまず日付変換部分だけを単体で動作確認すること。
- **大きなJSONを`--argjson`/`--arg`等のコマンドライン引数としてjqへ渡さない**（issue #37対応時に
  実機確認: 対応工数レポートの集計で、外部ファイル・コマンド出力等に由来する可変長のJSON
  データを`jq -n --argjson entries "$data" ...`という形で渡していたところ、データが数十KB程度
  （実例: transcriptの新規行32件、約120KB）でも`jq: Argument list too long`（終了コード126）で
  jqの起動自体が失敗した。Windowsのプロセス生成時のコマンドライン長上限（実測でおよそ32KB程度）に
  容易に達するため）。**渡すデータのサイズがファイルサイズ・ユーザー入力等に応じて可変・無制限に
  なりうる場合は、一時ファイルへ書き出すか、そもそも元のファイルパスをjqへ渡して`-R -n`と
  `inputs`でjq側に読ませる**（`.claude/hooks/lib/UsageTracking.sh`の`_usage_aggregate_transcript`/
  `_usage_aggregate_new_lines`が実例。後者は元々「シェル変数へ切り出してから引数で渡す」2関数
  構成だったが、この問題が判明し1関数（常にファイルパスを渡す設計）へ統合した）。`--argjson`/
  `--arg`が安全なのは、渡す値のサイズが呼び出し元のロジックで明確に小さいと保証できる場合
  （集計済みのサマリ値、固定長の設定値等）に限る。**この問題はコマンドの起動自体が失敗するため、
  失敗時に何もエラー出力が無いように見えるケース（`set -e`配下でエラーメッセージが握りつぶされる
  呼び出し方をしている場合）もあり、`jq: Argument list too long`という文言を直接見ないまま
  「処理が急に動かなくなった」としか気づけないことがある点に注意する。**
- **上記の失敗が別の関数へ波及して恒久化するケースに注意する**: あるjq呼び出しが上記の理由で
  失敗し、その戻り値を状態ファイルへ書き込むはずだった処理が（`set -e`により）実行されないまま
  終わっても、**それより前の別の書き込み処理が既に完了している場合**、ファイルが空／壊れた
  状態のまま残ることがある（issue #37の対応工数レポートで実際に発生: 状態ファイルが0バイトに
  壊れた状態で、カーソル的な位置情報だけが正常に進んでいた）。壊れた状態ファイルを次回`--argjson`で
  読み込もうとすると、空文字列は不正なJSONとして扱われ**同じ理由で毎回失敗し続け、恒久的に
  回復不能になる**。外部状態ファイルを読み込んで`--argjson`等へ渡す前には、内容が空でなく
  有効なJSONであることを検証し（例: `[ -n "$content" ] && printf '%s' "$content" | jq -e .
  >/dev/null 2>&1`）、無効なら「状態なし」の既定値にフォールバックする自己回復ロジックを
  入れておくと安全（`sync_usage_state`の`existing`読み込みが実例）。
  - **`jq -e .`は空文字列の入力に対して失敗を検知できないことがある**（実機確認:
    `printf '%s' "" | jq -e .`が終了コード0を返した）。空文字列チェック（`[ -n "$content" ]`）を
    `jq -e .`の判定より先に行うこと。

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
- Windows版のnative `jq`バイナリ（`C:\Program Files\jq\jq.exe`のような、MSYS版ではなくWindows
  ネイティブ実行ファイルとして配布されるもの）は、標準出力をファイルへリダイレクトする際に行末へ
  CRを付与することがある（実機確認: `.claude/scripts/src/extract-frontmatter.sh`実装時。git bashの
  `core.autocrlf=input`設定下ではコミット時に自動でLFへ変換されるため実害は限定的だが、コミット前の
  ワーキングツリー上ではCRLFが混入する）。jqの出力を直接ファイルへ書き出す箇所は`tr -d '\r'`を
  挟んでLF改行に統一する。
  - **同じCR付与は、ファイルリダイレクトだけでなくコマンド置換・パイプでも起きる**（issue #34
    対応時に実機確認: `printf '%s' '{"a":1,"b":2}' | jq -r 'keys[]' | od -c` で各行末に`\r`が
    付くことを確認）。`for x in $(... | jq -r ... )`のようなループでは、`$(...)`によるコマンド
    置換が「文字列全体の末尾」の改行しか取り除かないため、**要素が2件以上ある場合、最後の要素
    以外はループ変数へ`\r`が付いたまま渡る**（最後の要素だけ、末尾の`\r\n`ごと丸ごと取り除かれる
    ため`\r`が付かない）。この状態で`jq --arg`によるキー参照（`.[$var]`等）を行うと、
    最後の要素以外は文字列不一致で`null`になる。要素が1件しかない場合は表面化しないため、
    複数要素を扱うループを新設・変更する際に見落としやすい（`.claude/hooks/post-push-usage-report.sh`
    で実例あり）。対策は同じく`| tr -d '\r'`を、`for`に渡す`$(...)`の直前に挟むこと。

## Claude Code hookとして登録する場合

`.claude/settings.json`のhook `command`は `"bash"` とだけ指定する（フルパス直書きはしない。他環境
への移植性を優先）。ただし環境によっては、Windowsの`PATH`で`C:\Windows\System32\bash.exe`
（WSL起動用スタブ）が`Git\bin`より先に解決され、エラーも出さずgit bashではなくWSLが起動する
可能性がある（このマシンで実機確認済み。Git for Windowsのインストーラは既定で`bash.exe`のある
`Git\bin`を`PATH`に追加しないことが原因）。**システム環境変数（`Machine`スコープ）の`Path`に
`Git\bin`（例: `C:\Program Files\Git\bin`）を`C:\Windows\System32`より前に来る位置で追加する**
ことで解決する（ユーザー環境変数に追加するだけでは効果が無い。Windowsの有効PATHはシステム環境変数
側が先に連結されるため）。具体的な手順は
[.claude/scripts/docs/spec/shell-scripts.md](../../.claude/scripts/docs/spec/shell-scripts.md)
「Claude Code hookの起動コマンド」参照）。`${CLAUDE_PROJECT_DIR}`（Windows形式パス）はこの
`bash.exe`へargvで渡しても正しく解決される。

## テスト

- 副作用の無い純粋ロジック（文字列変換・正規表現マッチ等）は、外部コマンド呼び出しを伴わない
  単体テストスクリプトを`tests/`に置く（実例: `tests/test_vcs_provider.sh`）。
- 実プロセス起動・TCP通信等の結合確認は、既存のAHKテストと同じ「`passed=N failures=N`を出力し
  失敗があれば終了コード1」という規約に合わせる（実例: `tests/test_external_command_server.sh`）。
- 作成した`.sh`は最低限 `bash -n <file>` で構文チェックする。
