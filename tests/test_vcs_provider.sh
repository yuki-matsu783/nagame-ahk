#!/usr/bin/env bash
#
# .claude/scripts/src/vcs/Provider.sh の単体テスト。
# 設計: .claude/scripts/docs/spec/shell-scripts.md
#
# 対象: 外部API呼び出し（gh/glab）を伴わない純粋ロジックのみ（to_slug, test_issue_sections,
# get_issue_number_from_branch）。gh/glab呼び出しを伴う関数（get_issue等）はここでは検証しない
# （実データでの手動検証はworklog参照。issue-mr-flowの通常利用そのものが結合テストを兼ねる）。
#
# 使い方:
#     bash tests/test_vcs_provider.sh
#
# 副作用なし。標準出力にアサーション結果を出す。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/.claude/scripts/src/vcs/Provider.sh"

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

# --- to_slug ---
assert_equal "$(to_slug 'Fix: Login Button (v2)!!')" "fix-login-button-v2" "to_slug: 記号混じりの英語タイトル"
assert_equal "$(to_slug 'スクリプトを可能な限りbashで記載する')" "bash" "to_slug: 日本語タイトル中のascii部分のみ残る"
assert_equal "$(to_slug '')" "issue" "to_slug: 空文字は既定値issueになる"
assert_equal "$(to_slug '###')" "issue" "to_slug: 記号のみは既定値issueになる"
long_title="$(printf 'a%.0s' $(seq 1 80))"
slug_result="$(to_slug "$long_title")"
assert_true "$([ ${#slug_result} -le 50 ] && echo true || echo false)" "to_slug: 50文字を超えるタイトルは50文字以内に切り詰められる"
assert_equal "$(to_slug 'enrich branch slug')" "enrich-branch-slug" "to_slug: スペース区切りの英語意訳フレーズはそのままkebab-caseになる（AIエージェント生成想定・issue #22）"

# --- test_issue_sections ---
full_body=$'## 目的\nfoo\n\n## 現状\nbar\n\n## 期待する動作\nbaz\n\n## 受け入れ条件\nqux'
missing="$(test_issue_sections "$full_body")"
assert_equal "$missing" "" "test_issue_sections: 4見出しが揃っていれば欠落なし"

partial_body=$'## 目的\nfoo'
missing2="$(test_issue_sections "$partial_body")"
assert_equal "$missing2" $'現状\n期待する動作\n受け入れ条件' "test_issue_sections: 3見出しが欠落として検出される"

# --- build_issue_body ---
built_body="$(build_issue_body "目的テキスト" "現状テキスト" "期待する動作テキスト" "受け入れ条件テキスト")"
missing3="$(test_issue_sections "$built_body")"
assert_equal "$missing3" "" "build_issue_body: 組み立てた本文は4見出しの欠落なしと判定される"
assert_true "$(printf '%s' "$built_body" | grep -q "目的テキスト" && echo true || echo false)" "build_issue_body: 目的の内容が本文に含まれる"
assert_true "$(printf '%s' "$built_body" | grep -q "受け入れ条件テキスト" && echo true || echo false)" "build_issue_body: 受け入れ条件の内容が本文に含まれる"

# --- get_issue_number_from_branch ---
# .mrworkflow.json の既定テンプレート（feature-{issue}-{slug}）を前提とする
if issue_num="$(get_issue_number_from_branch 'feature-42-something')"; then
  assert_equal "$issue_num" "42" "get_issue_number_from_branch: 命名規則に一致するブランチからissue番号を抽出"
else
  assert_true "false" "get_issue_number_from_branch: 命名規則に一致するブランチからissue番号を抽出"
fi

if get_issue_number_from_branch 'main' >/dev/null 2>&1; then
  assert_true "false" "get_issue_number_from_branch: 命名規則に一致しないブランチ(main)は失敗する"
else
  assert_true "true" "get_issue_number_from_branch: 命名規則に一致しないブランチ(main)は失敗する"
fi

if get_issue_number_from_branch 'feature-abc-slug' >/dev/null 2>&1; then
  assert_true "false" "get_issue_number_from_branch: issue番号部分が数字でなければ失敗する"
else
  assert_true "true" "get_issue_number_from_branch: issue番号部分が数字でなければ失敗する"
fi

echo "----"
echo "passed=${PASSED} failures=${FAILURES}"
if [ "$FAILURES" -gt 0 ]; then
  exit 1
else
  exit 0
fi
