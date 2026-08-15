#!/usr/bin/env bash
#
# issue駆動MRワークフロー支援の共通レイヤー（bash版）。
# 設計: dev-tools/docs/spec/issue-mr-workflow.md, dev-tools/docs/spec/shell-scripts.md
#
# GitHub/GitLabの差異を吸収する共通インターフェースを提供する。呼び出し側
# （.claude/skills/issue-mr-flow/SKILL.md 等）はこのファイルをsourceして使う。
#     source dev-tools/src/vcs/Provider.sh
#
# プロバイダ非依存の関数（new_issue_branch, sync_branch 等）はここに実装し、
# プロバイダ依存の関数（get_issue, new_draft_merge_request, get_mr_unresolved_comments,
# set_mr_description 等）は get_provider の判定結果に応じて Github.sh / Gitlab.sh の
# 対応関数（github_xxx / gitlab_xxx）へディスパッチする。
#
# 戻り値の受け渡しはPowerShell版のPSCustomObjectに代えてJSON文字列をstdoutへ出力する形にする
# （呼び出し側はjqでフィールドを取り出す。例: get_issue 6 | jq -r '.title'）。JSONのキー名は
# PowerShell版のPascalCase（Number/Title/...）ではなく、bash/jqのエコシステムに合わせて
# camelCase（number/title/...）に統一している（詳細: dev-tools/docs/spec/shell-scripts.md）。
#
# 前提: bash, git, jq, gh（GitHubの場合）または glab（GitLabの場合）。
#
# 注意（文字コード）: PowerShell版はシステムのANSI/OEMコードページ対策として明示的な
# UTF-8切り替えが必要だったが、git bash + gh/jq の組み合わせではこの問題が発生しない
# （bashの標準入出力・パイプはコードページの影響を受けない）ため、本ファイルには
# 同種の対策は不要（詳細: dev-tools/docs/spec/shell-scripts.md「文字コード」節）。
#
# 注意（エラー方針）: PowerShell版の `$ErrorActionPreference = "Stop"` に相当する方針として
# `set -euo pipefail` を用いる。個々の関数内で「失敗してもスクリプト全体を止めたくない」箇所は
# `if ! cmd; then ...; fi` の形（`!` 付きコマンドは -e の対象外というbashの仕様）で局所的に握りつぶす。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./Github.sh
source "${SCRIPT_DIR}/Github.sh"
# shellcheck source=./Gitlab.sh
source "${SCRIPT_DIR}/Gitlab.sh"

# issue本文に標準として求める見出し（dev-tools/docs/spec/issue-mr-workflow.md
# 「Issueテンプレート標準化」参照。.github/ISSUE_TEMPLATE/task.md, .gitlab/issue_templates/task.md と対応）
REQUIRED_ISSUE_SECTIONS=("目的" "現状" "期待する動作" "受け入れ条件")

get_repo_root() {
  git rev-parse --show-toplevel
}

# `.mrworkflow.json` が無い場合のデフォルト値をJSONで返す（あればファイルの内容をそのまま返す）。
get_workflow_config() {
  local config_path
  config_path="$(get_repo_root)/.mrworkflow.json"
  if [ -f "$config_path" ]; then
    cat "$config_path"
    return 0
  fi
  cat <<'EOF'
{
  "branchPrefixTemplate": "feature-{issue}-{slug}",
  "defaultBaseBranch": "main",
  "plansDir": "plans",
  "worklogDir": "worklog",
  "specDirs": ["docs/spec", "dev-tools/docs/spec"],
  "ddrDirs": ["docs/ddr", "dev-tools/docs/ddr"]
}
EOF
}

# issueタイトル等を英数字・ハイフンのスラッグへ簡易変換する（ブランチ名・ファイル名に使う）
to_slug() {
  local text="$1"
  local slug
  slug="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  if [ ${#slug} -gt 50 ]; then
    slug="$(printf '%s' "${slug:0:50}" | sed -E 's/-+$//')"
  fi
  if [ -z "$slug" ]; then
    slug="issue"
  fi
  printf '%s' "$slug"
}

# issue本文に標準4見出し（目的・現状・期待する動作・受け入れ条件）が揃っているか確認し、
# 欠けている見出し名を1行1件でstdoutへ出力する（揃っていれば何も出力しない）。プロバイダ非依存。
test_issue_sections() {
  local body="$1"
  local section
  for section in "${REQUIRED_ISSUE_SECTIONS[@]}"; do
    if ! printf '%s\n' "$body" | grep -qE "^##[[:space:]]*${section}[[:space:]]*\$"; then
      printf '%s\n' "$section"
    fi
  done
}

# `git remote get-url origin` のホスト名からプロバイダを判定する
get_provider() {
  local url
  url="$(git remote get-url origin)"
  case "$url" in
    *github.com*) printf 'github\n' ;;
    *gitlab*) printf 'gitlab\n' ;;
    *)
      echo "サポート対象外のリモートです（GitHub/GitLabのみ対応）: $url" >&2
      return 1
      ;;
  esac
}

get_issue() {
  local number="$1"
  case "$(get_provider)" in
    github) github_get_issue "$number" ;;
    gitlab) gitlab_get_issue "$number" ;;
  esac
}

new_draft_merge_request() {
  local issue_number="$1" branch="$2" title="$3"
  local base_branch="${4:-$(get_workflow_config | jq -r '.defaultBaseBranch')}"
  case "$(get_provider)" in
    github) github_new_draft_merge_request "$issue_number" "$branch" "$base_branch" "$title" ;;
    gitlab) gitlab_new_draft_merge_request "$issue_number" "$branch" "$base_branch" "$title" ;;
  esac
}

get_mr_unresolved_comments() {
  local mr_number="$1" include_resolved="${2:-false}"
  case "$(get_provider)" in
    github) github_get_mr_unresolved_comments "$mr_number" "$include_resolved" ;;
    gitlab) gitlab_get_mr_unresolved_comments "$mr_number" "$include_resolved" ;;
  esac
}

# 指定したレビュースレッドに対応内容を返信する（スレッドの解決＝resolvedはレビュアー側の操作のため
# 行わない）。thread_idは get_mr_unresolved_comments の出力に含まれる threadId=... を使う。
add_mr_thread_reply() {
  local mr_number="$1" thread_id="$2" reply_body="$3"
  case "$(get_provider)" in
    github) github_add_mr_thread_reply "$mr_number" "$thread_id" "$reply_body" ;;
    gitlab) gitlab_add_mr_thread_reply "$mr_number" "$thread_id" "$reply_body" ;;
  esac
}

get_mr_for_branch() {
  local branch="$1"
  case "$(get_provider)" in
    github) github_get_mr_for_branch "$branch" ;;
    gitlab) gitlab_get_mr_for_branch "$branch" ;;
  esac
}

set_mr_description() {
  local mr_number="$1" body_file="$2"
  case "$(get_provider)" in
    github) github_set_mr_description "$mr_number" "$body_file" ;;
    gitlab) gitlab_set_mr_description "$mr_number" "$body_file" ;;
  esac
}

# MRへ新規コメントを1件投稿する（スレッド返信ではなく、レビューでもない通常コメント。
# レビュー合否判定には影響しない）。呼び出し元想定: セッション使用量レポート（post-push-usage-report.sh）。
add_mr_comment() {
  local mr_number="$1" body_file="$2"
  case "$(get_provider)" in
    github) github_add_mr_comment "$mr_number" "$body_file" ;;
    gitlab) gitlab_add_mr_comment "$mr_number" "$body_file" ;;
  esac
}

# baseとの差分（コミット）が無いブランチでは `gh pr create` / `glab mr create` が失敗するため
# （new_issue_branch直後など。dev-tools/docs/spec/issue-mr-workflow.md の既知の制約参照）、
# 空コミットを1つ積んでpushすることで回避する。呼び出し元（github_/gitlab_new_draft_merge_request）が
# 失敗を検知した後にこれを呼び、作成を1回だけリトライする。
add_empty_commit_for_draft_mr() {
  git commit --allow-empty -m "chore: Draft PR作成のための空コミット（baseとの差分が無いため）" >/dev/null
  git push >/dev/null
}

# issue番号・スラッグから `.mrworkflow.json` の branchPrefixTemplate に沿ったブランチを作成しcheckout、
# リモートへpushする（ステップ3・4: 「issueからMRとブランチを作る」「作成したブランチをfetch, checkout」）。
new_issue_branch() {
  local issue_number="$1" title="$2"
  local config slug branch base_branch template
  config="$(get_workflow_config)"
  slug="$(to_slug "$title")"
  base_branch="$(printf '%s' "$config" | jq -r '.defaultBaseBranch')"
  template="$(printf '%s' "$config" | jq -r '.branchPrefixTemplate')"
  branch="${template//\{issue\}/$issue_number}"
  branch="${branch//\{slug\}/$slug}"

  git fetch origin "$base_branch"
  git switch -c "$branch" "origin/$base_branch"
  git push -u origin "$branch"

  printf '%s\n' "$branch"
}

# 新しいセッションで作業を再開するとき用（ステップ4の再開版）。
# ローカルにブランチが無ければ origin から作成し、あれば最新化する。
sync_branch() {
  local branch="$1"
  git fetch origin
  if git branch --list "$branch" | grep -q .; then
    git checkout "$branch"
    git pull --ff-only origin "$branch"
  else
    git checkout -b "$branch" "origin/$branch"
  fi
}

# ブランチ名を branchPrefixTemplate に照らしてissue番号を抽出する（途中引き継ぎ対応のresumeで使用）。
# {issue}/{slug} を記号を含まないプレースホルダに置換してから正規表現エスケープすることで、
# テンプレートのリテラル部分だけを正しくエスケープしつつプレースホルダを正規表現化する。
# マッチした場合はissue番号をstdoutへ出力し終了コード0、マッチしなければ何も出力せず終了コード1を返す。
get_issue_number_from_branch() {
  local branch="${1:-$(git branch --show-current)}"
  local template tokenized escaped pattern
  template="$(get_workflow_config | jq -r '.branchPrefixTemplate')"
  tokenized="${template//\{issue\}/ZZISSUEZZ}"
  tokenized="${tokenized//\{slug\}/ZZSLUGZZ}"
  escaped="$(printf '%s' "$tokenized" | sed -E 's/[.[\*^$()+?{}|\\]/\\&/g')"
  pattern="${escaped//ZZISSUEZZ/([0-9]+)}"
  pattern="${pattern//ZZSLUGZZ/.+}"

  if [[ "$branch" =~ ^${pattern}$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# 現在のブランチ固有（<defaultBaseBranch> には無い）の plans/worklog ファイル一覧を返す
# （コミット済み差分＋作業ツリーの未コミット分をマージ・重複排除）。プロバイダ非依存。
get_branch_work_files() {
  local config plans_dir worklog_dir base_branch committed working
  config="$(get_workflow_config)"
  plans_dir="$(printf '%s' "$config" | jq -r '.plansDir')"
  worklog_dir="$(printf '%s' "$config" | jq -r '.worklogDir')"
  base_branch="$(printf '%s' "$config" | jq -r '.defaultBaseBranch')"

  committed="$(git diff --name-only "origin/${base_branch}...HEAD" -- "$plans_dir" "$worklog_dir" 2>/dev/null || true)"
  working="$(git status --porcelain -- "$plans_dir" "$worklog_dir" | sed -E 's/^...//')"

  printf '%s\n%s\n' "$committed" "$working" | sed '/^$/d' | sort -u
}
