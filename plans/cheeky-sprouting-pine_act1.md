---
title: サブエージェント対応工数のpush差分バグ修正
type: log
description: サブエージェント分の対応工数レポートが前回pushからの差分にならず毎回同じ値を再送してしまうバグの原因調査と修正計画
tags: [usage-tracking, bugfix, hooks]
keywords: [サブエージェント, 対応工数, UsageTracking, sinceLastPush, agents, 差分, push]
---

# サブエージェント対応工数のpush差分バグ修正（issue #34）

## Context

issue #34: 「対応工数レポートのサブエージェント分が前回pushからの差分になってなさそう」
（サブエージェントの対応工数がずっと同じ値のまま）。

`post-push-usage-report.sh`（PostToolUse, git push検知）は、push毎に
`.claude/hooks/lib/UsageTracking.sh` の `sync_usage_state` でtranscriptを集計し、
「前回このセッション／agentIdで記録した累計との差分」を `sinceLastPush` へ積算してMRへ投稿、
成功後に `sinceLastPush` をゼロリセットする設計（`dev-tools/docs/spec/issue-mr-workflow.md`
「サブエージェントの使用量記録」節）。メインセッション分は正しく差分になっているが、
サブエージェント分だけ常に同じ値が再送され続ける不具合が起きている。

## 原因（調査結果）

`_usage_merge_state`（`.claude/hooks/lib/UsageTracking.sh`）の戻り値オブジェクトが
`{branch, sessions, sinceLastPush} + (lastPostedAtのpassthrough)` のみを組み立てており、
**入力の `$existing.agents`（agentId単位の累計スナップショット）を出力へ引き継いでいない**。

`sync_usage_state` は以下の順で呼ばれる:
1. `new_state = _usage_merge_state($existing, ...)` ← ここで `$existing.agents` が消える
2. `new_state = _usage_aggregate_and_merge_subagents(new_state, ...)`
   ← `new_state.agents[$agentId]` を前回スナップショットとして参照するが、
   ステップ1で既に空になっているため常に「初回」扱いになり、
   **サブエージェントtranscriptに新しい追記が無くても毎回transcript全体の値を差分として計上**する。

再現・検証: `_usage_merge_state`にサブエージェント2回push相当のシナリオ（transcript不変のpush→
transcript追記ありのpush）を通した結果、修正前は2回目pushでも1回目と同じ値
（tokens 1/1, activeSeconds 30）が再送され、3回目pushでは本来の差分（+5/+5, +30s）ではなく
累積値（6/6, 60s）になることを確認した。修正案（後述）適用後は2回目pushで0、3回目pushで
正しい差分のみになることを確認済み。

`_usage_merge_agent_state` 側（agentId単位の差分計算そのもの）・`_usage_aggregate_and_merge_subagents`
（複数agentIdの畳み込み）のロジック自体は正しく、既存の単体テスト（`tests/test_usage_tracking.sh`）
もこれらを個別には正しく検証できている。今回のバグは「メインセッションのマージ結果に`.agents`が
含まれない」という、関数間の受け渡し部分にのみ存在する。

## 修正方針

### 1. `.claude/hooks/lib/UsageTracking.sh`: `_usage_merge_state` に `.agents` のpassthroughを追加

既存の `lastPostedAt` passthrough と同じパターンで、`$existing.agents` が存在すれば出力へ含める。

```jq
| {branch: $branch, sessions: $newSessions, sinceLastPush: $newSince}
  + (if $existing.lastPostedAt then {lastPostedAt: $existing.lastPostedAt} else {} end)
  + (if $existing.agents then {agents: $existing.agents} else {} end)
```

`_usage_merge_agent_state` が内部で `_usage_merge_state` を呼ぶ際に渡す `pseudo_existing` は
`agents` キーを持たない構造のため、この変更はagentId単位の計算には影響しない
（同一関数の別呼び出し元同士で干渉しないことを確認済み）。

### 2. リセット処理の共通化（テスト容易性・重複排除）

`post-push-usage-report.sh` の投稿成功後のリセット処理（`sinceLastPush` をゼロ初期化する
jqフィルタ）は現在スクリプト内にインラインで書かれており、`tests/test_usage_tracking.sh`
から直接検証できない。`UsageTracking.sh` に `_usage_reset_since_last_push(state)` 関数として
切り出し、`post-push-usage-report.sh` からはこれを呼ぶ形にする（既存の
`{tokensByModel: {}, toolCalls: {}, turns: 0, activeSeconds: 0, subagentsByType: {}}` という
リセット内容自体は変更しない）。これにより、テストが実運用と全く同じリセットロジックを使って
「2回目push」を再現できる。

### 3. `tests/test_usage_tracking.sh` に回帰テストを追加

`sync_usage_state` を使った統合的なシナリオを追加する（既存の単体テストは個別関数のみを
対象にしており、この不具合はメイン集計とサブエージェント集計の受け渡し部分でのみ発生するため、
`sync_usage_state` を通しで呼ぶテストでないと検知できない）:

1. push #1: メインtranscript + サブエージェントtranscript（1エントリ）を用意し
   `sync_usage_state` を呼ぶ → `sinceLastPush.subagentsByType.<type>` に値が付く。
2. `_usage_reset_since_last_push` でリセット（実際のpost-push-usage-report.shと同じ操作）。
3. push #2: サブエージェントtranscriptを変更せず再度 `sync_usage_state` を呼ぶ →
   `sinceLastPush.subagentsByType` が **0** であることを検証（このアサーションが今回の
   バグに対する回帰テスト）。
4. push #3: サブエージェントtranscriptへ新しいエントリを追記してから再度呼ぶ →
   差分のみ（追記分だけ）が計上されること、累積値になっていないことを検証。

## 対象外

- `_usage_merge_agent_state` / `_usage_aggregate_and_merge_subagents` / `_usage_aggregate_transcript`
  自体のロジック変更（既に正しいことを確認済み）。
- メインセッション分の集計ロジック（既に正しくpush差分になっている）。
- `docs/spec` `docs/ddr` への反映（flow-id 16の設計反映タイミングで実施する。今回はバグ修正であり
  設計自体の変更ではないため、既存の `dev-tools/docs/spec/issue-mr-workflow.md`
  「サブエージェントの使用量記録」節の記述と齟齬はない）。

## 検証方法

- `bash -n .claude/hooks/lib/UsageTracking.sh` / `bash -n .claude/hooks/post-push-usage-report.sh`
  で構文チェック。
- `bash tests/test_usage_tracking.sh` を実行し、既存テスト（25件）が全てpassすることに加え、
  新規追加する回帰テストもpassすることを確認する。
