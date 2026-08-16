---
title: worklog サブエージェント対応工数push差分バグ修正
type: log
description: issue #34 サブエージェント分の対応工数レポートがpush差分にならないバグの調査・修正worklog
tags: [worklog, usage-tracking, bugfix]
keywords: [サブエージェント, 対応工数, UsageTracking, sinceLastPush, agents, push差分]
---

# worklog: cheeky-sprouting-pine

対象: issue #34 サブエージェント対応工数のpush差分バグ修正（2026-08-16）。
plan: `plans/cheeky-sprouting-pine.md`

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

## 次の一歩

- 承認されたplan（`plans/cheeky-sprouting-pine.md`）に沿って実装:
  1. `.claude/hooks/lib/UsageTracking.sh` の `_usage_merge_state` に `.agents` passthroughを追加。
  2. リセット処理を `_usage_reset_since_last_push` として切り出し、
     `post-push-usage-report.sh` から呼ぶ形に変更。
  3. `tests/test_usage_tracking.sh` へ `sync_usage_state` 通しの回帰テストを追加。
- commit・pushしてレビュー依頼（flow-id 6）。

---
