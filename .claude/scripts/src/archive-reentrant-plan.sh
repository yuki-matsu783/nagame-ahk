#!/usr/bin/env bash
# 同一セッション内でPlanモードへ複数回re-entryすると、ハーネスは1回目のre-entryで使った
# planファイルパスをそのまま提示し続ける（新しいパスは割り当てられない）。この制約により、
# 2回目以降のre-entryで新しい計画を書こうとすると、1回目の計画（既にcommit済み）を
# 上書きしてしまう問題が起きる（詳細: .claude/rules/plan-mode-safety.md 規則6、issue #26）。
#
# 本スクリプトは、re-entry時にハーネス提示パスへ新しい計画を書き込む前に呼び出すことで、
# そのパスに既にある1つ前の計画（存在する場合のみ）を `_actN` サフィックス付きの別名へ
# 退避する。これにより、ハーネス提示パスへ直接新しい計画を上書きしてよくなり、
# 「一時的に上書き→git checkoutで復元」という手順（事故と隣り合わせだった旧手順）が不要になる。
#
# - planファイル: cp（元のパスはそのまま残し、後続でハーネスが直接上書きできるようにする）。
# - 対応するworklogファイル（worklog/日付_<plan名>.md）: mv（新しい計画が同じ`base`名を
#   再利用してworklogファイル名が衝突するのを避けるため、元の名前を明け渡す）。
# - git操作（add/commit）は行わない。ファイル操作のみとし、commitは通常のフロー手順
#   （.claude/skills/issue-mr-flow/SKILL.md flow-id 6/12）に委ねる。
#
# 使い方: archive-reentrant-plan.sh <plan_file_path> [worklog_dir]
#   plan_file_path: ハーネスがEnterPlanMode時に提示するパス（例: plans/groovy-twirling-puffin.md）
#   worklog_dir:    省略可。既定 "worklog"
#
# 出力: 結果をJSON文字列でstdoutへ出力する（.claude/scripts/src/vcs/Provider.sh と同じ規約）。
#   例: {"archived": true, "suffix": 1,
#        "planArchivedTo": "plans/groovy-twirling-puffin_act1.md",
#        "worklogArchivedTo": "worklog/20260815_groovy-twirling-puffin_act1.md"}
#   planファイルがまだ存在しない（このセッション最初のre-entry）場合:
#        {"archived": false, "reason": "plan file does not exist yet"}

set -euo pipefail

# plan_dir配下で、base名に対して未使用の最小のサフィックス番号（1始まり）を返す。
next_archive_suffix() {
  local plan_dir="$1" base="$2"
  local n=1
  while [[ -e "${plan_dir}/${base}_act${n}.md" ]]; do
    n=$((n + 1))
  done
  echo "$n"
}

# worklog_dir配下から `*_<base>.md` に一致するファイルを1件だけ探す。
# 0件・複数件はエラーにせず、空文字列を返して呼び出し元に判断を委ねる
# （shell-script-style.mdの「失敗しても継続したい処理」パターン。globが一切マッチしない場合に
# パターン文字列そのものが返る事故を避けるため、nullglobを使う）。
find_worklog_file() {
  local worklog_dir="$1" base="$2"
  local -a matches=()
  shopt -s nullglob
  matches=("${worklog_dir}"/*"_${base}.md")
  shopt -u nullglob
  if [[ "${#matches[@]}" -eq 1 ]]; then
    echo "${matches[0]}"
  fi
}

archive_reentrant_plan() {
  local plan_file="$1" worklog_dir="${2:-worklog}"

  if [[ ! -e "$plan_file" ]]; then
    jq -nc '{archived: false, reason: "plan file does not exist yet"}'
    return 0
  fi

  local plan_dir base
  plan_dir="$(dirname "$plan_file")"
  base="$(basename "$plan_file" .md)"

  local suffix
  suffix="$(next_archive_suffix "$plan_dir" "$base")"

  local plan_archived_to="${plan_dir}/${base}_act${suffix}.md"
  cp "$plan_file" "$plan_archived_to"

  local worklog_file worklog_archived_to="null"
  worklog_file="$(find_worklog_file "$worklog_dir" "$base")"
  if [[ -n "$worklog_file" ]]; then
    local worklog_target="${worklog_file%.md}_act${suffix}.md"
    mv "$worklog_file" "$worklog_target"
    worklog_archived_to="\"${worklog_target}\""
  fi

  jq -nc \
    --argjson suffix "$suffix" \
    --arg planArchivedTo "$plan_archived_to" \
    --argjson worklogArchivedTo "$worklog_archived_to" \
    '{archived: true, suffix: $suffix, planArchivedTo: $planArchivedTo, worklogArchivedTo: $worklogArchivedTo}'
}

main() {
  local plan_file="${1:-}"
  if [[ -z "$plan_file" ]]; then
    echo "usage: archive-reentrant-plan.sh <plan_file_path> [worklog_dir]" >&2
    exit 1
  fi
  archive_reentrant_plan "$@"
}

# 単体テスト（tests/test_archive_reentrant_plan.sh）からsourceして関数のみ再利用できるよう、
# 直接実行された場合のみ main を呼ぶ。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
