---
title: worklog サブエージェント対応工数push差分バグ修正
type: log
description: issue #34 サブエージェント分の対応工数レポートがpush差分にならないバグの調査・修正worklog
tags: [worklog, usage-tracking, bugfix]
keywords: [サブエージェント, 対応工数, UsageTracking, sinceLastPush, agents, push差分, agentId, description]
---

# worklog: cheeky-sprouting-pine

対象: issue #34 サブエージェント対応工数のpush差分バグ修正・表示のagent単位化（2026-08-16）。
plan: `plans/cheeky-sprouting-pine.md`
（第1版plan・worklogは `plans/cheeky-sprouting-pine_act1.md` /
`worklog/20260816_cheeky-sprouting-pine_act1.md` へ退避済み。バグ修正のみのplanだった）

## 試したこと

- issue #34の内容確認: 「サブエージェントの対応工数がずっと同じ値」という報告。
- `.claude/hooks/post-push-usage-report.sh` / `.claude/hooks/lib/UsageTracking.sh` を読み、
  サブエージェント集計の流れ（`_usage_sync_session_logs` → `_usage_aggregate_transcript` →
  `_usage_merge_agent_state` → `_usage_aggregate_and_merge_subagents`）を追った。
- `tests/test_usage_tracking.sh` の既存テストを実行し全passを確認（単体レベルでは問題なし）。
- `/tmp/repro_usage.sh` にて、`sync_usage_state` を3回連続で呼ぶ再現シナリオ
  （push#1: 初回, push#2: サブエージェントtranscript不変のまま再push, push#3: transcriptへ
  追記してからpush）を作成し、`post-push-usage-report.sh` と同じリセット処理を模して
  push間で `sinceLastPush` をゼロ化してから検証した。

## うまくいったこと

- 再現に成功。push#2（transcript不変）でも1回目と全く同じ値
  （tokens input/output=1/1, activeSeconds=30）が再度計上され、push#3（+5/+5, +30s追記）でも
  差分ではなく累積値（6/6, 60s）になることを確認した。
- 原因を特定: `_usage_merge_state` の戻り値オブジェクトが `$existing.agents`
  （agentId単位の累計スナップショット）を引き継いでおらず、`sync_usage_state` 内で
  メインセッションのマージ→サブエージェントのマージの順に呼ばれる際、1段目の
  `_usage_merge_state` 呼び出しで `.agents` が消失する。そのため2段目の
  `_usage_aggregate_and_merge_subagents` は常に「前回スナップショット無し」として扱い、
  transcript全体を毎回新規差分として計上してしまう。
- 修正案（`_usage_merge_state` の出力に既存の `lastPostedAt` passthroughと同じパターンで
  `agents` のpassthroughを追加）を `/tmp/UsageTracking_fixed.sh` に適用し、同じ再現シナリオで
  push#2が0、push#3が正しい差分のみになることを確認。既存25件の単体テストも全passのまま。
- `_usage_merge_agent_state` / `_usage_aggregate_and_merge_subagents` / `_usage_aggregate_transcript`
  自体のロジックは正しいことを確認（バグはこれらの関数間の受け渡し部分のみ）。

## ダメだったこと

- 特になし。

## 追加のスコープ（ユーザーフィードバック反映）

- push差分バグの調査中、ユーザーから「複数agentを使うときはagentごとに行になるように」との
  フィードバックを受けた。確認の結果、対応工数レポートの「サブエージェント」テーブルの表示単位を
  `agentType`合算（現状）から`agentId`単位（起動したagentごとに1行）へ変更する、という要望と判明。
  同じissue #34・同じplan（`plans/cheeky-sprouting-pine.md`）に含めて対応することで合意。
- 実データの`meta.json`（`.claude/session-logs/*/subagents/agent-*.meta.json`）を確認したところ、
  `agentType`に加えて`description`フィールド（Agent/Taskツール起動時の説明文）が存在することを
  確認した。行ラベルには`agentType`と`description`を使う設計にした。
- Plan modeへ再突入し、`dev-tools/src/archive-reentrant-plan.sh`で旧内容を
  `plans/cheeky-sprouting-pine_act1.md` / `worklog/20260816_cheeky-sprouting-pine_act1.md`へ退避した
  うえで、拡張版planをユーザーへ再提示・承認を得た
  （このスクリプトはworklogファイルを`mv`で退避する仕様のため、元のworklogパスは
  このタイミングで一度消滅し、本ファイルとして新規に書き直している）。
- さらにユーザーから「前回からの差分が0のagentについてはレポートに出力しない」との追加指示を受けた。
  agentId単位表示に伴い、差分が無いagent（トークン・ツール実行回数・稼働時間のいずれも0）は
  テーブル・稼働時間参考値等から除外する（該当agentのみで構成されるサブエージェントセクション自体も
  非表示にする）方針で実装に反映する。

## 実装（flow-id 11）

計画どおり以下を実装した:

1. `.claude/hooks/lib/UsageTracking.sh` の `_usage_merge_state` に `.agents` passthroughを追加
   （push差分バグの直接の修正）。
2. `_usage_merge_agent_state` を `subagentsByType`（agentType合算）から
   `subagents`（agentId単位、`agentType`・`description`付き）へスキーマ変更。
   `_usage_aggregate_and_merge_subagents` が `meta.json` の `.description // ""` を読み取って渡すよう変更。
3. `_usage_reset_since_last_push(state)` を切り出し、`post-push-usage-report.sh` の投稿成功後の
   リセット処理から呼ぶ形に変更（対象フィールドも`subagents`へ）。
4. `_usage_filter_nonzero_subagents(subagentsJson)` を追加し、差分0のagentをレポートから除外。
5. `post-push-usage-report.sh`のサブエージェントテーブルを「エージェント種別｜説明｜モデル｜...」の
   agentId単位1行表示に変更（表示順は`agentType`→`description`でソート）。
6. `tests/test_usage_tracking.sh` を新スキーマに合わせて更新し、`sync_usage_state`通しの回帰テスト
   （push#1→リセット→push#2は差分0→リセット→push#3は追記分のみ）を追加。既存25件＋新規14件、
   計39件が全passすることを確認。

## 実装中に判明した追加の不具合・修正

- **Windows版jqのCR混入バグ（新発見）**: このマシンのWindowsネイティブjq
  （`C:\Program Files\jq\jq.exe`, jq-1.6）は`jq -r`の出力の各行末に`\r`を付与する
  （`printf '%s' '{"a":1,"b":2}' | jq -r 'keys[]' | od -c`で確認）。
  `for x in $(... | jq -r ... | sort)`のようなループでは、コマンド置換が最後の行の末尾改行のみを
  取り除くため、要素が2件以上ある場合、最後の要素以外はループ変数に`\r`が付いたまま渡り、
  後続の`--arg`によるキー参照（`.[$id]`）が一致せずnullになることを実機再現で確認した
  （3要素のsubagentsで検証: 最後の1件だけ正常表示され、残り2件がjqエラーとともに欠落した）。
  1件しか無い場合は表面化しないため、既存の主トークンテーブルのモデルループでは潜在化していた
  （実運用のMRコメントでモデルが1種類のみだったため気づかれていなかった）。今回のagent単位表示化
  は必然的に複数行になるため顕在化した。対象の3ループ（主トークンテーブルのモデルループ、
  サブエージェントのagentIdループ、サブエージェント内モデルループ）に`| tr -d '\r'`を追加して対応。
  検証時、Bashツールのヒアドキュメント経由でテストスクリプトを作ると別の文字化け（バックスラッシュが
  消える現象）に遭遇し混同しかけたが、Writeツールでスクリプトファイルを作成して検証し直した結果、
  それはテスト手法側の問題（ヒアドキュメント転送の癖）であり実装（sedのpipeエスケープ）自体は
  正しいことを切り分けて確認した。
- **ツール実行回数の0件フィルタ**（ユーザーからの追加指示）: `_usage_merge_state`のtoolCalls集計は、
  過去に一度でも使われたツールであれば当該push分の差分が0でもキー自体を作ってしまう仕様のため、
  「過去に使ったが前回push以降は未使用のツール」が「XXXツール: 0」として表示され続けていた。
  トークンテーブルの0行除外と同じ考え方で、`tool_summary`／`subagent_tool_summary`の算出に
  `map(select(.value > 0))`を追加し、差分0のツールはキーごと非表示にした
  （状態ファイル側のスキーマ・集計ロジックは変更せず表示層のみで対応）。

## 次の一歩

- `bash -n`による構文チェック・`tests/test_usage_tracking.sh`の全pass確認は完了。
- commit・pushしてレビュー依頼（flow-id 12）。

---
