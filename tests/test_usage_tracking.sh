#!/usr/bin/env bash
#
# .claude/hooks/lib/UsageTracking.sh の単体テスト。
# 設計: plans/inherited-gathering-biscuit.md（issue #37）,
#       dev-tools/docs/spec/issue-mr-workflow.md「対応工数レポート」節
#
# 対象: gh/glab呼び出しを伴わない純粋ロジック（_usage_aggregate_transcript, _usage_read_new_lines,
# _usage_aggregate_new_lines, _usage_merge_state, _usage_merge_agent_state,
# _usage_sync_session_logs, _usage_aggregate_and_merge_subagents, sync_usage_state,
# _usage_reset_since_last_push）。合成JSONLフィクスチャ（jq -ncで生成、$TMPDIR配下）に対する
# 集計結果を検証する。_usage_sync_session_logsのコピー処理は、疑似`~/.claude/projects`ツリーを
# $TMPDIR配下に自作して検証する（実ホームディレクトリには一切触れない）。
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

# --- _usage_aggregate_transcript: activeSeconds（ロジック変更なし。issue #37以降はactiveSeconds
#     専用として維持される） ---

# entryが1件のみ: tail buffer（既定30秒）のみが計上される
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

# ちょうど閾値（300秒）のgapは「待ち」側として扱う
{
  mk_entry "2026-01-01T00:00:00Z" "b"
  mk_entry "2026-01-01T00:05:00Z" "b"
} > "$TMP_FILE"
result="$(_usage_aggregate_transcript "$TMP_FILE" "b")"
assert_equal "$(printf '%s' "$result" | jq -r '.activeSeconds')" "60" \
  "_usage_aggregate_transcript: gapがちょうど閾値の場合は待ち側として扱われる"

# gitBranch不一致entryは除外される
{
  mk_entry "2026-01-01T00:00:00Z" "other-branch"
  mk_entry "2026-01-01T00:02:00Z" "b"
} > "$TMP_FILE"
result="$(_usage_aggregate_transcript "$TMP_FILE" "b")"
assert_equal "$(printf '%s' "$result" | jq -r '.assistantCount')" "1" \
  "_usage_aggregate_transcript: gitBranch不一致entryはassistantCountから除外される"

# --- _usage_read_new_lines: カーソル位置以降の新規行のみが切り出される ---

{
  mk_entry "2026-01-01T00:00:00Z" "b"
  mk_entry "2026-01-01T00:01:00Z" "b"
  mk_entry "2026-01-01T00:02:00Z" "b"
} > "$TMP_FILE"
result="$(_usage_read_new_lines "$TMP_FILE" 1)"
assert_equal "$(printf '%s' "$result" | jq -r '.totalLines')" "3" \
  "_usage_read_new_lines: totalLinesは空行を除いた全行数"
assert_equal "$(printf '%s' "$result" | jq -r '.newEntries | length')" "2" \
  "_usage_read_new_lines: オフセット以降の行のみがnewEntriesに含まれる"
assert_equal "$(printf '%s' "$result" | jq -r '.newEntries[0].timestamp')" "2026-01-01T00:01:00Z" \
  "_usage_read_new_lines: newEntriesの先頭はオフセット位置の行"

result="$(_usage_read_new_lines "$TMP_FILE" 0)"
assert_equal "$(printf '%s' "$result" | jq -r '.newEntries | length')" "3" \
  "_usage_read_new_lines: オフセット0なら全行がnewEntriesに含まれる"

result="$(_usage_read_new_lines "$TMP_FILE" 10)"
assert_equal "$(printf '%s' "$result" | jq -r '.newEntries | length')" "0" \
  "_usage_read_new_lines: オフセットが総行数を超える場合はnewEntriesが空になる"

# 不正なJSON行は行数（totalLines）には数えるが、newEntriesからは除外される
{
  mk_entry "2026-01-01T00:00:00Z" "b"
  echo "not valid json"
  mk_entry "2026-01-01T00:02:00Z" "b"
} > "$TMP_FILE"
result="$(_usage_read_new_lines "$TMP_FILE" 0)"
assert_equal "$(printf '%s' "$result" | jq -r '.totalLines')" "3" \
  "_usage_read_new_lines: 不正なJSON行も空行でなければtotalLinesに数える"
assert_equal "$(printf '%s' "$result" | jq -r '.newEntries | length')" "2" \
  "_usage_read_new_lines: 不正なJSON行はnewEntriesからは除外される"

# --- _usage_aggregate_new_lines: tools/tokens/turns/skillCalls/agentCalls/askUserQuestionsの抽出 ---

skill_entry="$(jq -nc '{type: "assistant", gitBranch: "b", timestamp: "2026-01-01T00:00:00Z",
  message: {model: "m", usage: {input_tokens: 1, output_tokens: 1}, content: [
    {type: "tool_use", id: "toolu_1", name: "Skill", input: {skill: "issue-mr-flow", args: "start 45"}}
  ]}}')"
agent_entry="$(jq -nc '{type: "assistant", gitBranch: "b", timestamp: "2026-01-01T00:01:00Z",
  message: {model: "m", usage: {input_tokens: 2, output_tokens: 2}, content: [
    {type: "tool_use", id: "toolu_2", name: "Agent", input: {
      subagent_type: "Explore", description: "調査する", prompt: "何か調べて"}},
    {type: "tool_use", id: "toolu_3", name: "Bash", input: {}}
  ]}}')"
other_branch_entry="$(jq -nc '{type: "assistant", gitBranch: "other", timestamp: "2026-01-01T00:02:00Z",
  message: {model: "m", usage: {input_tokens: 99, output_tokens: 99}, content: [
    {type: "tool_use", id: "toolu_9", name: "Bash", input: {}}
  ]}}')"
question_entry="$(jq -nc '{type: "user", gitBranch: "b", timestamp: "2026-01-01T00:03:00Z", uuid: "u1",
  message: {content: [
    {type: "tool_result", tool_use_id: "toolu_4",
      content: "Your questions have been answered: \"色は？\"=\"赤\", \"数は？\"=\"3\". You can now continue with these answers in mind."}
  ]}}')"
non_answer_entry="$(jq -nc '{type: "user", gitBranch: "b", timestamp: "2026-01-01T00:04:00Z", uuid: "u2",
  message: {content: [
    {type: "tool_result", tool_use_id: "toolu_5", content: "1"}
  ]}}')"

new_entries="$(jq -nc --argjson e1 "$skill_entry" --argjson e2 "$agent_entry" \
  --argjson e3 "$other_branch_entry" --argjson e4 "$question_entry" --argjson e5 "$non_answer_entry" \
  '[$e1, $e2, $e3, $e4, $e5]')"
delta="$(_usage_aggregate_new_lines "$new_entries" "b")"

assert_equal "$(printf '%s' "$delta" | jq -r '.assistantCount')" "2" \
  "_usage_aggregate_new_lines: gitBranch一致のassistantエントリのみカウントされる"
assert_equal "$(printf '%s' "$delta" | jq -r '.tokens.m.input')" "3" \
  "_usage_aggregate_new_lines: 他ブランチ分のトークンは合算されない（1+2=3、99は除外）"
assert_equal "$(printf '%s' "$delta" | jq -r '.tools.Bash')" "1" \
  "_usage_aggregate_new_lines: 他ブランチ分のtool_useは除外される（同ブランチのBashのみ1件）"
assert_equal "$(printf '%s' "$delta" | jq -r '.skillCalls | length')" "1" \
  "_usage_aggregate_new_lines: Skill tool_useブロックが1件抽出される"
assert_equal "$(printf '%s' "$delta" | jq -r '.skillCalls[0].skill')" "issue-mr-flow" \
  "_usage_aggregate_new_lines: skillCallsにskill名が入る"
assert_equal "$(printf '%s' "$delta" | jq -r '.skillCalls[0].args')" "start 45" \
  "_usage_aggregate_new_lines: skillCallsにargsが入る"
assert_equal "$(printf '%s' "$delta" | jq -r '.agentCalls | length')" "1" \
  "_usage_aggregate_new_lines: Agent tool_useブロックが1件抽出される"
assert_equal "$(printf '%s' "$delta" | jq -r '.agentCalls[0].subagentType')" "Explore" \
  "_usage_aggregate_new_lines: agentCallsにsubagentTypeが入る"
assert_equal "$(printf '%s' "$delta" | jq -r '.agentCalls[0].prompt')" "何か調べて" \
  "_usage_aggregate_new_lines: agentCallsにpromptが入る"
assert_equal "$(printf '%s' "$delta" | jq -r '.askUserQuestions | length')" "2" \
  "_usage_aggregate_new_lines: 1回のAskUserQuestionから複数の質問=回答ペアが抽出される"
assert_equal "$(printf '%s' "$delta" | jq -r '.askUserQuestions[0].question')" "色は？" \
  "_usage_aggregate_new_lines: askUserQuestionsに質問文が入る"
assert_equal "$(printf '%s' "$delta" | jq -r '.askUserQuestions[0].answer')" "赤" \
  "_usage_aggregate_new_lines: askUserQuestionsに回答が入る"

# --- _usage_merge_state: 新規分（delta）をそのまま加算する方式（issue #37で引き算方式から変更） ---

zero_delta='{"tokens":{},"tools":{},"assistantCount":0,"skillCalls":[],"agentCalls":[],"askUserQuestions":[]}'

delta_1="$(jq -nc '{tokens: {m: {input: 10, output: 5, cacheCreate: 0, cacheRead: 0}},
  tools: {Bash: 2}, assistantCount: 1, skillCalls: [], agentCalls: [], askUserQuestions: []}')"
merged_1="$(_usage_merge_state "{}" "$delta_1" 30 "sessionA" "feature-x")"
assert_equal "$(printf '%s' "$merged_1" | jq -r '.sinceLastPush.tokensByModel.m.input')" "10" \
  "_usage_merge_state: 初回pushはdeltaの値がそのままsinceLastPushになる"
assert_equal "$(printf '%s' "$merged_1" | jq -r '.sinceLastPush.toolCalls.Bash')" "2" \
  "_usage_merge_state: 初回pushのtoolCallsもdeltaがそのまま入る"
assert_equal "$(printf '%s' "$merged_1" | jq -r '.sinceLastPush.turns')" "1" \
  "_usage_merge_state: turnsはdelta.assistantCountがそのまま入る"
assert_equal "$(printf '%s' "$merged_1" | jq -r '.sinceLastPush.activeSeconds')" "30" \
  "_usage_merge_state: 初回pushのactiveSecondsは累計値(30)-前回(0)がそのまま入る"
assert_equal "$(printf '%s' "$merged_1" | jq -r '.sessions.sessionA.lastActiveSeconds')" "30" \
  "_usage_merge_state: sessionのlastActiveSecondsに累計値が保存される"

# 2回目push: 前回のsinceLastPush（まだリセットされていない想定）に新規分が加算される。
# tokens/tools/turnsは単純加算（引き算ではない）。activeSecondsは累計値との差分。
delta_2="$(jq -nc '{tokens: {m: {input: 4, output: 1, cacheCreate: 0, cacheRead: 0}},
  tools: {Bash: 1, Read: 3}, assistantCount: 2, skillCalls: [], agentCalls: [], askUserQuestions: []}')"
merged_2="$(_usage_merge_state "$merged_1" "$delta_2" 150 "sessionA" "feature-x")"
assert_equal "$(printf '%s' "$merged_2" | jq -r '.sinceLastPush.tokensByModel.m.input')" "14" \
  "_usage_merge_state: 2回目pushはtokensが単純加算される（10+4=14）"
assert_equal "$(printf '%s' "$merged_2" | jq -r '.sinceLastPush.toolCalls.Bash')" "3" \
  "_usage_merge_state: 2回目pushはtoolCallsが単純加算される（2+1=3）"
assert_equal "$(printf '%s' "$merged_2" | jq -r '.sinceLastPush.toolCalls.Read')" "3" \
  "_usage_merge_state: 新規ツールのtoolCallsも加算される"
assert_equal "$(printf '%s' "$merged_2" | jq -r '.sinceLastPush.turns')" "3" \
  "_usage_merge_state: turnsも単純加算される（1+2=3）"
assert_equal "$(printf '%s' "$merged_2" | jq -r '.sinceLastPush.activeSeconds')" "150" \
  "_usage_merge_state: activeSecondsは累計値(150)-前回累計(30)=120が前回分(30)へ加算される（30+120=150）"

# skillCalls/agentCalls/askUserQuestionsは配列として追記（累積）される
delta_with_skill="$(jq -nc '{tokens: {}, tools: {}, assistantCount: 0,
  skillCalls: [{id: "t1", skill: "commit", args: null}], agentCalls: [], askUserQuestions: []}')"
merged_3="$(_usage_merge_state "$merged_2" "$delta_with_skill" 150 "sessionA" "feature-x")"
assert_equal "$(printf '%s' "$merged_3" | jq -r '.sinceLastPush.skillCalls | length')" "1" \
  "_usage_merge_state: skillCallsが新規に追記される"
merged_4="$(_usage_merge_state "$merged_3" "$delta_with_skill" 150 "sessionA" "feature-x")"
assert_equal "$(printf '%s' "$merged_4" | jq -r '.sinceLastPush.skillCalls | length')" "2" \
  "_usage_merge_state: skillCallsは追記のたびに累積する（配列連結）"

# --- _usage_merge_agent_state: agentId単位のスナップショット・sinceLastPush（新シグネチャ:
#     delta + activeSeconds累計値を渡す） ---

agent_delta_a1="$(jq -nc '{tokens: {}, tools: {}, assistantCount: 1, skillCalls: [], agentCalls: [], askUserQuestions: []}')"
merged_agent_a="$(_usage_merge_agent_state "{}" "agent1" "Explore" "Explore usage code" "$agent_delta_a1" 30 "feature-x")"
assert_equal "$(printf '%s' "$merged_agent_a" | jq -r '.agents.agent1.agentType')" "Explore" \
  "_usage_merge_agent_state: agentIdごとの累計スナップショットにagentTypeが保存される"
assert_equal "$(printf '%s' "$merged_agent_a" | jq -r '.agents.agent1.description')" "Explore usage code" \
  "_usage_merge_agent_state: agentIdごとの累計スナップショットにdescriptionが保存される"
assert_equal "$(printf '%s' "$merged_agent_a" | jq -r '.sinceLastPush.subagents.agent1.activeSeconds')" "30" \
  "_usage_merge_agent_state: 初回のagentId分がsinceLastPush.subagents[agentId]へ計上される"

# 異なるagentId・同一agentType: agentごとに個別のentryとして保持される
agent_delta_a2="$(jq -nc '{tokens: {}, tools: {}, assistantCount: 1, skillCalls: [], agentCalls: [], askUserQuestions: []}')"
merged_agent_b="$(_usage_merge_agent_state "$merged_agent_a" "agent2" "Explore" "another explore task" "$agent_delta_a2" 45 "feature-x")"
assert_equal "$(printf '%s' "$merged_agent_b" | jq -r '.sinceLastPush.subagents.agent1.activeSeconds')" "30" \
  "_usage_merge_agent_state: 異なるagentId追加後もagent1自身の値は変わらない（合算されない）"
assert_equal "$(printf '%s' "$merged_agent_b" | jq -r '.sinceLastPush.subagents.agent2.activeSeconds')" "45" \
  "_usage_merge_agent_state: 異なるagentIdはそれぞれ個別のentryとして保持される"

# 同一agentIdへの2回目の呼び出し: activeSecondsは累計値差分、tokens/toolsはdeltaがそのまま加算される
agent_delta_a1_second="$(jq -nc '{tokens: {}, tools: {}, assistantCount: 1, skillCalls: [], agentCalls: [], askUserQuestions: []}')"
merged_agent_c="$(_usage_merge_agent_state "$merged_agent_b" "agent1" "Explore" "Explore usage code" "$agent_delta_a1_second" 50 "feature-x")"
assert_equal "$(printf '%s' "$merged_agent_c" | jq -r '.sinceLastPush.subagents.agent1.activeSeconds')" "50" \
  "_usage_merge_agent_state: 同一agentIdの2回目はactiveSeconds累計差分（50-30=20）が前回の30へ加算される（30+20=50）"

# --- _usage_sync_session_logs / _usage_aggregate_and_merge_subagents: usage/session-logs・
#     usage/state/session-cursors への配置とカーソルベースの新規行diff集計 ---

FAKE_ROOT="$(mktemp -d)"
trap 'rm -f "$TMP_FILE"; rm -rf "$FAKE_ROOT"' EXIT

mkdir -p "${FAKE_ROOT}/home_projects/sess1/subagents"
mk_entry "2026-01-01T00:00:00Z" "feature-x" > "${FAKE_ROOT}/home_projects/sess1.jsonl"
jq -nc '{type: "assistant", gitBranch: "feature-x", timestamp: "2026-01-01T00:00:00Z",
  agentId: "a1", message: {model: "m", usage: {input_tokens: 1, output_tokens: 1}, content: []}}' \
  > "${FAKE_ROOT}/home_projects/sess1/subagents/agent-a1.jsonl"
jq -nc '{agentType: "Explore", description: "Explore usage-report hook infra"}' \
  > "${FAKE_ROOT}/home_projects/sess1/subagents/agent-a1.meta.json"

log_dir="$(_usage_sync_session_logs "${FAKE_ROOT}/repo" "feature-x" "sess1" "${FAKE_ROOT}/home_projects/sess1.jsonl")"

assert_equal "$log_dir" "${FAKE_ROOT}/repo/usage/session-logs/feature-x/sess1" \
  "_usage_sync_session_logs: コピー先はusage/session-logs/配下になる（.claude/配下ではない）"
assert_true "$([ -f "${log_dir}/main.jsonl" ] && echo true || echo false)" \
  "_usage_sync_session_logs: メインtranscriptがローカルへコピーされる"
assert_true "$([ -f "${log_dir}/subagents/agent-a1.jsonl" ] && echo true || echo false)" \
  "_usage_sync_session_logs: サブエージェントtranscriptがローカルへコピーされる"
assert_true "$([ -f "${log_dir}/subagents/agent-a1.meta.json" ] && echo true || echo false)" \
  "_usage_sync_session_logs: サブエージェントmeta.jsonがローカルへコピーされる"

merged_from_copy="$(_usage_aggregate_and_merge_subagents "{}" "$log_dir" "feature-x" "${FAKE_ROOT}/repo")"
assert_equal "$(printf '%s' "$merged_from_copy" | jq -r '.agents.a1.agentType')" "Explore" \
  "_usage_aggregate_and_merge_subagents: コピー済みディレクトリからagentTypeがmeta.json経由で読み取られる"
assert_equal "$(printf '%s' "$merged_from_copy" | jq -r '.agents.a1.description')" "Explore usage-report hook infra" \
  "_usage_aggregate_and_merge_subagents: コピー済みディレクトリからdescriptionがmeta.json経由で読み取られる"
assert_equal "$(printf '%s' "$merged_from_copy" | jq -r '.sinceLastPush.subagents.a1.activeSeconds')" "30" \
  "_usage_aggregate_and_merge_subagents: コピー済みディレクトリから集計・マージまで一気通貫で動く"
assert_true "$([ -f "${FAKE_ROOT}/repo/usage/state/session-cursors/a1.json" ] && echo true || echo false)" \
  "_usage_aggregate_and_merge_subagents: agentId単位のカーソルファイルがusage/state/session-cursors/配下に作られる"

# 同じサブエージェントtranscriptのまま再度呼んでも、新規行が無いためsinceLastPushは変化しない
merged_from_copy_again="$(_usage_aggregate_and_merge_subagents "$merged_from_copy" "$log_dir" "feature-x" "${FAKE_ROOT}/repo")"
assert_equal "$(printf '%s' "$merged_from_copy_again" | jq -r '.sinceLastPush.subagents.a1.activeSeconds')" "30" \
  "_usage_aggregate_and_merge_subagents: transcript不変なら2回目呼び出しでも差分は増えない（カーソルで新規行無しと判定）"

empty_log_dir="$(mktemp -d)"
existing_noop="$(jq -nc '{foo: "bar"}')"
result_noop="$(_usage_aggregate_and_merge_subagents "$existing_noop" "$empty_log_dir" "feature-x" "${FAKE_ROOT}/repo")"
assert_equal "$result_noop" "$existing_noop" \
  "_usage_aggregate_and_merge_subagents: subagentsディレクトリが無ければexistingをそのまま返す"

# --- _usage_reset_since_last_push ---

state_before_reset="$(jq -nc '{branch: "feature-x", sessions: {s: {lastActiveSeconds: 30}},
  agents: {a1: {agentType: "Explore", description: "d"}},
  sinceLastPush: {tokensByModel: {m: {input: 1, output: 1, cacheCreate: 0, cacheRead: 0}},
    toolCalls: {Bash: 1}, turns: 1, activeSeconds: 30, subagents: {a1: {activeSeconds: 30}},
    skillCalls: [{id: "t1", skill: "commit", args: null}],
    agentCalls: [{id: "t2", subagentType: "Explore", description: "d", prompt: "p"}],
    askUserQuestions: [{id: "u1#0", question: "q", answer: "a"}]}}')"
reset_result="$(_usage_reset_since_last_push "$state_before_reset")"
assert_equal "$(printf '%s' "$reset_result" | jq -r '.sinceLastPush.activeSeconds')" "0" \
  "_usage_reset_since_last_push: sinceLastPush.activeSecondsが0になる"
assert_equal "$(printf '%s' "$reset_result" | jq -c '.sinceLastPush.subagents')" "{}" \
  "_usage_reset_since_last_push: sinceLastPush.subagentsが空になる"
assert_equal "$(printf '%s' "$reset_result" | jq -c '.sinceLastPush.skillCalls')" "[]" \
  "_usage_reset_since_last_push: sinceLastPush.skillCallsが空配列になる"
assert_equal "$(printf '%s' "$reset_result" | jq -c '.sinceLastPush.agentCalls')" "[]" \
  "_usage_reset_since_last_push: sinceLastPush.agentCallsが空配列になる"
assert_equal "$(printf '%s' "$reset_result" | jq -c '.sinceLastPush.askUserQuestions')" "[]" \
  "_usage_reset_since_last_push: sinceLastPush.askUserQuestionsが空配列になる"
assert_equal "$(printf '%s' "$reset_result" | jq -r '.agents.a1.agentType')" "Explore" \
  "_usage_reset_since_last_push: agents（累計スナップショット）はリセットされず保持される"
assert_true "$(printf '%s' "$reset_result" | jq -r 'has("lastPostedAt")')" \
  "_usage_reset_since_last_push: lastPostedAtが設定される"

# --- _usage_filter_nonzero_subagents（差分0のagentはレポートに出力しない） ---

subagents_mixed="$(jq -nc '{
  a1: {agentType: "Explore", description: "d1",
    tokensByModel: {m: {input: 1, output: 0, cacheCreate: 0, cacheRead: 0}}, toolCalls: {}, activeSeconds: 0},
  a2: {agentType: "Explore", description: "d2",
    tokensByModel: {}, toolCalls: {}, activeSeconds: 0},
  a3: {agentType: "Plan", description: "d3",
    tokensByModel: {}, toolCalls: {}, activeSeconds: 10}
}')"
filtered="$(_usage_filter_nonzero_subagents "$subagents_mixed")"
assert_true "$(printf '%s' "$filtered" | jq -r 'has("a1")')" \
  "_usage_filter_nonzero_subagents: トークン差分ありのagentは残る"
assert_true "$(printf '%s' "$filtered" | jq -r '(has("a2") | not)')" \
  "_usage_filter_nonzero_subagents: トークン・ツール・稼働時間いずれも差分0のagentは除外される"
assert_true "$(printf '%s' "$filtered" | jq -r 'has("a3")')" \
  "_usage_filter_nonzero_subagents: activeSecondsのみ差分があるagentは残る"

# --- 回帰テスト: sync_usage_state（issue #37: カーソルはブランチではなくセッション単位で
#     グローバルに保持されるため、ブランチが切り替わっても前回までに処理済みの行を再度
#     数え直さないこと） ---
#
# 注意（テスト設計上の限界）: Claude Code側がresume時にtranscriptへ過去の行をどのような形で
# 再書き込みするかは非公開の内部仕様であり（ファイル冒頭コメント参照）、実データで観測した
# 「同一uuidが複数回・異なるgitBranchラベル付きで出現する」という重複行自体は、
# 新しい物理行として追記される限りカーソル方式でも新規行として数えられる（重複行の内容を
# 判別して除外することは意図的に行わない設計。plan「Context」節参照）。
# 本テストが確実に検証できるのは、カーソルが「ブランチ単位」ではなく「セッション単位で
# グローバル」に保持されることそのもの。もしカーソルがブランチごとに別管理されていた場合、
# 同じtranscriptのまま別ブランチへ切り替えてpushすると、そのブランチにとっては
# 「初めて見るセッション」としてカーソル0から再集計され、branch-aで既に処理済みの行が
# branch-bの初回差分として二重に計上されてしまう。

PUSH_ROOT="$(mktemp -d)"
trap 'rm -f "$TMP_FILE"; rm -rf "$FAKE_ROOT" "$PUSH_ROOT"' EXIT
PUSH_REPO="${PUSH_ROOT}/repo"

mkdir -p "${PUSH_ROOT}/home_projects"
TRANSCRIPT="${PUSH_ROOT}/home_projects/pushsess.jsonl"

# ブランチAでの作業（3行）
{
  mk_entry "2026-01-01T00:00:00Z" "branch-a"
  mk_entry "2026-01-01T00:01:00Z" "branch-a"
  mk_entry "2026-01-01T00:02:00Z" "branch-a"
} > "$TRANSCRIPT"

# ブランチAで push（3行とも計上され、セッション"pushsess"のグローバルカーソルが3まで進む）
state_a="$(sync_usage_state "$PUSH_REPO" "branch-a" "pushsess" "$TRANSCRIPT")"
assert_equal "$(printf '%s' "$state_a" | jq -r '.sinceLastPush.turns')" "3" \
  "sync_usage_state回帰テスト（issue #37）: branch-aでの初回pushは3行分すべてが計上される"

# transcriptの内容は変わらないまま、同じセッションが別ブランチ(branch-b)からpushされる
# （branch-bにとっては初めてのpush＝状態ファイルもまだ存在しない）
state_b="$(sync_usage_state "$PUSH_REPO" "branch-b" "pushsess" "$TRANSCRIPT")"
assert_equal "$state_b" "" \
  "sync_usage_state回帰テスト（issue #37）: カーソルがセッション単位でグローバルなため、branch-aで既に処理済みの行はbranch-bへ切り替えても再カウントされない（新規行が無いため状態ファイルも作られず出力は空になる）"

# --- 回帰テスト: 差分が無ければ状態を更新しない（issue #37「差分がなければコピーしない」） ---

NOOP_ROOT="$(mktemp -d)"
trap 'rm -f "$TMP_FILE"; rm -rf "$FAKE_ROOT" "$PUSH_ROOT" "$NOOP_ROOT"' EXIT
NOOP_REPO="${NOOP_ROOT}/repo"
NOOP_TRANSCRIPT="${NOOP_ROOT}/home_projects/noopsess.jsonl"
mkdir -p "${NOOP_ROOT}/home_projects"
mk_entry "2026-01-01T00:00:00Z" "feature-noop" > "$NOOP_TRANSCRIPT"

state_noop_1="$(sync_usage_state "$NOOP_REPO" "feature-noop" "noopsess" "$NOOP_TRANSCRIPT")"
state_noop_2="$(sync_usage_state "$NOOP_REPO" "feature-noop" "noopsess" "$NOOP_TRANSCRIPT")"
assert_equal "$state_noop_1" "$state_noop_2" \
  "sync_usage_state: transcriptに変化が無ければ2回目呼び出しでも状態は変わらない"
assert_true "$([ -d "${NOOP_REPO}/usage/session-logs/feature-noop/noopsess" ] && echo true || echo false)" \
  "sync_usage_state: 差分がある1回目はsession-logsへコピーされる"

echo "----"
echo "passed=${PASSED} failures=${FAILURES}"
if [ "$FAILURES" -gt 0 ]; then
  exit 1
else
  exit 0
fi
