#!/usr/bin/env bash
# 指定ディレクトリ配下のmarkdownファイルからYAML frontmatterのみを抽出し、
# 1行1JSONの index.jsonl として出力する（既存があれば上書き）。
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

# 単純なスカラー値・フロー配列 [a, b, c]・ブロック配列（改行+ "  - item"）のみに対応した
# 自前の軽量YAML→JSON変換。フルYAML文法は非対応（本リポジトリのfrontmatterスキーマ専用。
# 詳細: .claude/rules/shell-script-style.md, .claude/rules/markdown-frontmatter.md）。
# frontmatterが無いファイルは文字列 "null" を返す。
frontmatter_to_json() {
  local file="$1"
  local first_line=""
  IFS= read -r first_line <"$file" || true
  first_line="${first_line%$'\r'}"
  if [[ "$first_line" != "---" ]]; then
    echo "null"
    return 0
  fi

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

  local line_no=0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    line="${line%$'\r'}"
    if [[ $line_no -eq 1 ]]; then
      continue
    fi
    if [[ "$line" == "---" ]]; then
      flush_list
      break
    fi
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
  done <"$file"

  echo "$json"
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

  local out_file="$target_dir/index.jsonl"
  : >"$out_file"

  local file
  while IFS= read -r -d '' file; do
    local rel="${file#"$target_dir"/}"
    local concept_id="${rel%.md}"
    local dir
    dir="$(dirname "$rel")"
    local fm
    fm="$(frontmatter_to_json "$file")"
    local epoch
    epoch="$(stat -c %Y "$file")"
    local mtime
    mtime="$(date -d "@$epoch" +"%Y-%m-%dT%H:%M:%S")"
    jq -nc \
      --arg concept_id "$concept_id" \
      --arg directory "$dir" \
      --argjson frontmatter "$fm" \
      --arg mtime "$mtime" \
      '{concept_id: $concept_id, directory: $directory, frontmatter: $frontmatter, mtime: $mtime}' \
      >>"$out_file"
  done < <(find "$target_dir" -type f -name '*.md' -print0 | sort -z)

  echo "wrote: $out_file" >&2
}

# 単体テスト（tests/test_extract_frontmatter.sh）からsourceして関数のみ再利用できるよう、
# 直接実行された場合のみ main を呼ぶ。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
