#!/usr/bin/env bash
#
# dev-tools/src/archive-reentrant-plan.sh の単体テスト。
# 設計反映時に dev-tools/docs/spec/ へ記録予定（issue #26）。
#
# 対象: ネットワーク・git呼び出しを伴わない純粋なファイル操作ロジック（cp/mv・サフィックス採番・
# JSON出力）。実際のPlanモード再突入シナリオは模擬したディレクトリ構成で検証する。
#
# 使い方:
#     bash tests/test_archive_reentrant_plan.sh
#
# 副作用: $TMPDIR配下に一時ディレクトリを作成・削除する。標準出力にアサーション結果を出す。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# main() の自動実行を避けるため、直接実行ではなくsourceする（archive-reentrant-plan.sh側の
# `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` ガードにより、source時はmainが呼ばれない）。
source "${REPO_ROOT}/dev-tools/src/archive-reentrant-plan.sh"

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

assert_file_exists() {
  local path="$1" label="$2"
  if [ -e "$path" ]; then
    PASSED=$((PASSED + 1))
  else
    FAILURES=$((FAILURES + 1))
    echo "FAIL: ${label} file not found: ${path}"
  fi
}

assert_file_absent() {
  local path="$1" label="$2"
  if [ ! -e "$path" ]; then
    PASSED=$((PASSED + 1))
  else
    FAILURES=$((FAILURES + 1))
    echo "FAIL: ${label} file unexpectedly exists: ${path}"
  fi
}

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

PLANS_DIR="${WORK_DIR}/plans"
WORKLOG_DIR="${WORK_DIR}/worklog"
mkdir -p "$PLANS_DIR" "$WORKLOG_DIR"

# --- planファイルがまだ存在しない場合（このセッション最初のre-entry）: no-op ---
result="$(archive_reentrant_plan "${PLANS_DIR}/fresh-plan.md" "$WORKLOG_DIR")"
assert_equal "$(jq -r '.archived' <<<"$result")" "false" "存在しないplanファイル: archivedはfalse"
assert_file_absent "${PLANS_DIR}/fresh-plan_act1.md" "存在しないplanファイル: archiveファイルは作られない"

# --- 1回目のre-entry相当: planのみ（対応するworklogが無い） ---
plan_file="${PLANS_DIR}/lonely-plan.md"
echo "plan v1" >"$plan_file"
result="$(archive_reentrant_plan "$plan_file" "$WORKLOG_DIR")"
assert_equal "$(jq -r '.archived' <<<"$result")" "true" "worklog無し: archivedはtrue"
assert_equal "$(jq -r '.suffix' <<<"$result")" "1" "worklog無し: suffixは1"
assert_equal "$(jq -r '.worklogArchivedTo' <<<"$result")" "null" "worklog無し: worklogArchivedToはnull"
assert_file_exists "${PLANS_DIR}/lonely-plan_act1.md" "worklog無し: planのarchiveファイルが作られる"
assert_file_exists "$plan_file" "worklog無し: 元のplanファイルは残る（cpのため）"
assert_equal "$(cat "${PLANS_DIR}/lonely-plan_act1.md")" "plan v1" "worklog無し: archiveされた内容が一致する"

# --- planとworklogが両方ある状態で、1回目→2回目と連続でre-entryする ---
plan_file="${PLANS_DIR}/paired-plan.md"
echo "plan v1" >"$plan_file"
worklog_file="${WORKLOG_DIR}/20260816_paired-plan.md"
echo "worklog v1" >"$worklog_file"

result1="$(archive_reentrant_plan "$plan_file" "$WORKLOG_DIR")"
assert_equal "$(jq -r '.suffix' <<<"$result1")" "1" "1回目re-entry: suffixは1"
# JSON中のパス文字列はネイティブjq.exe経由でMSYSの絶対パス自動変換の影響を受けうる
# （.claude/rules/shell-script-style.md「git bashのパス変換の落とし穴」参照。実運用では
# ハーネスが相対パスを提示するため影響しない）。ここではファイル名部分のみを比較する。
assert_equal "$(basename "$(jq -r '.planArchivedTo' <<<"$result1")")" "paired-plan_act1.md" "1回目re-entry: planArchivedToのファイル名が一致する"
assert_equal "$(basename "$(jq -r '.worklogArchivedTo' <<<"$result1")")" "20260816_paired-plan_act1.md" "1回目re-entry: worklogArchivedToのファイル名が一致する"
assert_file_exists "${PLANS_DIR}/paired-plan_act1.md" "1回目re-entry: planのarchiveファイルが作られる"
assert_file_exists "${WORKLOG_DIR}/20260816_paired-plan_act1.md" "1回目re-entry: worklogのarchiveファイルが作られる（mv後の名前）"
assert_file_absent "$worklog_file" "1回目re-entry: 元のworklogファイル名は明け渡される（mvのため）"
assert_file_exists "$plan_file" "1回目re-entry: 元のplanファイルは残る（cpのため）"

# ハーネスが同じパスを提示し続ける前提で、2回目のplanを同じplan_fileへ上書きしてから再度呼ぶ
echo "plan v2" >"$plan_file"
echo "worklog v2" >"$worklog_file"
result2="$(archive_reentrant_plan "$plan_file" "$WORKLOG_DIR")"
assert_equal "$(jq -r '.suffix' <<<"$result2")" "2" "2回目re-entry: 既存の_act1を避けてsuffixは2になる"
assert_file_exists "${PLANS_DIR}/paired-plan_act2.md" "2回目re-entry: planのarchiveファイルが作られる"
assert_equal "$(cat "${PLANS_DIR}/paired-plan_act1.md")" "plan v1" "2回目re-entry後も_act1の内容は変わらない"
assert_equal "$(cat "${PLANS_DIR}/paired-plan_act2.md")" "plan v2" "2回目re-entryのarchive内容が一致する"

echo "----"
echo "passed=${PASSED} failures=${FAILURES}"
if [ "$FAILURES" -gt 0 ]; then
  exit 1
else
  exit 0
fi
