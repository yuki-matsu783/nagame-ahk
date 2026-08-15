# Plan: 開発補助スクリプトのbash化（issue #6）

## Context

`nagame-ahk`の開発フロー（issue-mr-flow）や配布・テストの補助スクリプトはこれまでPowerShellで
書かれてきたが、PowerShellはWSL等の非Windows的なシェル環境からは扱いにくい。
[issue #6](https://github.com/yuki-matsu783/nagame-ahk/issues/6)は、git bash経由で同等のことが
行えるスクリプトはbash化し、行えないものだけPowerShellのまま残すことを求めている。
対象ブランチは`feature-6-bash`（Draft PR #18）。Hook（`.claude/hooks/*.ps1`）の変換も含めるかを
ユーザーに確認したところ、含める方針で承認済み。

## 事前調査で確認した実行環境（このマシンで検証済み）

- git bash: mingw64同梱のbash 5.2。`/dev/tcp`対応、`ps -W`でWindowsプロセス一覧取得可
- `jq` 1.6 インストール済み → bash側のJSON操作の新規前提として追加する
- `gh` CLI インストール済み、AutoHotkey v2 インストール済み（実機比較用）
- 環境変数はWindows由来の大文字名でアクセスする必要がある（`$PROGRAMFILES`は使えるが`$ProgramFiles`は空）
- `tasklist.exe`の出力はシステムコードページ(cp932)のままなので、日本語メッセージの文字列一致は避け、
  終了コードや`findstr`/イメージ名一致で判定する

## 変換対象と方針

| ファイル | 方針 |
|---|---|
| `dev-tools/src/vcs/Provider.ps1` `Github.ps1` `Gitlab.ps1` | bash化して`.sh`に置き換え（`.ps1`削除）。issue-mr-flow全体で毎回使う中核 |
| `dev-tools/src/build.ps1` | bash化して`.sh`に置き換え |
| `.claude/hooks/session-start.ps1` `.claude/hooks/post-push-usage-report.ps1` `.claude/hooks/lib/UsageTracking.ps1` | bash化して`.sh`に置き換え、`.claude/settings.json`のhook `command`を`bash`に変更 |
| `tests/test_external_command_server.ps1` | bash化を試み、実機で新旧の結果が一致すれば置き換え。困難なら理由を明記しPowerShellのまま残す |

GitLab版(`Gitlab.sh`)は既存`Gitlab.ps1`と同様「未検証」（このリポジトリのremoteはGitHubのみ）のまま
構造だけ移植する。関数名はPowerShellの`Verb-Noun`からbashのsnake_case関数へ移植する
（例: `Get-Issue`→`get_issue`、`New-IssueBranch`→`new_issue_branch`）。

## 実施内容

1. **設計ドキュメント作成**
   - 新規`dev-tools/docs/spec/shell-scripts.md`: bash化の方針・スクリプト一覧・前提（jq追加）・
     既知の制約（cp932/tasklist、環境変数名の違い等）をまとめる
   - `dev-tools/docs/spec/issue-mr-workflow.md` / `distribution.md`のスクリプト言語記述箇所を更新
2. `dev-tools/src/vcs/Provider.sh` `Github.sh` `Gitlab.sh`を新規作成、`.ps1`を削除
3. `.claude/skills/issue-mr-flow/SKILL.md`のPowerShellコード例を
   `source dev-tools/src/vcs/Provider.sh`（Bashツール前提）に更新
4. `dev-tools/src/build.sh`を新規作成、`.ps1`を削除
5. `.claude/hooks/session-start.sh` `.claude/hooks/post-push-usage-report.sh`
   `.claude/hooks/lib/UsageTracking.sh`を新規作成、`.ps1`を削除、
   `.claude/settings.json`のhook定義を`bash`呼び出しに変更
6. `tests/test_external_command_server.ps1`の変換可否を実機検証し、可能なら`.sh`へ置き換え
7. 受け入れ条件「スクリプトをテストするためのスクリプトを作成する」に対応し、
   `tests/test_vcs_provider.sh`（外部API呼び出しを伴わない純粋ロジック部分の単体テスト）を
   新規作成、`tests/README.md`に追記
8. AIアセット反映: 新規`.claude/rules/shell-script-style.md`（LF・UTF-8無BOM・
   `set -euo pipefail`・jq前提などのbash規約）を作成し、`directory-structure.md`にjq前提・`.sh`配置
   ルールを追記、`powershell-encoding.md`は「PowerShellを直接書く場合のみ適用」である旨を明確化
9. セッション開始時に先に作成していた重複plan（`plans/bashify-dev-scripts.md`）を削除し、本ファイルに一本化する

## 対象外（やらないこと）

- `src/`（AHK本体）のロジック変更
- GitLab版の実機動作確認
- WSL環境そのものでの動作確認（Windows実機のgit bashでのみ確認）
- CI/CD化

## 検証方法

- 各`.sh`: `bash -n <file>`で構文チェック
- VCS層: `source dev-tools/src/vcs/Provider.sh`後、`get_issue 6`等をこのセッションから実行し
  PowerShell版と同じ結果になることを確認
- build.sh: 実行してexeが生成されることを確認
- hook: 模擬stdin JSONを流し込みPowerShell版と出力JSON構造が一致することを確認。
  実ブランチでの`git push`実機テストも行う
- test_external_command_server: 実機で`src/main.ahk`を起動し新スクリプトを実行、
  PowerShell版と同じpassed/failures件数になることを確認
- `tests/test_vcs_provider.sh`: 追加した単体テストが全てpassすることを確認
