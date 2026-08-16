---
title: 対応工数レポート集計が実transcriptでjqのargv長制限に抵触する不具合の修正
type: rule
description: issue #37対応後にPR #47で実際に投稿が止まった原因（jqへの巨大JSONのargv渡し）の追加修正計画
tags: [usage-tracking, bugfix, jq]
keywords: [対応工数レポート, UsageTracking, Argument list too long, argv, jq, 状態ファイル破損]
---

# 対応工数レポート集計が実transcriptでjqのargv長制限に抵触する不具合の修正

## Context

issue #37対応（PR #47）で、対応工数レポートの集計を「セッション横断カーソル＋新規行diff」方式へ
変更した。flow-id 21〜22（plan/worklog削除・HANDOFF.mdリセット・Draft解除）まで完了させた直後、
ユーザーから「MRに対応工数レポートが出なくなっている」という報告を受けた。PR #47はまだ
squash mergeされておらず、本不具合はこのブランチ上でのみ発生している未マージのコードに
起因するため、**新しいissueを起票せず、同じissue #37 / PR #47のブランチ上で追加対応する**
（バグを含んだコードはまだmainへ一切反映されていないため、ここで直接修正するのが最も筋が良い）。

### 原因調査で判明したこと

実データ（このセッション自身のtranscript、`~/.claude/projects/.../b673f394-....jsonl`）を使い、
`.claude/hooks/lib/UsageTracking.sh`の`_usage_aggregate_new_lines`を直接呼び出して再現した結果、
以下のエラーで失敗することを確認した。

```
.claude/hooks/lib/UsageTracking.sh: line 180: /c/Program Files/jq/jq: Argument list too long
```

**根本原因**: `_usage_read_new_lines`が切り出した新規行（`newEntries`。パース済みJSON配列）を、
一度シェル変数へ丸ごと格納したうえで、`_usage_aggregate_new_lines`が`jq -n --argjson entries
"$new_entries" ...`という形で**コマンドライン引数として**jqへ渡している。transcriptの各行には
`tool_use`/`tool_result`の生の入出力（Read/Bashの出力、Editの差分等）がそのまま含まれるため、
新規行がわずか32件（約120KB）程度でもこの引数が肥大化し、Windowsのプロセス生成時の
コマンドライン長上限（実測でおよそ32KB程度）を超えて`jq`の起動自体が失敗する
（`execve`失敗、終了コード126）。実データで検証したところ、このセッション程度の作業量（tool出力を
含む数十行の新規行）で確実に発生する、ほぼ避けられない不具合だった。

`main()`（`post-push-usage-report.sh`）は`set -euo pipefail`で実行されているため、この失敗により
`sync_usage_state`は即座に中断し、`( main ) || true`で握りつぶされる。結果としてMRへの投稿自体が
行われなくなる（ユーザー報告の直接原因）。

**さらに判明した二次的な問題（恒久化のリスク）**: 実際に手元の`usage/state/
feature-37-fix-effort-report-aggregation-logic.json`を確認したところ、内容が0バイト（空）の
状態でカーソルだけが進んでいた（`usage/state/session-cursors/b673f394-....json`の
`lastLineCount`が737）。空の状態ファイルは、次回`sync_usage_state`実行時に
`existing="$(cat "$state_file")"`で空文字列として読み込まれ、`_usage_merge_state`の
`jq -n --argjson existing "$existing" ...`に渡ると`--argjson`への不正なJSON（空文字列）として
**必ず失敗する**。つまり一度state_fileが空／壊れた状態になると、上記のargv長バグを修正しても
**その状態ファイルがある限り恒久的に投稿できなくなる**（別の理由でこの空ファイルが生まれた
可能性はあるが、少なくとも今後同種の要因で状態ファイルが壊れた場合に自己回復できないという
構造的な弱さがある）。

## 対応方針

### A. `_usage_read_new_lines` / `_usage_aggregate_new_lines` を1関数に統合し、transcriptを
   常にファイルとしてjqへ渡す

`_usage_aggregate_transcript`が既に採用している安全なパターン（`jq -R -n ... "$transcript_path"`
で**ファイルパスを渡し、jqの`inputs`でファイル内容を読ませる**。中身をシェル変数やコマンドライン
引数として運ばない）に統一する。

新しい`_usage_aggregate_new_lines(transcript_path, last_line_count, branch)`は、offset以降の
新規行をjq内部でスライス・パース・集計まで一気に行い、**集計結果（`{totalLines, tokens, tools,
assistantCount, skillCalls, agentCalls, askUserQuestions}`）という小さいオブジェクトのみ**を
stdoutへ返す。生のnewEntries配列をシェル側へ一切持ち出さないため、transcriptがどれだけ大きくても
コマンドライン引数の長さに影響しない。

- `sync_usage_state`: `_usage_read_new_lines`→`_usage_aggregate_new_lines`の2段呼び出しを、
  新しい`_usage_aggregate_new_lines "$transcript_path" "$last_line_count" "$branch"`の1回に置き換える。
  返り値から`.totalLines`を取り出してスキップ判定に使い、残りのフィールド（`del(.totalLines)`）を
  deltaとして使う。
- `_usage_aggregate_and_merge_subagents`: 同様にサブエージェントのtranscriptファイル（`$f`）を
  直接渡す形に置き換える。

### B. 破損／空の状態ファイルからの自己回復

`sync_usage_state`が状態ファイルを読む箇所で、内容が有効なJSONかどうかを`jq -e . >/dev/null 2>&1`で
検証し、無効（空・壊れている）であれば`{}`（＝状態なし）として扱う。既存の壊れたデータは失われるが、
「一度壊れると二度と投稿できなくなる」という恒久障害を防ぐ。

### C. ローカルの破損済み状態ファイルの復旧（このマシン限定の作業、コミット対象外）

`usage/`はgitignore対象のため、壊れた実体（`usage/state/feature-37-fix-effort-report-aggregation-logic.json`
が0バイト）は削除して再生成に任せる（対応方針Bにより、削除しなくても次回実行時に自己回復するが、
念のため明示的にクリーンな状態にしておく）。

### D. テスト（`tests/test_usage_tracking.sh`）

- 既存の`_usage_read_new_lines`単体テスト（`totalLines`/オフセット切り出し/不正行の扱い）を、
  新シグネチャ`_usage_aggregate_new_lines(file, offset, branch)`に対する同等のテストへ書き換える
  （ファイルへの複数行書き出し→呼び出し、という形に変更。返り値は集計結果になるため、
  「オフセット以降のみが対象になっている」ことは`assistantCount`等の集計値で検証する）。
- 既存の`_usage_aggregate_new_lines`テスト（skill/agent/question抽出）は、`new_entries`という
  JSON文字列を直接渡す呼び出しから、複数行をファイルへ書き出してファイルパスを渡す呼び出しへ
  書き換える（アサーション内容自体は変更不要）。
- **新規: 大きなペイロードに対する回帰テスト**。1行に数十KB〜100KB程度の長い文字列フィールド
  （実transcriptのtool出力を模した内容）を含むエントリを複数含むtranscriptファイルを作り、
  `_usage_aggregate_new_lines`が例外・エラー終了せず正しく集計できることを確認する
  （今回のバグの直接的な回帰テスト）。
- **新規: 状態ファイル破損からの自己回復テスト**。状態ファイルへ空文字列を書き込んだ状態で
  `sync_usage_state`を呼び、エラー終了せず新しい状態が生成されることを確認する。
- `sync_usage_state`/`_usage_aggregate_and_merge_subagents`を直接呼ぶ既存テスト（session-logs配置・
  カーソル・回帰テスト等）は内部実装の変更のみで外部シグネチャは変わらないため、そのまま維持する。

### E. ドキュメント反映

- `.claude/hooks/lib/UsageTracking.sh`: 関数コメントを新設計に合わせて書き換え、`--argjson`へ
  巨大なtranscript由来のJSONを渡してはいけない理由をコメントとして残す。
- `.claude/rules/shell-script-style.md`「JSON操作」節に、既存のstrptime/CR混入の注意事項と並べて
  「巨大なJSONをコマンドライン引数（`--argjson`等）としてjqへ渡さない。ファイルパスを渡して
  `inputs`で読ませる」という一般的な注意事項を追記する（今後同種のスクリプトを書く際の再発防止）。
- `dev-tools/docs/spec/issue-mr-workflow.md`「コンポーネント」節の関数説明を、統合後の
  `_usage_aggregate_new_lines`シグネチャに合わせて更新する。
- `dev-tools/docs/ddr/0006-対応工数レポートはtranscript自前パースで実装する.md`へ、直前に追加した
  「追記（issue #37）」に続く形で今回のargv長制限バグ・状態ファイル自己回復について追記する
  （このDDRはまだmainへマージされていないブランチ上のものだが、追記形式は既存の運用スタイルに
  合わせて踏襲する）。

## 対象外

- `_usage_merge_state`/`_usage_merge_agent_state`が`--argjson existing`/`--argjson delta`で
  渡すサイズも理論上同じ問題を抱えうるが、これらは`sinceLastPush`という要約済みの小さいデータ
  （通常は1回のpush分、post成功のたびにリセットされる）であり、transcriptの生データほど
  巨大になりにくいため、今回は対応方針Aの範囲（transcriptを直接扱う経路）に限定する。
  将来同種の障害が起きた場合に再検討する。
- issue #37の集計方式そのもの（セッション横断カーソル＋新規行diff）の見直しは行わない。
  今回の不具合はその実装の一部（データの受け渡し方法）にとどまる。

## 検証方法

- `bash tests/test_usage_tracking.sh` で全テスト（既存＋追加分）がpassすること。
- 修正後、実transcript（`~/.claude/projects/.../b673f394-....jsonl`）に対して
  `_usage_aggregate_new_lines`をカーソル位置から直接呼び出し、エラーにならず集計結果が返ることを
  手動確認する。
- `bash -n .claude/hooks/lib/UsageTracking.sh`で構文チェック。
- 修正・テスト・ドキュメントをcommit・pushしたうえで、次回`git push`時に実際にMRへ
  対応工数レポートコメントが投稿されることを確認する（このセッション自身の次のpushで検証可能）。
