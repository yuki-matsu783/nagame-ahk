#!/usr/bin/env bash
# 指定ディレクトリ配下を再帰的に走査し、YAML frontmatterのみを抽出する。
# markdownファイルが直下に存在するディレクトリ毎に、そのディレクトリ自身へ1行1JSONの
# index.jsonl を出力する（既存があれば上書き。1回の実行で複数ファイルになりうる）。
# concept_id/directoryは、実行時に指定したディレクトリではなく常にgitリポジトリのルートからの
# 相対パスを基準にする（例: リポジトリルートで実行しても docs/ を指定して実行しても、
# docs/spec/activity-status.md のconcept_idは常に "docs/spec/activity-status"）。
# 使い方: extract-frontmatter.sh <directory>（リポジトリルートで "." を指定すると、
# markdownを含む全ディレクトリのindex.jsonlを一括生成できる）。
# YAML→JSON変換は、PATH上に`yq`（https://github.com/mikefarah/yq）があれば優先的に使い、
# 無ければ本リポジトリのfrontmatterスキーマに絞った自前の軽量パーサーへフォールバックする
# （yqを新規の必須外部依存にはしない）。
# 設計反映時に dev-tools/docs/spec/ へ正史仕様として記録する予定（issue #7 PR #23レビュー対応）。
set -euo pipefail

# 前後の空白を取り除く
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# 前後がダブルクォートで囲まれていれば取り除く
unquote() {
  local s="$1"
  if [[ "$s" == \"*\" && "$s" == *\" && ${#s} -ge 2 ]]; then
    s="${s#\"}"
    s="${s%\"}"
  fi
  printf '%s' "$s"
}

# frontmatterの中身（区切り行 "---" を含まない）を標準出力へ返す。
# frontmatterが無ければ何も出力せず終了コード1を返す。
extract_frontmatter_block() {
  local file="$1"
  local first_line=""
  IFS= read -r first_line <"$file" || true
  first_line="${first_line%$'\r'}"
  if [[ "$first_line" != "---" ]]; then
    return 1
  fi

  local line_no=0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    line="${line%$'\r'}"
    if [[ $line_no -eq 1 ]]; then
      continue
    fi
    if [[ "$line" == "---" ]]; then
      return 0
    fi
    printf '%s\n' "$line"
  done <"$file"
  return 0
}

# 単純なスカラー値・フロー配列 [a, b, c]・ブロック配列（改行+ "  - item"）のみに対応した
# 自前の軽量YAML→JSON変換。フルYAML文法は非対応（本リポジトリのfrontmatterスキーマ専用。
# 詳細: .claude/rules/shell-script-style.md, .claude/rules/markdown-frontmatter.md）。
# 標準入力からfrontmatterブロック本文（区切り行を含まない）を読み、JSONを標準出力へ返す。
# yqが使えない環境向けのフォールバック実装（frontmatter_to_json参照）。
frontmatter_block_to_json() {
  local json="{}"
  local list_key=""
  local -a list_items=()

  flush_list() {
    if [[ -n "$list_key" ]]; then
      local arr="[]"
      local item
      for item in "${list_items[@]:-}"; do
        [[ -z "$item" ]] && continue
        arr=$(jq -c --arg v "$item" '. + [$v]' <<<"$arr")
      done
      json=$(jq -c --arg k "$list_key" --argjson v "$arr" '. + {($k): $v}' <<<"$json")
      list_key=""
      list_items=()
    fi
  }

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^([A-Za-z0-9_]+):[[:space:]]*(.*)$ ]]; then
      flush_list
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      if [[ -z "$val" ]]; then
        # 値が空 = 後続行のブロック配列（"  - item"）を期待する
        list_key="$key"
        continue
      fi
      if [[ "$val" == \[*\] ]]; then
        local inner="${val#\[}"
        inner="${inner%\]}"
        local arr="[]"
        local part
        while IFS= read -r part; do
          part="$(unquote "$(trim "$part")")"
          [[ -z "$part" ]] && continue
          arr=$(jq -c --arg v "$part" '. + [$v]' <<<"$arr")
        done < <(tr ',' '\n' <<<"$inner")
        json=$(jq -c --arg k "$key" --argjson v "$arr" '. + {($k): $v}' <<<"$json")
      elif [[ "$val" == "true" || "$val" == "false" ]]; then
        json=$(jq -c --arg k "$key" --argjson v "$val" '. + {($k): $v}' <<<"$json")
      else
        val="$(unquote "$val")"
        json=$(jq -c --arg k "$key" --arg v "$val" '. + {($k): $v}' <<<"$json")
      fi
    elif [[ "$line" =~ ^[[:space:]]+-[[:space:]]*(.*)$ ]]; then
      local item="${BASH_REMATCH[1]}"
      item="$(unquote "$(trim "$item")")"
      list_items+=("$item")
    fi
  done
  flush_list

  echo "$json"
}

# frontmatterをJSONへ変換する（公開関数）。frontmatterが無いファイルは文字列 "null" を返す。
# `yq`（https://github.com/mikefarah/yq）がPATH上にあれば優先的に使い、フルYAML文法への対応力を
# 上げる。無い、または変換に失敗した場合は自前の軽量パーサー（frontmatter_block_to_json）へ
# フォールバックする（yqを新規の必須外部依存にはしない。PR #23レビュー対応）。
frontmatter_to_json() {
  local file="$1"
  local block
  if ! block="$(extract_frontmatter_block "$file")"; then
    echo "null"
    return 0
  fi

  if command -v yq >/dev/null 2>&1; then
    local yq_out
    if yq_out="$(printf '%s\n' "$block" | yq -o=json e '.' - 2>/dev/null)" && jq empty <<<"$yq_out" >/dev/null 2>&1; then
      echo "$yq_out"
      return 0
    fi
    # yqでの変換に失敗した場合は自前パーサーへフォールバックする
  fi

  printf '%s\n' "$block" | frontmatter_block_to_json
}

# gitリポジトリのルートを、MSYS形式（/c/...）に正規化して返す。
# `git rev-parse --show-toplevel`はWindowsドライブレター形式（C:/...）で返るため、
# `realpath --relative-to`の基準に使うと表記が一致せず相対パス計算が失敗する
# （実機確認済み）。`cd`はどちらの表記も受け付けるため、一度cdしてから`pwd`で
# 一貫したMSYS形式を取得する。
resolve_repo_root() {
  local start_dir="$1"
  (cd "$start_dir" && cd "$(git rev-parse --show-toplevel)" && pwd)
}

main() {
  local target_dir="${1:-}"
  if [[ -z "$target_dir" ]]; then
    echo "usage: extract-frontmatter.sh <directory>" >&2
    exit 1
  fi
  if [[ ! -d "$target_dir" ]]; then
    echo "error: directory not found: $target_dir" >&2
    exit 1
  fi
  target_dir="${target_dir%/}"

  local repo_root
  repo_root="$(resolve_repo_root "$target_dir")"

  # markdownが直下に存在するディレクトリごとにindex.jsonlを生成する（1回の実行で複数ファイルに
  # なりうる）。concept_id/directoryは実行時の指定ディレクトリではなく、常にgitリポジトリの
  # ルートからの相対パスを基準にする（PR #23レビュー対応）。
  local -A seen_out_files=()
  local file
  while IFS= read -r -d '' file; do
    local rel
    rel="$(realpath --relative-to="$repo_root" "$file")"
    local concept_id="${rel%.md}"
    local dir
    dir="$(dirname "$rel")"
    local out_file
    out_file="$(dirname "$file")/index.jsonl"
    if [[ -z "${seen_out_files[$out_file]:-}" ]]; then
      : >"$out_file"
      seen_out_files[$out_file]=1
    fi
    local fm
    fm="$(frontmatter_to_json "$file")"
    local epoch
    epoch="$(stat -c %Y "$file")"
    local mtime
    mtime="$(date -d "@$epoch" +"%Y-%m-%dT%H:%M:%S")"
    # Windows版jqバイナリ（native、MSYS版ではない）は行末にCRを付与することがあるため、
    # ファイルへ直接書き出す最終出力のみtrで取り除きLF改行に統一する（詳細:
    # .claude/rules/shell-script-style.md「保存形式」）。
    jq -nc \
      --arg concept_id "$concept_id" \
      --arg directory "$dir" \
      --argjson frontmatter "$fm" \
      --arg mtime "$mtime" \
      '{concept_id: $concept_id, directory: $directory, frontmatter: $frontmatter, mtime: $mtime}' \
      | tr -d '\r' >>"$out_file"
  done < <(git ls-files --cached --others --exclude-standard -z -- "$target_dir" | grep -z '\.md$' | sort -z)

  local out_file
  for out_file in "${!seen_out_files[@]}"; do
    echo "wrote: $out_file" >&2
  done
}

# 単体テスト（tests/test_extract_frontmatter.sh）からsourceして関数のみ再利用できるよう、
# 直接実行された場合のみ main を呼ぶ。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
