#!/usr/bin/env bash
#
# .claude/scripts/src/extract-frontmatter.sh の単体テスト。
# 設計反映時に dev-tools/docs/spec/ へ記録予定（issue #7 PR #23レビュー対応）。
#
# 対象: ネットワークを伴わない純粋ロジック（frontmatter_to_json のYAML→JSON変換、
# resolve_repo_root によるリポジトリルート解決、concept_id・directory・frontmatter無しの扱い）。
# resolve_repo_root はローカルの `git rev-parse` を呼ぶが、tests/test_vcs_provider.sh が
# gh/glab（ネットワークAPI）呼び出しのみを対象外とし、ローカルgit呼び出しは検証対象に含めている
# のと同じ方針。find/stat/date を使った実ディレクトリ走査（main関数本体）はここでは検証しない
# （実データでの動作確認は本スクリプトの通常利用を兼ねる）。
#
# 使い方:
#     bash tests/test_extract_frontmatter.sh
#
# 副作用: $TMPDIR配下に一時ファイルを作成・削除する。標準出力にアサーション結果を出す。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# main() の自動実行を避けるため、直接実行ではなくsourceする（extract-frontmatter.sh側の
# `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` ガードにより、source時はmainが呼ばれない）。
source "${REPO_ROOT}/.claude/scripts/src/extract-frontmatter.sh"

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

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# --- frontmatter_to_json: スカラー・フロー配列 ---
scalar_and_flow_file="${WORK_DIR}/scalar_and_flow.md"
cat >"$scalar_and_flow_file" <<'EOF'
---
title: サンプル
type: spec
tags: [foo, bar, baz]
alwaysApply: true
---

本文
EOF
result="$(frontmatter_to_json "$scalar_and_flow_file")"
assert_equal "$(jq empty <<<"$result" 2>&1; echo $?)" "0" "frontmatter_to_json: 出力が妥当なJSONになっている"
assert_equal "$(jq -r '.title' <<<"$result")" "サンプル" "frontmatter_to_json: スカラー値(title)を取得できる"
assert_equal "$(jq -r '.type' <<<"$result")" "spec" "frontmatter_to_json: スカラー値(type)を取得できる"
assert_equal "$(jq -c '.tags' <<<"$result")" '["foo","bar","baz"]' "frontmatter_to_json: フロー配列(tags)を取得できる"
assert_equal "$(jq -r '.alwaysApply' <<<"$result")" "true" "frontmatter_to_json: 真偽値(alwaysApply)をJSON booleanとして取得できる"

# --- frontmatter_to_json: ブロック配列（ahk-style.mdのpathsと同形式） ---
block_array_file="${WORK_DIR}/block_array.md"
cat >"$block_array_file" <<'EOF'
---
paths:
  - "src/**/*.ahk"
  - "tests/**/*.ahk"
title: ブロック配列サンプル
---

本文
EOF
result_block="$(frontmatter_to_json "$block_array_file")"
assert_equal "$(jq -c '.paths' <<<"$result_block")" '["src/**/*.ahk","tests/**/*.ahk"]' "frontmatter_to_json: ブロック配列(paths)を取得できる"
assert_equal "$(jq -r '.title' <<<"$result_block")" "ブロック配列サンプル" "frontmatter_to_json: ブロック配列の後のスカラー値も取得できる"

# --- frontmatter_to_json: frontmatterが無いファイル ---
no_frontmatter_file="${WORK_DIR}/no_frontmatter.md"
cat >"$no_frontmatter_file" <<'EOF'
# 見出し

frontmatterの無いファイル。
EOF
assert_equal "$(frontmatter_to_json "$no_frontmatter_file")" "null" "frontmatter_to_json: frontmatterが無ければnullを返す"

# --- resolve_repo_root: 実行時の指定ディレクトリに関わらず、常にgitリポジトリのルートを返す ---
# （PR #23レビュー対応: concept_id/directoryは指定ディレクトリではなくrepo root基準にする）
assert_equal "$(resolve_repo_root "$REPO_ROOT")" "$REPO_ROOT" "resolve_repo_root: リポジトリルート自身を指定した場合"
assert_equal "$(resolve_repo_root "$REPO_ROOT/docs")" "$REPO_ROOT" "resolve_repo_root: サブディレクトリを指定してもリポジトリルートを返す"

# --- concept_id・directory の導出（main関数と同じ計算式をここで直接検証） ---
# concept_id/directoryは実行時の指定ディレクトリではなく、repo_root（resolve_repo_rootの戻り値）
# からの相対パスを基準にする。
repo_root="$(resolve_repo_root "$REPO_ROOT")"

rel_root_level="$(realpath --relative-to="$repo_root" "$REPO_ROOT/README.md")"
assert_equal "${rel_root_level%.md}" "README" "concept_id: リポジトリルート直下のファイルは拡張子を除いたファイル名になる"
assert_equal "$(dirname "$rel_root_level")" "." "directory: リポジトリルート直下のファイルは'.'になる"

rel_nested="$(realpath --relative-to="$repo_root" "$REPO_ROOT/docs/spec/activity-status.md")"
assert_equal "${rel_nested%.md}" "docs/spec/activity-status" "concept_id: サブディレクトリのファイルはリポジトリルートからの相対パスから.mdを除いたものになる"
assert_equal "$(dirname "$rel_nested")" "docs/spec" "directory: サブディレクトリのファイルはリポジトリルートからの相対ディレクトリパスになる"

# docs/ を指定して実行した場合でも、concept_id/directoryはリポジトリルート基準のまま
# （docs/spec/ からの相対 "activity-status" にはならない）ことを確認する。
repo_root_from_subdir="$(resolve_repo_root "$REPO_ROOT/docs")"
rel_from_subdir="$(realpath --relative-to="$repo_root_from_subdir" "$REPO_ROOT/docs/spec/activity-status.md")"
assert_equal "${rel_from_subdir%.md}" "docs/spec/activity-status" "concept_id: docs/を指定して実行してもリポジトリルート基準のまま"

echo "----"
echo "passed=${PASSED} failures=${FAILURES}"
if [ "$FAILURES" -gt 0 ]; then
  exit 1
else
  exit 0
fi
