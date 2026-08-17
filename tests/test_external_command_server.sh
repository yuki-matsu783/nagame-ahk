#!/usr/bin/env bash
#
# ExternalCommandServer(docs/spec/external-command-server.md)の結合スモークテスト（bash版）。
# 設計: .claude/scripts/docs/spec/shell-scripts.md
#
# src/main.ahk を実際に起動し、TCPクライアントとして接続して Auth および代表的なコマンドを
# 送受信し、レスポンスが期待通りかを確認する。テスト終了後は起動したAutoHotkeyプロセスを終了する。
#
# 確認しているのは低リスクなコマンドのみ(SendKeys/MouseClick/PlayMacro/GUI系ダイアログは
# 実機の入力・表示を伴うため対象外。手動で確認すること)。
#
# 注意: 副作用があります: クリップボードの内容を書き換える、トレイにトースト通知を表示する。
# 既に常駐版nagame-ahkが起動していると多重起動になり誤検知するため、実行前に一旦終了しておくこと。
# (このスクリプトはテスト対象のAutoHotkeyプロセスを名前で判別して終了するため、無関係な
# AutoHotkeyスクリプトが同時に動いていると巻き込んで終了させてしまう点に注意)
#
# 注意: Settings.ServerPort / Settings.AuthToken を変更した場合は、下記の PORT / AUTH_TOKEN も
# 合わせて変更すること。
#
# 注意（git bashのパス変換）: `tasklist`/`taskkill` のDOS形式フラグ（`/FI` 等）はgit bashの
# パス自動変換に巻き込まれるため `//FI` のように先頭を`//`にする（詳細:
# .claude/scripts/docs/spec/shell-scripts.md「git bashのパス変換」節）。
#
# 使い方:
#     tests/test_external_command_server.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AHK_EXE="C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe"
MAIN_SCRIPT="${REPO_ROOT}/src/main.ahk"
LOG_PATH="${REPO_ROOT}/nagame-ahk.log"
SERVER_HOST="127.0.0.1"
PORT=39321        # Settings.ServerPort の既定値
AUTH_TOKEN="ahk-rira"  # Settings.AuthToken の既定値

PASSED=0
FAILURES=0

assert_equal() {
  local actual="$1" expected="$2" label="$3"
  if [ "$actual" = "$expected" ]; then
    PASSED=$((PASSED + 1))
  else
    FAILURES=$((FAILURES + 1))
    echo "FAIL: ${label} expected=[${expected}] actual=[${actual}]"
  fi
}

# condition には "true"/"false" 文字列を渡す（jqの真偽値出力やbashの比較結果をそのまま渡せるように）
assert_true() {
  local condition="$1" label="$2"
  if [ "$condition" = "true" ]; then
    PASSED=$((PASSED + 1))
  else
    FAILURES=$((FAILURES + 1))
    echo "FAIL: ${label} (condition was false)"
  fi
}

proc_running() {
  tasklist //FI "IMAGENAME eq AutoHotkey64.exe" //FO CSV //NH 2>/dev/null | grep -qi "AutoHotkey64.exe"
}

stop_ahk() {
  taskkill //IM AutoHotkey64.exe //F >/dev/null 2>&1 || true
}

# fd 3 に新しいTCP接続を開く（既存の接続が残っていれば先に閉じる）
tcp_connect() {
  exec 3<&- 2>/dev/null || true
  exec 3>&- 2>/dev/null || true
  exec 3<>"/dev/tcp/${SERVER_HOST}/${PORT}"
}

tcp_close() {
  exec 3<&- 2>/dev/null || true
  exec 3>&- 2>/dev/null || true
}

# コマンド(JSON文字列)を送信し、応答のJSON文字列をstdoutへ出力する。
# 接続が切断され応答を受信できなかった場合は終了コード1を返す。
send_command() {
  local json="$1"
  printf '%s\n' "$json" >&3
  local line
  if ! IFS= read -r line <&3; then
    return 1
  fi
  printf '%s' "$line"
}

# ---- 準備: 既存プロセスを止めてから起動 ----
stop_ahk
[ -f "$LOG_PATH" ] && rm -f "$LOG_PATH"

"$AHK_EXE" "$MAIN_SCRIPT" &
sleep 2

if proc_running; then
  assert_true "true" "main.ahkのプロセスが起動していること"
else
  assert_true "false" "main.ahkのプロセスが起動していること"
fi

cleanup() {
  tcp_close
  stop_ahk
}
trap cleanup EXIT

# ---- 未認証状態: 誤トークンは拒否され、以降の書き込みも失敗する(切断されている) ----
tcp_connect
res="$(send_command '{"id":"1","command":"Auth","params":{"token":"wrong-token"}}')"
assert_equal "$(printf '%s' "$res" | jq -r '.ok')" "false" "誤トークンのAuthはok:falseを返す"
assert_equal "$(printf '%s' "$res" | jq -r '.error')" "authentication required" "誤トークンのAuthのエラーメッセージ"
sleep 0.2
disconnected="false"
if printf '%s\n' '{"id":"x","command":"ShowToast","params":{"title":"x","message":"y"}}' >&3 2>/dev/null; then
  if ! IFS= read -r _ <&3; then
    disconnected="true"
  fi
else
  disconnected="true"
fi
assert_true "$disconnected" "認証失敗後は接続がサーバー側から切断されること"
tcp_close

# ---- 未認証状態でAuth以外を送ると拒否される ----
tcp_connect
res="$(send_command '{"id":"1","command":"GetActiveWindow","params":{}}')"
assert_equal "$(printf '%s' "$res" | jq -r '.ok')" "false" "未認証でコマンドを送るとok:falseになる"
tcp_close

# ---- 正常系 ----
tcp_connect
res="$(send_command "$(jq -nc --arg token "$AUTH_TOKEN" '{id:"1", command:"Auth", params:{token:$token}}')")"
assert_equal "$(printf '%s' "$res" | jq -r '.ok')" "true" "正しいトークンでのAuthが成功すること"

res="$(send_command '{"id":"2","command":"GetActiveWindow","params":{}}')"
assert_equal "$(printf '%s' "$res" | jq -r '.ok')" "true" "GetActiveWindowが成功すること"
hwnd="$(printf '%s' "$res" | jq -r '.result.hwnd')"
assert_true "$([ "$hwnd" -gt 0 ] 2>/dev/null && echo true || echo false)" "GetActiveWindowがhwndを返すこと"

res="$(send_command '{"id":"3","command":"ListWindows","params":{}}')"
assert_equal "$(printf '%s' "$res" | jq -r '.ok')" "true" "ListWindowsが成功すること"
win_count="$(printf '%s' "$res" | jq -r '.result.windows | length')"
assert_true "$([ "$win_count" -gt 0 ] 2>/dev/null && echo true || echo false)" "ListWindowsが1件以上返すこと"

marker="nagame-ahk-test-$(date +%s)-$$"
res="$(send_command "$(jq -nc --arg text "$marker" '{id:"4", command:"SetClipboard", params:{text:$text}}')")"
assert_equal "$(printf '%s' "$res" | jq -r '.ok')" "true" "SetClipboardが成功すること"
res="$(send_command '{"id":"5","command":"GetClipboard","params":{}}')"
assert_equal "$(printf '%s' "$res" | jq -r '.result.text')" "$marker" "GetClipboardがSetClipboardした内容を返すこと(クリップボードを書き換えます)"

res="$(send_command '{"id":"6","command":"ShowToast","params":{"title":"テスト","message":"外部コマンドサーバーのスモークテストです"}}')"
assert_equal "$(printf '%s' "$res" | jq -r '.ok')" "true" "ShowToastが成功すること(トースト通知が表示されます)"

res="$(send_command '{"id":"7","command":"NoSuchCommand","params":{}}')"
assert_equal "$(printf '%s' "$res" | jq -r '.ok')" "false" "未知のコマンドはok:falseになる"
err_msg="$(printf '%s' "$res" | jq -r '.error')"
case "$err_msg" in
  "unknown command:"*) assert_true "true" "未知のコマンドのエラーメッセージ" ;;
  *) assert_true "false" "未知のコマンドのエラーメッセージ" ;;
esac

tcp_close

echo "----"
echo "passed=${PASSED} failures=${FAILURES}"
if [ "$FAILURES" -gt 0 ]; then
  exit 1
else
  exit 0
fi
