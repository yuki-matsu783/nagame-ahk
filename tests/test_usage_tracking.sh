#!/usr/bin/env bash
#
# .claude/hooks/lib/UsageTracking.sh の単体テスト。
# 設計: dev-tools/docs/spec/issue-mr-workflow.md「対応工数レポート」節
#
# 対象: gh/glab呼び出しを伴わない純粋ロジック（_usage_aggregate_transcript, _usage_merge_state）。
# 合成JSONLフィクスチャ（jq -ncで生成、$TMPDIR配下）に対する集計結果を検証する。
#
# 使い方:
#     bash tests/test_usage_tracking.sh
#
# 副作用: $TMPDIR配下に一時ファイルを作成・削除するのみ。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/.claude/hooks/lib/UsageTracking.sh"

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

assert_true() {
  local condition="$1" label="$2"
  if [ "$condition" = "true" ]; then
    PASSED=$((PASSED + 1))
  else
    FAILURES=$((FAILURES + 1))
    echo "FAIL: ${label} (condition was false)"
  fi
}

# assistantエントリを1件、コンパクトJSON（1行）で出力する。
mk_entry() {
  local ts="$1" branch="$2"
  jq -nc --arg ts "$ts" --arg branch "$branch" \
    '{type: "assistant", gitBranch: $branch, timestamp: $ts,
      message: {model: "m", usage: {input_tokens: 1, output_tokens: 1}, content: []}}'
}

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

# --- _usage_aggregate_transcript: activeSeconds ---

# entryが1件のみ: tail buffer（既定30秒）のみが計上される（参考実装claude-work-timerの
# "returns single segment for one event" 相当）
mk_entry "2026-01-01T00:00:00Z" "b" > "$TMP_FILE"
result="$(_usage_aggregate_transcript "$TMP_FILE" "b")"
assert_equal "$(printf '%s' "$result" | jq -r '.activeSeconds')" "30" \
  "_usage_aggregate_transcript: entry1件のみでもtail buffer分が計上される"

# 閾値未満のgap（120秒 < 300秒）: gapがそのまま加算され、末尾にtail bufferが1回加算される
{
  mk_entry "2026-01-01T00:00:00Z" "b"
  mk_entry "2026-01-01T00:02:00Z" "b"
} > "$TMP_FILE"
result="$(_usage_aggregate_transcript "$TMP_FILE" "b")"
assert_equal "$(printf '%s' "$result" | jq -r '.activeSeconds')" "150" \
  "_usage_aggregate_transcript: 閾値未満のgapは加算され末尾にtail bufferが1回加算される（120+30）"

# 閾値以上のgap（480秒 >= 300秒）: gapは加算されず、閉じたセグメントと末尾セグメントそれぞれに
# tail bufferが加算される
{
  mk_entry "2026-01-01T00:00:00Z" "b"
  mk_entry "2026-01-01T00:08:00Z" "b"
} > "$TMP_FILE"
result="$(_usage_aggregate_transcript "$TMP_FILE" "b")"
assert_equal "$(printf '%s' "$result" | jq -r '.activeSeconds')" "60" \
  "_usage_aggregate_transcript: 閾値以上のgapは除外されセグメント終端のtail bufferが2回分計上される（30+30）"

# ちょうど閾値（300秒）のgapは「待ち」側として扱う（参考実装claude-work-timerの
# "handles exact threshold as idle" 相当）
{
  mk_entry "2026-01-01T00:00:00Z" "b"
  mk_entry "2026-01-01T00:05:00Z" "b"
} > "$TMP_FILE"
result="$(_usage_aggregate_transcript "$TMP_FILE" "b")"
assert_equal "$(printf '%s' "$result" | jq -r '.activeSeconds')" "60" \
  "_usage_aggregate_transcript: gapがちょうど閾値の場合は待ち側として扱われる"

# 複数の閾値超gap（3セグメント）: セグメントの数だけtail bufferが積み上がる
{
  mk_entry "2026-01-01T00:00:00Z" "b"
  mk_entry "2026-01-01T00:01:00Z" "b"
  mk_entry "2026-01-01T00:11:00Z" "b"
  mk_entry "2026-01-01T00:12:00Z" "b"
  mk_entry "2026-01-01T00:27:00Z" "b"
  mk_entry "2026-01-01T00:28:00Z" "b"
} > "$TMP_FILE"
result="$(_usage_aggregate_transcript "$TMP_FILE" "b")"
assert_equal "$(printf '%s' "$result" | jq -r '.activeSeconds')" "270" \
  "_usage_aggregate_transcript: 複数の閾値超gapでセグメント数分tail bufferが積み上がる（60×3+30×3）"

# gitBranch不一致entryは除外される（tokens集計と同じ既存フィルタがactiveSecondsにも効くことを確認）
{
  mk_entry "2026-01-01T00:00:00Z" "other-branch"
  mk_entry "2026-01-01T00:02:00Z" "b"
} > "$TMP_FILE"
result="$(_usage_aggregate_transcript "$TMP_FILE" "b")"
assert_equal "$(printf '%s' "$result" | jq -r '.assistantCount')" "1" \
  "_usage_aggregate_transcript: gitBranch不一致entryはassistantCountから除外される"
assert_equal "$(printf '%s' "$result" | jq -r '.activeSeconds')" "30" \
  "_usage_aggregate_transcript: gitBranch不一致entryは直前entryとして扱われずtail bufferのみになる"

# --- _usage_merge_state: activeSeconds delta ---

# 初回push（セッション未記録）: prevActiveSeconds=0として扱われ、currentがそのままdeltaになる
current_1="$(jq -nc '{tokens: {}, tools: {}, assistantCount: 1, activeSeconds: 30}')"
merged_1="$(_usage_merge_state "{}" "$current_1" "sessionA" "feature-x")"
assert_equal "$(printf '%s' "$merged_1" | jq -r '.sinceLastPush.activeSeconds')" "30" \
  "_usage_merge_state: 初回push（セッション未記録）はcurrentの値がそのままdeltaになる"
assert_equal "$(printf '%s' "$merged_1" | jq -r '.sessions.sessionA.lastActiveSeconds')" "30" \
  "_usage_merge_state: 初回pushでセッションのlastActiveSecondsが保存される"

# 2回目以降のpush: 前回スナップショットとの差分が加算される。既存のsinceLastPush（前回投稿分から
# 繰り越し）にも積み上がることを確認する
current_2="$(jq -nc '{tokens: {}, tools: {}, assistantCount: 2, activeSeconds: 150}')"
merged_2="$(_usage_merge_state "$merged_1" "$current_2" "sessionA" "feature-x")"
assert_equal "$(printf '%s' "$merged_2" | jq -r '.sinceLastPush.activeSeconds')" "150" \
  "_usage_merge_state: 2回目以降のpushはdelta（150-30=120）が前回のsinceLastPush（30）へ加算される"
assert_equal "$(printf '%s' "$merged_2" | jq -r '.sessions.sessionA.lastActiveSeconds')" "150" \
  "_usage_merge_state: 2回目以降のpushでlastActiveSecondsが最新値へ更新される"

# tail bufferの暫定加算が実gapへ置き換わっても差分は負にならない（単調非減少性）ことを確認する。
# 1件のみのセッション（activeSeconds=30、tail buffer分のみ）の後、
# 同じ末尾entryのすぐ後（5秒後）に2件目が来た場合を想定する。
current_single="$(jq -nc '{tokens: {}, tools: {}, assistantCount: 1, activeSeconds: 30}')"
merged_single="$(_usage_merge_state "{}" "$current_single" "sessionB" "feature-x")"
# 2件目追加後の再集計結果を模した値（5秒gap + 新しい末尾tail buffer = 5+30=35）
current_grown="$(jq -nc '{tokens: {}, tools: {}, assistantCount: 2, activeSeconds: 35}')"
merged_grown="$(_usage_merge_state "$merged_single" "$current_grown" "sessionB" "feature-x")"
# 「1回目のsinceLastPushより2回目の方が小さくない」ことを検証する（単調非減少性の確認）
prev_since="$(printf '%s' "$merged_single" | jq -r '.sinceLastPush.activeSeconds')"
new_since="$(printf '%s' "$merged_grown" | jq -r '.sinceLastPush.activeSeconds')"
assert_true "$([ "$new_since" -ge "$prev_since" ] && echo true || echo false)" \
  "_usage_merge_state: tail bufferの暫定加算が実gapへ置き換わってもsinceLastPushは単調非減少である"

echo "----"
echo "passed=${PASSED} failures=${FAILURES}"
if [ "$FAILURES" -gt 0 ]; then
  exit 1
else
  exit 0
fi
