# worklog: shimmying-wibbling-simon

対象: issue #6 開発補助スクリプトのbash化（2026-08-16）。
plan: `plans/shimmying-wibbling-simon.md`

## 試したこと

- 事前調査: git bash (`/dev/tcp`対応, `ps -W`), `jq` 1.6, `gh` CLI, AutoHotkey v2 の実機確認
- `tasklist.exe` 出力がcp932のままbashに渡ると文字化けすることを確認（メッセージの文字列一致は避ける方針に）
- `$ProgramFiles`（PowerShell流）は空、`$PROGRAMFILES`（Windows由来の大文字）は値が入ることを確認

## うまくいったこと

- `dev-tools/src/vcs/Provider.sh` `Github.sh` `Gitlab.sh` を新規作成し`.ps1`を削除。
  戻り値はPSCustomObjectの代わりにJSON文字列（camelCaseキー）をstdoutへ出力し、呼び出し側はjqで
  フィールドを取り出す設計にした
- `get_issue 6`・`get_workflow_config`・`to_slug`・`test_issue_sections`・`get_mr_for_branch`・
  `get_issue_number_from_branch`を実データ（issue #6, PR #18, ブランチ`feature-6-bash`/`main`）で
  実行し、PowerShell版と同じ結果になることを確認
- `get_mr_unresolved_comments`のjqフィルタを、実PR(#17, #18)に加えて合成したGraphQLレスポンス
  fixture（resolved/unresolved混在・line=null・diffHunkあり/なし）で検証し、PowerShell版と同じ
  整形結果（`[review unresolved threadId=... path:line] author: body` 等）になることを確認
- 書き込み系関数（`new_issue_branch`/`new_draft_merge_request`/`add_mr_thread_reply`/
  `add_mr_comment`）は実ブランチ・実PRを新規に汚さないため実行テストはせず、コードレビュー
  （PowerShell版とのdiff相当の1:1移植）で確認するにとどめた

## ダメだったこと

- `build.sh`の初回実装で `/in` `/out` `/base` `/icon` をそのまま渡したところ、git bash（MSYS）が
  単一スラッシュ引数を「POSIXパスらしき文字列」と誤認しWindowsパスへ自動変換してしまい、
  `Ahk2Exe.exe`が`Unrecognised parameter`エラーダイアログを出して停止（フォアグラウンドで
  ハングしツールタイムアウトに達した）。`//in` `//out` `//base` `//icon`（先頭 `//`）に
  変更することでMSYSの自動変換を回避でき解決。`tasklist`/`taskkill`のDOS形式フラグでも
  同じ対策が必要（`shell-scripts.md`に反映予定）

- `.claude/hooks/session-start.sh` `.claude/hooks/post-push-usage-report.sh`
  `.claude/hooks/lib/UsageTracking.sh` を新規作成、`.ps1`版を削除。stdin JSON解析・
  hookSpecificOutput組み立て・transcript集計（token/tool/turn差分）・状態ファイル読み書きは
  すべてjqで実装。try/catch相当は「本体処理を関数化し `( func )` の実サブシェル境界で囲み、
  失敗をコマンド置換/サブシェルのexit codeとして呼び出し元へ伝える」パターンに統一
  （bashの`if`/`||`条件式内では`set -e`が一時停止するため、実サブシェルで囲まないと
  内部の失敗で早期終了してくれない点に注意。`shell-scripts.md`に反映予定）
- `session-start.sh`は模擬stdin JSON（agent_idあり/なし、正常系）で、`post-push-usage-report.sh`は
  スタブ化した`Provider.sh`を使った隔離リポジトリでの結合テスト（git push検知・コメント本文組み立て・
  状態リセット・agent_id/非push/transcript無しの各早期リターン）で検証し、期待通りの結果を確認
- `UsageTracking.sh`のtranscript集計・状態マージのjqロジックは、合成JSONLフィクスチャ
  （複数ブランチ混在・不正行・空行・null message混在、および複数回sync＋push後リセット＋再syncの
  シーケンス）で検証し、差分計算・リセット後の再蓄積が期待通りになることを確認
- `.claude/settings.json`のhook `command`を`powershell.exe`から`bash.exe`へ変更する際、素の
  `"command": "bash"`はこのマシンでは`C:\Windows\System32\bash.exe`（WSL起動用スタブ）に
  解決されてしまうことが判明（`where.exe bash`で確認）。git bash本体
  `C:\Program Files\Git\bin\bash.exe`をフルパスで指定する必要がある（`shell-scripts.md`に反映予定）
- `${CLAUDE_PROJECT_DIR}/.claude/hooks/session-start.sh`のようにWindows風パス
  （`C:\Users\...`）と`/`混在のパスをgit bashの`bash.exe`に直接argvで渡しても正しく解決される
  ことを実機で確認（settings.jsonが実際に組み立てる引数と同じ形で動作確認済み）

- `tests/test_external_command_server.ps1`をbash化し実機（実際に`src/main.ahk`を起動、TCP経由で
  Auth/GetActiveWindow/ListWindows/SetClipboard/GetClipboard/ShowToast/未知コマンドを検証）で
  実行、PowerShell版と同じ15件のアサーション全てpassすることを確認。`tasklist`/`taskkill`は
  `//FI` `//IM` `//F`でパス変換を回避。TCP通信は`/dev/tcp`で実装
- `tests/test_vcs_provider.sh`（`to_slug`/`test_issue_sections`/`get_issue_number_from_branch`の
  単体テスト、10件）を新規作成し全件pass
- 設計書`dev-tools/docs/spec/shell-scripts.md`、AIアセット`.claude/rules/shell-script-style.md`を
  新規作成。`dev-tools/docs/spec/issue-mr-workflow.md`・`distribution.md`・
  `.claude/rules/directory-structure.md`・`powershell-encoding.md`・`tests/README.md`・
  `docs/spec/external-command-server.md`を現状（bash化後）に合わせて更新
- 最終確認: `find . -name "*.ps1"` でリポジトリ内に`.ps1`が1件も残っていないことを確認

## ダメだったこと（追加）

- （build.shの`/in`パス変換問題は上記に記載済み。他に致命的な失敗は無し）

- PR #18レビュー対応: 「git bashのパスが通っていない場合のユーザー案内手順が無い」との指摘を受け、
  `shell-scripts.md`に`where git`でのインストール先特定〜`.claude/settings.json`書き換えまでの
  具体手順を追記。スレッドへ署名付きで返信済み

## 次の一歩

- レビュー対応をpushし、`comments all`で未解決スレッドが無いことを確認する

---
