---
title: 対応工数レポートのjq argv長制限バグ修正 worklog
type: log
description: PR #47マージ前に発覚した「レポートが投稿されなくなる」不具合の調査・修正ログ
tags: [usage-tracking, bugfix, jq]
keywords: [対応工数レポート, UsageTracking, Argument list too long, argv, 状態ファイル破損]
---

# 対応工数レポートのjq argv長制限バグ修正 worklog

対象issue: #37（追加対応。PR #47はまだ未マージ）
plan: `plans/inherited-gathering-biscuit.md`

## 経緯

issue #37対応（flow-id 11〜22）を完了させ、Draft解除まで終えた直後、ユーザーから
「MRに対応工数レポートが出なくなっている」という報告を受けた。PR #47はまだsquash mergeされて
おらず、不具合を含むコードは一切mainへ反映されていないため、新しいissueを起票せず同じ
issue #37 / PR #47のブランチ上で追加対応することにした。

flow-id 21（plan/worklog削除・HANDOFF.mdリセット）を一度実施済みだったため、本対応にあたり
plan/worklogを再作成し、HANDOFF.mdもissue #37の状態へ戻して継続する。

## 調査結果

実データ（このセッション自身のtranscript）で`_usage_aggregate_new_lines`を直接再現した結果、

```
.claude/hooks/lib/UsageTracking.sh: line 180: /c/Program Files/jq/jq: Argument list too long
```

で失敗することを確認した。新規行32件（約120KB）程度でも発生する。原因は、新規行の配列
（transcriptの生データそのもの。Read/Bash出力等を含む）を`jq -n --argjson entries "$new_entries"`
という形でコマンドライン引数として渡していたこと。Windowsのプロセス生成コマンドライン長上限
（実測でおよそ32KB程度）を超え、`jq`の起動自体が失敗する（exit 126）。

`main()`は`set -euo pipefail`のため、これによりsync_usage_stateが即座に中断し、
`( main ) || true`で握りつぶされ、投稿が行われなくなっていた（ユーザー報告の直接原因）。

さらに、実際に手元の状態ファイル（`usage/state/feature-37-fix-effort-report-aggregation-logic.json`）
が0バイトになっており、カーソルだけが進んだ状態（`lastLineCount: 737`）だったことも確認した。
空の状態ファイルは次回`_usage_merge_state`の`--argjson existing`に渡ると不正なJSONとして必ず
失敗するため、一度この状態になると修正後も自己回復できない構造的な弱さがあることも分かった
（対応方針Bで対処）。

## 対応内容

plan「対応方針A〜E」を実装した。

- A: `_usage_read_new_lines`と`_usage_aggregate_new_lines`を1関数に統合し、
  `_usage_aggregate_transcript`と同じ安全なパターン（`jq -R -n ... "$transcript_path"`でファイル
  パスを渡し`inputs`で読ませる）に統一した。`sync_usage_state`/`_usage_aggregate_and_merge_subagents`
  双方の呼び出し箇所を更新。
- B: `sync_usage_state`の状態ファイル読み込み箇所へ、空文字列チェック→`jq -e .`検証の順で
  妥当性確認を追加し、無効なら`{}`（状態なし）へフォールバックする自己回復ロジックを追加した。
  `jq -e .`は空文字列に対しては失敗を検知できない（実機確認: 終了コード0を返した）ことが分かり、
  空文字列チェックを先に行う実装へ修正した。
- C: 手元の破損した`usage/state/feature-37-fix-effort-report-aggregation-logic.json`（0バイト）を
  削除した。
- D: `tests/test_usage_tracking.sh`を新シグネチャに合わせて書き換え、以下3件の回帰テストを追加した。
  - 巨大なペイロード（50KB×3件の行）でも`Argument list too long`にならないことの確認
  - 状態ファイルが0バイトに破損していても`sync_usage_state`がクラッシュせず自己回復することの確認
  - （テスト実装中に追加で発見: 下記「実装中に見つかった追加のバグ」参照）
  `bash tests/test_usage_tracking.sh`は71件全pass。
- E: `.claude/hooks/lib/UsageTracking.sh`のコメント、`.claude/rules/shell-script-style.md`
  「JSON操作」節、`dev-tools/docs/spec/issue-mr-workflow.md`「コンポーネント」節、
  `dev-tools/docs/ddr/0006-...md`への追記を行った。

### 実装中に見つかった追加のバグ（plan策定時には未知だった）

修正後、実際にこのセッション自身のtranscriptに対して`_usage_aggregate_new_lines`を直接呼び出して
動作確認したところ、別の例外（`Cannot iterate over string`）が発生した。調査の結果、
人間が直接入力したシンプルなテキストメッセージでは`message.content`が単一の文字列のまま
格納される（content-blockの配列ではない）ことが実データで判明した。既存コードは`.[]`で
無条件にイテレートしていたため例外になっていた。配列の場合のみ中身を返すjqヘルパー
`content_blocks`を追加して修正し、回帰テスト（`plain_string_user_entry`）を追加した。

このバグは、plan策定時の再現実験（`_usage_aggregate_new_lines`を直接呼び出したテスト）では
合成データ（`tool_result`ブロックのみを含む配列）しか使っておらず、実データでしか顕在化しない
種類の問題だったため、実装着手後に初めて発覚した。DDR 0006への追記に「教訓」として記録した。

### 検証方法

- `bash tests/test_usage_tracking.sh` で71件全passを確認済み。
- 実際にこのセッション自身のtranscript（`~/.claude/projects/.../b673f394-....jsonl`）に対して
  `_usage_aggregate_new_lines`をカーソル位置（737）・オフセット0の両方から直接呼び出し、
  エラーなく正しい集計結果が返ることを確認した。
- 壊れた状態ファイル（0バイト）を人為的に再現したスクラッチ環境で`sync_usage_state`を呼び、
  クラッシュせず新しい状態が生成されることを確認した。
- `bash -n`で変更した`.sh`ファイルすべての構文チェックを実施済み。
- 最終確認（実際のMRへの投稿）は、本対応をpushした後の次回pushで行われる
  （`post-push-usage-report.sh`自身が毎回`sync_usage_state`を呼ぶため、この一連の修正commitの
  push自体が実地検証を兼ねる）。
