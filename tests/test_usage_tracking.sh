#!/usr/bin/env bash
#
# .claude/hooks/lib/UsageTracking.sh の単体テスト。
# 設計: dev-tools/docs/spec/issue-mr-workflow.md「対応工数レポート」節
#
# 対象: gh/glab呼び出しを伴わない純粋ロジック（_usage_aggregate_transcript, _usage_merge_state,
# _usage_merge_agent_state, _usage_sync_session_logs, _usage_aggregate_and_merge_subagents）。
# 合成JSONLフィクスチャ（jq -ncで生成、$TMPDIR配下）に対する集計結果を検証する。
# _usage_sync_session_logsのコピー処理は、疑似`~/.claude/projects`ツリーを$TMPDIR配下に自作して
# 検証する（実ホームディレクトリには一切触れない）。
#
# 使い方:
#     bash tests/test_usage_tracking.sh
#
# 副作用: $TMPDIR配下に一時ファイル・ディレクトリを作成・削除するのみ。

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

# --- _usage_aggregate_transcript: agentId等サブエージェント由来の余分なフィールドがあっても
#     既存の集計ロジックに影響しないことの回帰テスト ---

extra_entry="$(jq -nc '{type: "assistant", gitBranch: "b", timestamp: "2026-01-01T00:00:00Z",
  agentId: "x", isSidechain: true, sessionId: "parent",
  message: {model: "m", usage: {input_tokens: 1, output_tokens: 1},
    content: [{type: "tool_use", name: "Bash"}]}}')"
printf '%s\n' "$extra_entry" > "$TMP_FILE"
result="$(_usage_aggregate_transcript "$TMP_FILE" "b")"
assert_equal "$(printf '%s' "$result" | jq -r '.assistantCount')" "1" \
  "_usage_aggregate_transcript: agentId等の余分なフィールドがあってもassistantCountは正しく集計される"
assert_equal "$(printf '%s' "$result" | jq -r '.tools.Bash')" "1" \
  "_usage_aggregate_transcript: agentId等の余分なフィールドがあってもtool_use集計は正しく動く"

# --- _usage_merge_agent_state: agentId単位のスナップショット・agentType単位の表示集約 ---

current_a1="$(jq -nc '{tokens: {}, tools: {}, assistantCount: 1, activeSeconds: 30}')"
merged_agent_a="$(_usage_merge_agent_state "{}" "agent1" "Explore" "$current_a1" "feature-x")"
assert_equal "$(printf '%s' "$merged_agent_a" | jq -r '.agents.agent1.agentType')" "Explore" \
  "_usage_merge_agent_state: agentIdごとの累計スナップショットにagentTypeが保存される"
assert_equal "$(printf '%s' "$merged_agent_a" | jq -r '.sinceLastPush.subagentsByType.Explore.activeSeconds')" "30" \
  "_usage_merge_agent_state: 初回のagentId分がsubagentsByType[agentType]へ加算される"

# 異なるagentId・同一agentType: 表示集約（subagentsByType）では合算される
current_a2="$(jq -nc '{tokens: {}, tools: {}, assistantCount: 1, activeSeconds: 45}')"
merged_agent_b="$(_usage_merge_agent_state "$merged_agent_a" "agent2" "Explore" "$current_a2" "feature-x")"
assert_equal "$(printf '%s' "$merged_agent_b" | jq -r '.sinceLastPush.subagentsByType.Explore.activeSeconds')" "75" \
  "_usage_merge_agent_state: 異なるagentIdでも同一agentType分はsubagentsByType上で合算される（30+45）"
assert_true "$(printf '%s' "$merged_agent_b" | jq -r 'if (.agents | has("agent1")) and (.agents | has("agent2")) then "true" else "false" end')" \
  "_usage_merge_agent_state: agentIdごとのスナップショットは個別に保持される"

# 同一agentIdへの2回目の呼び出し: agentId単位のスナップショット差分のみが加算され、二重計上されない
current_a1_grown="$(jq -nc '{tokens: {}, tools: {}, assistantCount: 2, activeSeconds: 50}')"
merged_agent_c="$(_usage_merge_agent_state "$merged_agent_b" "agent1" "Explore" "$current_a1_grown" "feature-x")"
assert_equal "$(printf '%s' "$merged_agent_c" | jq -r '.sinceLastPush.subagentsByType.Explore.activeSeconds')" "95" \
  "_usage_merge_agent_state: 同一agentIdの2回目はスナップショット差分（50-30=20）のみが加算される（75+20）"

# --- _usage_sync_session_logs / _usage_aggregate_and_merge_subagents: 疑似~/.claude/projectsツリーからの
#     コピー・集計（実ホームディレクトリには一切触れない） ---

FAKE_ROOT="$(mktemp -d)"
trap 'rm -f "$TMP_FILE"; rm -rf "$FAKE_ROOT"' EXIT

mkdir -p "${FAKE_ROOT}/home_projects/sess1/subagents"
mk_entry "2026-01-01T00:00:00Z" "feature-x" > "${FAKE_ROOT}/home_projects/sess1.jsonl"
jq -nc '{type: "assistant", gitBranch: "feature-x", timestamp: "2026-01-01T00:00:00Z",
  agentId: "a1", message: {model: "m", usage: {input_tokens: 1, output_tokens: 1}, content: []}}' \
  > "${FAKE_ROOT}/home_projects/sess1/subagents/agent-a1.jsonl"
jq -nc '{agentType: "Explore"}' > "${FAKE_ROOT}/home_projects/sess1/subagents/agent-a1.meta.json"

log_dir="$(_usage_sync_session_logs "${FAKE_ROOT}/repo" "feature-x" "sess1" "${FAKE_ROOT}/home_projects/sess1.jsonl")"

assert_true "$([ -f "${log_dir}/main.jsonl" ] && echo true || echo false)" \
  "_usage_sync_session_logs: メインtranscriptがローカルへコピーされる"
assert_true "$([ -f "${log_dir}/subagents/agent-a1.jsonl" ] && echo true || echo false)" \
  "_usage_sync_session_logs: サブエージェントtranscriptがローカルへコピーされる"
assert_true "$([ -f "${log_dir}/subagents/agent-a1.meta.json" ] && echo true || echo false)" \
  "_usage_sync_session_logs: サブエージェントmeta.jsonがローカルへコピーされる"

merged_from_copy="$(_usage_aggregate_and_merge_subagents "{}" "$log_dir" "feature-x")"
assert_equal "$(printf '%s' "$merged_from_copy" | jq -r '.agents.a1.agentType')" "Explore" \
  "_usage_aggregate_and_merge_subagents: コピー済みディレクトリからagentTypeがmeta.json経由で読み取られる"
assert_equal "$(printf '%s' "$merged_from_copy" | jq -r '.sinceLastPush.subagentsByType.Explore.activeSeconds')" "30" \
  "_usage_aggregate_and_merge_subagents: コピー済みディレクトリから集計・マージまで一気通貫で動く"

empty_log_dir="$(mktemp -d)"
existing_noop="$(jq -nc '{foo: "bar"}')"
result_noop="$(_usage_aggregate_and_merge_subagents "$existing_noop" "$empty_log_dir" "feature-x")"
assert_equal "$result_noop" "$existing_noop" \
  "_usage_aggregate_and_merge_subagents: subagentsディレクトリが無ければexistingをそのまま返す"

echo "----"
echo "passed=${PASSED} failures=${FAILURES}"
if [ "$FAILURES" -gt 0 ]; then
  exit 1
else
  exit 0
fi
