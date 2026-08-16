#!/usr/bin/env bash
#
# Claude Code PostToolUse hook（git push検知、bash版）。
# 設計: plans/groovy-zooming-balloon.md（issue #15）→ dev-tools/docs/spec/issue-mr-workflow.md,
#       dev-tools/docs/spec/shell-scripts.md（issue #6、bash化）
#
# .claude/settings.json 側で matcher: "Bash|PowerShell" と、各エントリの if フィールド
# （"Bash(git push*)" / "PowerShell(git push*)"）によって、tool_input のコマンドが
# git push を含む場合のみ起動される（マッチしなければClaude Code側でプロセスが起動されず、
# 通常のBash/PowerShell利用への性能影響は無い）。if フィルタはベストエフォートのため、
# 本スクリプト側でも念のため command 文字列を正規表現で再チェックする。
#
# 投稿前に、自分自身で .claude/hooks/lib/UsageTracking.sh の sync_usage_state を呼んで
# 状態を最新化する（トークン数・ツール実行回数・assistant応答回数のいずれも、このタイミングで
# transcriptとの差分を計算する）。これにより、当該ターンの途中でgit pushが実行されるケース
# （例: 最初のpushがブランチ作成・調査・実装と同じターン内で行われる場合）でも、その時点までに
# transcriptへ書き出し済みの内容を漏れなく反映できる。
#
# `sinceLastPush` を読み、MRへ新規コメントとして投稿する（レビューではない通常コメントのため、
# レビュー合否判定には影響しない）。投稿に成功したら `sinceLastPush` をリセットする。失敗時は
# 状態を変更せず握りつぶす（次のpush時に繰り越されるだけで、git push自体をブロックしない）。
#
# 注意（エラー方針）: 本体処理は `main` 関数にまとめ、`( main )` のように実サブシェル（丸括弧）の
# 中で呼ぶことで、内部で失敗したコマンドの時点で確実にサブシェルごと終了させる（bashの
# 「if/||の条件式の中では-eが一時停止する」という仕様の影響を受けないようにするため。詳細:
# dev-tools/docs/spec/shell-scripts.md「bashでのtry/catch相当の書き方」節）。失敗はすべて
# 握りつぶし、git push自体はブロックしない。

set -uo pipefail

fmt_num() {
  # 3桁ごとにカンマを挿入する（PowerShell版の "{0:N0}" 相当）
  printf '%d' "$1" | sed -E ':a; s/([0-9])([0-9]{3})(,|$)/\1,\2\3/; ta'
}

fmt_duration() {
  # 秒 → "H時間M分" / "M分" 形式（UsageTracking.shのactiveSecondsをレポート表示用に整形する）
  local total_seconds="$1"
  local hours minutes
  hours=$(( total_seconds / 3600 ))
  minutes=$(( (total_seconds % 3600) / 60 ))
  if [ "$hours" -gt 0 ]; then
    printf '%d時間%d分' "$hours" "$minutes"
  else
    printf '%d分' "$minutes"
  fi
}

main() {
  set -euo pipefail

  local raw
  raw="$(cat)"
  [ -n "$raw" ] || exit 0

  local hook_input
  hook_input="$(printf '%s' "$raw" | jq -c '.' 2>/dev/null)" || exit 0
  [ -n "$hook_input" ] || exit 0

  local agent_id
  agent_id="$(printf '%s' "$hook_input" | jq -r '.agent_id // empty')"
  # サブエージェント内実行では何もしない（SessionStart hookと同じガード。並行書き込みによる
  # 状態ファイル競合を避ける意味もある）
  [ -z "$agent_id" ] || exit 0

  [ -n "${CLAUDE_PROJECT_DIR:-}" ] || exit 0

  local tool_name
  tool_name="$(printf '%s' "$hook_input" | jq -r '.tool_name // empty')"
  if [ "$tool_name" != "Bash" ] && [ "$tool_name" != "PowerShell" ]; then
    exit 0
  fi

  local command
  command="$(printf '%s' "$hook_input" | jq -r '.tool_input.command // empty')"
  if [ -z "$command" ] || ! printf '%s' "$command" | grep -qiE 'git[[:space:]]+push'; then
    exit 0
  fi

  cd "$CLAUDE_PROJECT_DIR"
  source "${CLAUDE_PROJECT_DIR}/dev-tools/src/vcs/Provider.sh"
  source "${CLAUDE_PROJECT_DIR}/.claude/hooks/lib/UsageTracking.sh"

  local branch base_branch
  branch="$(git branch --show-current 2>/dev/null || true)"
  base_branch="$(get_workflow_config | jq -r '.defaultBaseBranch')"
  [ -n "$branch" ] && [ "$branch" != "$base_branch" ] || exit 0

  local session_id transcript_path repo_root
  session_id="$(printf '%s' "$hook_input" | jq -r '.session_id // empty')"
  transcript_path="$(printf '%s' "$hook_input" | jq -r '.transcript_path // empty')"
  repo_root="$(get_repo_root)"

  local safe_branch state_dir state_file state=""
  safe_branch="$(_usage_safe_branch_name "$branch")"
  state_dir="${repo_root}/usage/state"
  state_file="${state_dir}/${safe_branch}.json"

  # 投稿判定の前に、その時点までtranscriptへ書き出し済みの内容を状態へ反映する
  # （ターンの途中でのpushでも、初回pushなどで記録漏れが起きないようにするための同期）
  if [ -n "$session_id" ] && [ -n "$transcript_path" ]; then
    state="$(sync_usage_state "$repo_root" "$branch" "$session_id" "$transcript_path" || true)"
  fi

  if [ -z "$state" ]; then
    [ -f "$state_file" ] || exit 0
    state="$(cat "$state_file")"
  fi

  if [ "$(printf '%s' "$state" | jq 'has("sinceLastPush")')" != "true" ]; then
    exit 0
  fi
  local usage subagent_usage
  usage="$(printf '%s' "$state" | jq -c '.sinceLastPush')"
  # サブエージェントはagentId単位で保持されている（issue #34: agentType単位の合算からagentIdごと
  # の表示へ変更）。投稿要否判定の合計計算はagentId単位のままでも合計値に影響しない
  # （0件除外は合計を変えないため、表示用フィルタは後段でのみ適用する）。
  subagent_usage="$(printf '%s' "$state" | jq -c '.sinceLastPush.subagents // {}')"

  # 合計が0なら投稿しない（初回push・使用量が積み上がっていないpush対策）。メイン自身の消費が
  # ほぼ0でも、サブエージェント作業だけが行われたpushでレポートが握りつぶされないよう、
  # サブエージェント分のトークン合計も含める。
  local total
  total="$(jq -n --argjson usage "$usage" --argjson subagentUsage "$subagent_usage" '
    ([$usage.tokensByModel[] | (.input // 0) + (.output // 0) + (.cacheCreate // 0) + (.cacheRead // 0)] | add // 0)
    + ([$subagentUsage[] | .tokensByModel[]? | ((.input // 0) + (.output // 0) + (.cacheCreate // 0) + (.cacheRead // 0))] | add // 0)
  ')"
  [ "$total" != "0" ] || exit 0

  # 表示は「差分0のagentは出力しない」方針（issue #34のユーザー指示）。合計計算後、
  # テーブル描画・稼働時間参考値等の表示処理はすべてこのフィルタ後の値に対して行う。
  subagent_usage="$(_usage_filter_nonzero_subagents "$subagent_usage")"

  local mr
  mr="$(get_mr_for_branch "$branch")"
  [ -n "$mr" ] || exit 0
  local mr_number
  mr_number="$(printf '%s' "$mr" | jq -r '.number')"

  # このMR（ブランチ）に対して過去に投稿成功したことがあるか（state.lastPostedAtの有無で判定）。
  # 免責事項の説明文（フッター）は初回投稿時のみ表示し、毎回同じ文言が繰り返し投稿されるのを防ぐ
  # （PR #29レビュー指摘）。
  local is_first_post
  is_first_post="$(printf '%s' "$state" | jq -r 'if .lastPostedAt then "false" else "true" end')"

  # --- コメント本文の組み立て ---
  local tmp_file
  tmp_file="$(mktemp)"
  {
    echo "## 対応工数レポート（自動投稿・前回pushからの差分）"
    echo ""
    echo "> このコメントはClaude Codeによる自動投稿です。**レビューの合否判定には使用しないでください。**"
    echo ""
    echo "- ブランチ: ${branch}"
    echo "- assistant応答回数: $(printf '%s' "$usage" | jq -r '.turns')"
    echo "- 対応工数（目安・入力待ち時間を除く）: $(fmt_duration "$(printf '%s' "$usage" | jq -r '.activeSeconds // 0')")"
    echo ""
    echo "| モデル | Input | Output | Cache Write | Cache Read |"
    echo "|---|---:|---:|---:|---:|"
    local model
    # 注意（`tr -d '\r'`）: このマシンのWindowsネイティブjq（`C:\Program Files\jq\jq.exe`）は
    # `jq -r`の出力の各行末に`\r`を付与する（shell-script-style.md「文字コード」節が挙げる
    # ファイルリダイレクト時の既知の挙動と同根だが、コマンド置換でも発生することを本issue #34の
    # 実装時に確認した）。`$(...)`によるコマンド置換は最後の行の末尾改行のみを取り除くため、
    # 2件以上の要素がある場合、最後の要素以外はfor変数に`\r`が付いたまま渡り、以降の
    # `--arg`によるキー参照が一致せずnullになる（実際に本テーブルで再現・修正した）。
    for model in $(printf '%s' "$usage" | jq -r '.tokensByModel | keys[]' | tr -d '\r' | sort); do
      local m input_v output_v create_v read_v
      m="$(printf '%s' "$usage" | jq -c --arg model "$model" '.tokensByModel[$model]')"
      input_v="$(printf '%s' "$m" | jq -r '.input // 0')"
      output_v="$(printf '%s' "$m" | jq -r '.output // 0')"
      create_v="$(printf '%s' "$m" | jq -r '.cacheCreate // 0')"
      read_v="$(printf '%s' "$m" | jq -r '.cacheRead // 0')"
      # "<synthetic>"等、4項目とも0のモデル行はノイズなので表示しない（transcript側が
      # usageの無いプレースホルダーentryにmodel名を割り当てているケースがある）
      if [ "$input_v" = "0" ] && [ "$output_v" = "0" ] && [ "$create_v" = "0" ] && [ "$read_v" = "0" ]; then
        continue
      fi
      echo "| ${model} | $(fmt_num "$input_v") | $(fmt_num "$output_v") | $(fmt_num "$create_v") | $(fmt_num "$read_v") |"
    done
    echo ""
    local tool_summary
    # 差分0のツールはキーごと表示しない（`_usage_merge_state`のtoolCalls集計は、過去に一度でも
    # 使われたツールなら差分0でもキー自体は必ず作る仕様のため、フィルタしないと「XXXツール: 0」が
    # 過去に使ったツール分だけ延々と残り続けてしまう。トークンテーブルの0行除外と同じ考え方）
    tool_summary="$(printf '%s' "$usage" | jq -r '.toolCalls | to_entries | map(select(.value > 0)) | sort_by(.key) | map("\(.key): \(.value)") | join(", ")')"
    if [ -n "$tool_summary" ]; then
      echo "**ツール実行回数**: ${tool_summary}"
      echo ""
    fi

    # skill呼び出し・Agent呼び出し・ユーザーへの質問の詳細テーブル（issue #37）。
    # いずれもメインセッションのtranscriptのみを対象とする（サブエージェント自身が呼び出した分・
    # ネストしたサブエージェントは対象外）。各セルは`description`列と同じくパイプをエスケープし、
    # 改行は半角スペースへつぶす（表が崩れないようにするため）。`tr -d '\r'`はWindowsネイティブjqの
    # コマンド置換CR混入対策（既存箇所と同じ理由）。

    if [ "$(printf '%s' "$usage" | jq '.skillCalls | length')" != "0" ]; then
      echo "### skill呼び出し"
      echo ""
      echo "| skill | args |"
      echo "|---|---|"
      local skill_count i
      skill_count="$(printf '%s' "$usage" | jq '.skillCalls | length')"
      for i in $(seq 0 $((skill_count - 1))); do
        local skill_name skill_args
        skill_name="$(printf '%s' "$usage" | jq -r --argjson i "$i" '.skillCalls[$i].skill // ""' | tr -d '\r' | tr '\n' ' ' | sed 's/|/\\|/g')"
        skill_args="$(printf '%s' "$usage" | jq -r --argjson i "$i" '.skillCalls[$i].args // ""' | tr -d '\r' | tr '\n' ' ' | sed 's/|/\\|/g')"
        echo "| ${skill_name} | ${skill_args} |"
      done
      echo ""
    fi

    if [ "$(printf '%s' "$usage" | jq '.agentCalls | length')" != "0" ]; then
      echo "### Agent呼び出し"
      echo ""
      echo "Agentツールで起動されたサブエージェントの呼び出し記録です（呼び出し時点の記録のため、"
      echo "対応するサブエージェントがまだ完了していなくても表示されます。下記の「### サブエージェント」"
      echo "＝トークン/稼働時間の実績テーブルとは別集計です。プロンプトは300文字を超える場合"
      echo "末尾を省略しています）。"
      echo ""
      echo "| サブエージェント種別 | 説明 | プロンプト |"
      echo "|---|---|---|"
      local agent_call_count i
      agent_call_count="$(printf '%s' "$usage" | jq '.agentCalls | length')"
      for i in $(seq 0 $((agent_call_count - 1))); do
        local a_subtype a_desc a_prompt
        a_subtype="$(printf '%s' "$usage" | jq -r --argjson i "$i" '.agentCalls[$i].subagentType // ""' | tr -d '\r' | tr '\n' ' ' | sed 's/|/\\|/g')"
        a_desc="$(printf '%s' "$usage" | jq -r --argjson i "$i" '.agentCalls[$i].description // ""' | tr -d '\r' | tr '\n' ' ' | sed 's/|/\\|/g')"
        a_prompt="$(printf '%s' "$usage" | jq -r --argjson i "$i" '.agentCalls[$i].prompt // "" | if (length > 300) then (.[0:300] + "…") else . end' | tr -d '\r' | tr '\n' ' ' | sed 's/|/\\|/g')"
        echo "| ${a_subtype} | ${a_desc} | ${a_prompt} |"
      done
      echo ""
    fi

    if [ "$(printf '%s' "$usage" | jq '.askUserQuestions | length')" != "0" ]; then
      echo "### ユーザーへの質問"
      echo ""
      echo "| 質問 | 回答 |"
      echo "|---|---|"
      local question_count i
      question_count="$(printf '%s' "$usage" | jq '.askUserQuestions | length')"
      for i in $(seq 0 $((question_count - 1))); do
        local q a
        q="$(printf '%s' "$usage" | jq -r --argjson i "$i" '.askUserQuestions[$i].question // ""' | tr -d '\r' | tr '\n' ' ' | sed 's/|/\\|/g')"
        a="$(printf '%s' "$usage" | jq -r --argjson i "$i" '.askUserQuestions[$i].answer // ""' | tr -d '\r' | tr '\n' ' ' | sed 's/|/\\|/g')"
        echo "| ${q} | ${a} |"
      done
      echo ""
    fi

    # サブエージェント（Task/Agentツール等で起動された別セッション）の使用量。メインセッションの
    # 数値には含まれないため独立セクションとして表示する（既存テーブルへの行追加ではなく、
    # 主体が異なる数値を明確に区別するため。PR #29レビュー指摘）。ネストしたサブエージェント
    # （depth 2以降）は対象外。agentId単位で1行ずつ表示する（issue #34: 同じagentTypeを複数回
    # 起動してもどのagentがどれだけ使ったか見えるようにするため、agentType合算表示から変更）。
    # 差分0のagentは呼び出し元で`_usage_filter_nonzero_subagents`により除外済み。
    if [ "$(printf '%s' "$subagent_usage" | jq 'keys | length')" != "0" ]; then
      echo "### サブエージェント"
      echo ""
      echo "Task/Agentツールで起動されたサブエージェント内の使用量です（メインセッションの数値には"
      echo "含まれません。ネストしたサブエージェントは対象外です。前回pushから差分の無いagentは"
      echo "表示していません）。"
      echo ""
      echo "| エージェント種別 | 説明 | モデル | Input | Output | Cache Write | Cache Read |"
      echo "|---|---|---|---:|---:|---:|---:|"
      local agent_id
      # `tr -d '\r'`の理由は上のモデルループのコメントと同じ（Windowsネイティブjqのコマンド置換
      # 経由でのCR混入対策）。agentIdが2件以上ある場合に必ず顕在化するため、
      # このagent単位表示（issue #34の主目的）では特に重要。
      for agent_id in $(printf '%s' "$subagent_usage" | jq -r 'to_entries | sort_by(.value.agentType, .value.description) | .[].key' | tr -d '\r'); do
        local a_usage a_type a_desc model
        a_usage="$(printf '%s' "$subagent_usage" | jq -c --arg id "$agent_id" '.[$id]')"
        a_type="$(printf '%s' "$a_usage" | jq -r '.agentType // "unknown"')"
        # description中の"|"はMarkdownテーブルの区切りと衝突するためエスケープする
        a_desc="$(printf '%s' "$a_usage" | jq -r '.description // ""' | sed 's/|/\\|/g')"
        for model in $(printf '%s' "$a_usage" | jq -r '.tokensByModel | keys[]' | tr -d '\r' | sort); do
          local m input_v output_v create_v read_v
          m="$(printf '%s' "$a_usage" | jq -c --arg model "$model" '.tokensByModel[$model]')"
          input_v="$(printf '%s' "$m" | jq -r '.input // 0')"
          output_v="$(printf '%s' "$m" | jq -r '.output // 0')"
          create_v="$(printf '%s' "$m" | jq -r '.cacheCreate // 0')"
          read_v="$(printf '%s' "$m" | jq -r '.cacheRead // 0')"
          # 全項目0の行は表示しない（トークンテーブルの<synthetic>行除外と同じ考え方）
          if [ "$input_v" = "0" ] && [ "$output_v" = "0" ] && [ "$create_v" = "0" ] && [ "$read_v" = "0" ]; then
            continue
          fi
          echo "| ${a_type} | ${a_desc} | ${model} | $(fmt_num "$input_v") | $(fmt_num "$output_v") | $(fmt_num "$create_v") | $(fmt_num "$read_v") |"
        done
      done
      echo ""
      local subagent_tool_summary
      # 差分0のツールはキーごと表示しない（メインのtool_summaryと同じ理由）
      subagent_tool_summary="$(printf '%s' "$subagent_usage" | jq -r '
        [.[] | .toolCalls | to_entries[]]
        | group_by(.key)
        | map({key: .[0].key, value: (map(.value) | add)})
        | map(select(.value > 0))
        | sort_by(.key)
        | map("\(.key): \(.value)")
        | join(", ")
      ')"
      if [ -n "$subagent_tool_summary" ]; then
        echo "**ツール実行回数（サブエージェント合計）**: ${subagent_tool_summary}"
        echo ""
      fi
      local subagent_active_seconds
      subagent_active_seconds="$(printf '%s' "$subagent_usage" | jq '[.[] | .activeSeconds // 0] | add // 0')"
      echo "- 稼働時間（サブエージェント内・参考値。メインの対応工数とは別集計で重複除去はしていません）: $(fmt_duration "$subagent_active_seconds")"
      echo ""
    fi
    if [ "$is_first_post" = "true" ]; then
      echo "---"
      echo "### Claude Codeより"
      echo "post-push-usage-report.sh による集計。"
      echo "セッション情報ログを解析した集計のため、目安として扱ってください。"
      echo "既知の過小カウント要因が報告されています。"
      echo "詳細:https://gille.ai/en/blog/claude-code-jsonl-logs-undercount-tokens/"
    fi
  } > "$tmp_file"

  add_mr_comment "$mr_number" "$tmp_file"
  rm -f "$tmp_file"

  # 投稿成功時のみ sinceLastPush をリセットする（失敗時は次回pushへ繰り越す。
  # add_mr_commentが失敗した場合はここに到達せず、set -e により main ごと中断される）。
  # リセットロジック本体は UsageTracking.sh の _usage_reset_since_last_push に切り出してある
  # （tests/test_usage_tracking.sh から同じロジックで「2回目push」を再現できるようにするため）。
  local reset_state
  reset_state="$(_usage_reset_since_last_push "$state")"
  mkdir -p "$state_dir"
  printf '%s' "$reset_state" > "$state_file"
}

( main ) || true

exit 0
