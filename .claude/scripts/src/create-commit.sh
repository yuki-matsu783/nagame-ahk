#!/usr/bin/env bash
#
# `commit` スキル専用のコミット実行ラッパー（issue #39）。
# `.claude/skills/commit/SKILL.md` のStep 5から呼び出す想定。
#
# `git add -- <files>` → `git commit -m <message>` を行うだけの薄いラッパーだが、呼び出し文字列
# 自体（例: `bash .claude/scripts/src/create-commit.sh --message "..." -- file1 file2`）に
# "git commit" という部分文字列を含まないことが目的。`.claude/hooks/block-direct-git-commit.sh`
# （PreToolUse hook）は Bash/PowerShell ツールのコマンド文字列に "git commit" が含まれる場合を
# ブロックするため、このラッパー経由のコミットはhookの対象外になり、commitスキルの正規の実行を
# 妨げない（詳細: .claude/scripts/docs/ddr/0012-コミットはcommitスキル経由を機構的に強制する.md）。
#
# 使い方:
#   .claude/scripts/src/create-commit.sh --message "<コミットメッセージ>" -- <file1> [file2 ...]
#
# `--amend` `--no-verify` `git add .`/`-A` 相当のオプションは持たない（commitスキルの絶対ルールを
# 呼び出し側だけでなくラッパー側でも構造的に不可能にするため）。

set -euo pipefail

usage() {
  cat <<'EOF'
使い方: create-commit.sh --message <コミットメッセージ> -- <file1> [file2 ...]

--message と、`--` 以降の対象ファイル1件以上が必須です。
EOF
}

message=""
files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --message) message="$2"; shift 2 ;;
    --) shift; files=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "不明な引数です: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$message" ]; then
  echo "エラー: --message は必須です" >&2
  usage >&2
  exit 1
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "エラー: コミット対象ファイルを -- の後に1件以上指定してください" >&2
  usage >&2
  exit 1
fi

git add -- "${files[@]}"
git commit -m "$message"
