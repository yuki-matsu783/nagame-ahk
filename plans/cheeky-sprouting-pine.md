---
title: サブエージェント対応工数のpush差分バグ修正・表示のagent単位化
type: log
description: サブエージェント分の対応工数レポートがpush差分にならないバグの修正、および表示をagentType合算からagentId単位（1行/agent）へ変更する計画
tags: [usage-tracking, bugfix, hooks]
keywords: [サブエージェント, 対応工数, UsageTracking, sinceLastPush, agents, 差分, push, agentId, description]
---

# サブエージェント対応工数のpush差分バグ修正・表示のagent単位化（issue #34）

## Context

issue #34: 「対応工数レポートのサブエージェント分が前回pushからの差分になってなさそう」
（サブエージェントの対応工数がずっと同じ値のまま）。

`post-push-usage-report.sh`（PostToolUse, git push検知）は、push毎に
`.claude/hooks/lib/UsageTracking.sh` の `sync_usage_state` でtranscriptを集計し、
「前回このセッション／agentIdで記録した累計との差分」を `sinceLastPush` へ積算してMRへ投稿、
成功後に `sinceLastPush` をゼロリセットする設計（`dev-tools/docs/spec/issue-mr-workflow.md`
「サブエージェントの使用量記録」節）。メインセッション分は正しく差分になっているが、
サブエージェント分だけ常に同じ値が再送され続ける不具合が起きている。

加えて、調査中のユーザーフィードバックにより、サブエージェント分のレポート表示自体も
「複数agentを使うときはagentごとに行になるように」変更する（現状は`agentType`単位で
複数の`agentId`分を合算した1行にまとめてしまっており、どのagentがどれだけ使ったかが
見えない）。両方とも同じ`.claude/hooks/lib/UsageTracking.sh` / `post-push-usage-report.sh`が
対象のため、同じplan・同じブランチで一緒に対応する。

## 原因（push差分バグの調査結果）

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

### 2. 表示をagentType合算 → agentId単位（1行/agent）へ変更

現状 `_usage_merge_agent_state` は、agentId単位で計算した差分を
`sinceLastPush.subagentsByType[agentType]` へ**合算**して格納しており（同じagentTypeを
複数回起動すると1行にまとまる）、これが今回変更したい対象。以下のように、集計の単位を
「agentType」から「agentId（起動したagentごと）」へ変更する。

- **状態スキーマ変更**: `sinceLastPush.subagentsByType[agentType]` → `sinceLastPush.subagents[agentId]`
  （`agentType`・`description`をフィールドとして持たせる）。`.claude/usage-state/*.json` は
  gitignore対象の使い捨て状態ファイルのため、スキーマ変更に伴うマイグレーションは不要
  （既存の`subagentsByType`キーは単に無視され、次回pushからは新スキーマで蓄積される）。
- **`_usage_merge_agent_state` の変更**: `pseudo_existing.sinceLastPush` の参照元を
  `.sinceLastPush.subagentsByType[$agentType]` から `.sinceLastPush.subagents[$agentId]` に変更し、
  agentId単位でそのまま差分を積算する（agentType単位の合算ステップを廃止）。
  `description` 引数を追加し（呼び出し元の`_usage_aggregate_and_merge_subagents`が
  `meta.json`の`.description // ""`から取得して渡す。実データ確認済み: `meta.json`には
  `agentType`に加えて`description`フィールドが存在する）、
  `.agents[$agentId]`・`.sinceLastPush.subagents[$agentId]`の両方に`agentType`と`description`を
  付与して保存する（表示用ラベルとして使う）。
- **`post-push-usage-report.sh`のテーブル変更**: 「| エージェント種別 | モデル | ... |」を
  「| エージェント種別 | 説明 | モデル | Input | Output | Cache Write | Cache Read |」に変更し、
  `agentType`でまとめず`agentId`ごとに行を出す（表示順は`agentType`→`description`でソートし、
  同種のagentが固まって見えるようにする）。稼働時間参考値・ツール実行回数合計の集計ロジックは
  キー名を`subagents`に変えるだけで既存のまま流用できる（`[.[] | ...]`で全agent分を走査する
  実装のため、キーがagentTypeかagentIdかは影響しない）。
- **差分0のagentは表示しない**（追加のユーザー指示）: あるagentIdの
  `tokensByModel`全モデル・`toolCalls`・`activeSeconds`が全て0の場合、そのagentは
  テーブル行・稼働時間参考値・ツール実行回数合計のいずれからも除外する（トークンテーブル本体で
  既に行っている「4項目とも0のモデル行は表示しない」という既存の間引きと同じ考え方を、
  agent単位に適用する）。除外後に非ゼロのagentが1件も無ければ「### サブエージェント」
  セクション自体を出力しない。この判定は `UsageTracking.sh` に
  `_usage_filter_nonzero_subagents(subagentsJson)` として切り出し（bashスクリプト内の
  インラインjqではなく単体テスト可能な関数にする）、`post-push-usage-report.sh`
  はこの関数の出力に対してテーブル描画・集計を行う。

### 3. リセット処理の共通化（テスト容易性・重複排除）

`post-push-usage-report.sh` の投稿成功後のリセット処理（`sinceLastPush` をゼロ初期化する
jqフィルタ）は現在スクリプト内にインラインで書かれており、`tests/test_usage_tracking.sh`
から直接検証できない。`UsageTracking.sh` に `_usage_reset_since_last_push(state)` 関数として
切り出し、`post-push-usage-report.sh` からはこれを呼ぶ形にする（リセット対象フィールドは
`subagentsByType` → `subagents` に変わる以外、内容は変更しない）。これにより、テストが実運用と
全く同じリセットロジックを使って「2回目push」を再現できる。

### 4. `tests/test_usage_tracking.sh` の更新・追加

- 既存の `_usage_merge_agent_state` 関連テスト（`subagentsByType`での合算を検証している箇所）を
  新スキーマに合わせて書き換える。「異なるagentIdは合算される」ではなく
  **「異なるagentIdはそれぞれ個別のentryとして保持され、合算されない」**ことを検証する内容に変更する。
  `description`が正しく保存されることも検証する。
- `sync_usage_state` を使った統合的な回帰テストを追加する（既存の単体テストは個別関数のみを
  対象にしており、push差分バグはメイン集計とサブエージェント集計の受け渡し部分でのみ発生するため、
  `sync_usage_state` を通しで呼ぶテストでないと検知できない）:
  1. push #1: メインtranscript + サブエージェントtranscript（1エントリ、`description`付き）を
     用意し `sync_usage_state` を呼ぶ → `sinceLastPush.subagents[agentId]` に値が付く。
  2. `_usage_reset_since_last_push` でリセット（実際のpost-push-usage-report.shと同じ操作）。
  3. push #2: サブエージェントtranscriptを変更せず再度 `sync_usage_state` を呼ぶ →
     `sinceLastPush.subagents[agentId]` の各値が **0** であることを検証（このアサーションが
     今回のpush差分バグに対する回帰テスト）。
  4. push #3: サブエージェントtranscriptへ新しいエントリを追記してから再度呼ぶ →
     差分のみ（追記分だけ）が計上されること、累積値になっていないことを検証。
- `_usage_filter_nonzero_subagents` の単体テストを追加する: 差分ありのagentと
  差分0（tokensByModel全モデル・toolCalls・activeSeconds全て0）のagentが混在する入力を渡し、
  差分0のagentのみが除外されることを検証する。

### 5. 実装中に判明した追加修正

- **Windows版jqのCR混入バグ**: このマシンのWindowsネイティブjq（`C:\Program Files\jq\jq.exe`）は
  `jq -r`の出力の各行末に`\r`を付与する。`for x in $(... | jq -r ... | sort)`のようなループでは、
  コマンド置換が最後の行の末尾改行のみを取り除くため、要素が2件以上ある場合、最後の要素以外は
  ループ変数に`\r`が付いたまま渡り、後続の`--arg`によるキー参照（`.[$id]`等）が一致せずnullになる
  （agentId・modelいずれのループでも発生。1件しか無い場合は表面化しないため、既存の主トークン
  テーブルのモデルループでは潜在化していた）。今回のagent単位表示化は必然的に複数agentId・
  複数行になるため顕在化する。対象となる3箇所のループ（主トークンテーブルのモデルループ、
  サブエージェントのagentIdループ、サブエージェント内モデルループ）に`| tr -d '\r'`を追加して対応する。
- **ツール実行回数の0件フィルタ**（追加のユーザー指示）: `_usage_merge_state`のtoolCalls集計は、
  過去に一度でも使われたツールであれば、当該push分の差分が0でもキー自体を作ってしまう仕様
  （`$current.tools`＝transcript全体で使われた全ツールをreduceの対象にしているため）。
  トークンテーブルの0行除外と同じ考え方で、`tool_summary`／`subagent_tool_summary`の表示直前に
  `map(select(.value > 0))`を追加し、差分0のツールはキーごと表示しないようにする
  （状態ファイル側のスキーマ・集計ロジックは変更せず、表示層でのフィルタに留める）。

## 対象外

- `_usage_aggregate_transcript`自体のロジック変更（既に正しいことを確認済み）。
- メインセッション分の集計ロジック（既に正しくpush差分になっている）。
- ネストしたサブエージェント（depth 2以降）対応（既存スコープ外のまま）。
- `docs/spec` `docs/ddr` への反映（flow-id 16の設計反映タイミングで実施する。
  「サブエージェントの使用量記録」節の「スナップショット単位（agentId）と表示集約単位（agentType）の
  二段設計」の記述は、今回の変更でagentType単位の合算を廃止するため反映が必要になる）。

## 検証方法

- `bash -n .claude/hooks/lib/UsageTracking.sh` / `bash -n .claude/hooks/post-push-usage-report.sh`
  で構文チェック。
- `bash tests/test_usage_tracking.sh` を実行し、更新後の全テストがpassすることを確認する
  （push差分の回帰テスト・agent単位表示の変更点の両方を含む）。
