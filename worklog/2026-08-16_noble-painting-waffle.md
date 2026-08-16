---
title: worklog — サブエージェント集計＋session-logsローカルコピー方式
type: log
description: PR #29レビュー指摘（サブエージェント使用量記録、session-logsコピー方式）対応の作業ログ
tags: [usage-report, issue-28, subagent, worklog]
keywords: [サブエージェント, session-logs, transcript, agentId, agentType]
---

# worklog: サブエージェント集計＋session-logsローカルコピー方式

## 経緯

issue #28（対応工数レポート）は一度flow-id 21まで完了しDraft解除・PR #29をready化していたが、
その後2件のレビューコメントが追加された。

1. `<synthetic>`等、全項目0のモデル行がノイズとして表示される（対応済み、commit `ee31174`）。
2. ツール実行回数が一部のツール種別しか出ない理由についての質問
   （バグではなく仕様。ドキュメント反映で対応済み、commit `6c4914a`）。
3. サブエージェントのトークン・ツール使用量も別行で出力してほしい／集計対象を
   `~/.claude/projects`から直接読むのではなく、リポジトリ内へコピーしてから処理する方式に
   変えたほうがよい、という指摘（本worklogの対象）。

3番目の指摘はissue #28の受け入れ条件を超える規模のため、新issueへ分離するか確認したところ、
ユーザーの判断で「PR #29内でこのまま対応する」ことになった。

## 実機調査で判明した事実

- `~/.claude/projects/<projectDirHash>/<sessionId>/subagents/agent-<agentId>.jsonl`（＋同名
  `.meta.json`。`agentType`等を含む）に、メインtranscriptと同一スキーマ
  （`type`, `gitBranch`, `message.usage`, `message.content[].type=="tool_use"`, `timestamp`）で
  サブエージェントの活動が記録されている。
- `spawnDepth`フィールドがあるが、このプロジェクトの実データでは`1`のみ観測。ネスト
  （`agent-X/subagents/`のような構造）は未観測・スキーマ未確認のため対象外とした。

## Plan

`plans/noble-painting-waffle.md` 参照（Planエージェントでの設計検証を経て承認済み）。要点:

- 集計対象を`git push`時に`.claude/session-logs/<safeBranch>/<sessionId>/`へコピーしてから処理する
  （既存の全件再パース＋スナップショット差分方式は維持し、集計対象パスだけ差し替える）。
- サブエージェントの累計スナップショットは`agentId`単位（二重計上防止）、レポート表示は`agentType`
  単位で合算。
- レポートには既存テーブルへの行追加ではなく独立した「### サブエージェント」セクションを追加。
- 稼働時間はメインの「対応工数」行には合算せず、参考値として別行に表示（重複計上の可能性がある
  ため）。

## 実装ログ

- `.claude/hooks/lib/UsageTracking.sh`: `_usage_safe_branch_name`（3箇所目の重複を関数化）、
  `_usage_sync_session_logs`（メイン・サブエージェントtranscriptを`.claude/session-logs/`へ
  コピー）、`_usage_merge_agent_state`（`_usage_merge_state`を「疑似existing」でラップして再利用、
  `agentId`単位のスナップショット・`agentType`単位の表示集約）、
  `_usage_aggregate_and_merge_subagents`（コピー済みディレクトリの走査→集計→マージ）を実装。
  `_usage_aggregate_transcript`/`_usage_merge_state`本体は無改造。
- `.claude/hooks/post-push-usage-report.sh`: 投稿要否判定の`total`にサブエージェント分を含める、
  「### サブエージェント」セクション（`agentType`×モデルのテーブル・ツール実行回数合計・
  稼働時間参考値。全項目0行は既存ロジックと同様に除外）を追加、リセットJSONへ
  `subagentsByType: {}`追加、`safe_branch`計算を`_usage_safe_branch_name`へ統一。
- `.gitignore`: `/.claude/session-logs/`を追加。
- `tests/test_usage_tracking.sh`: 13アサーション追加（合計25、全合格）。`agentId`単位の差分・
  `agentType`単位の合算・二重計上防止・疑似`~/.claude/projects`ツリーからのコピー・
  エンドツーエンド集計を検証。
- 手動検証: レポート整形ロジック（サブエージェントセクション・`<synthetic>`ゼロ行除外・
  投稿要否判定のtotal計算）をjqで単体検証、期待通りの出力を確認。
- `bash -n`全ファイル通過、`test_usage_tracking.sh`（25/25）・`test_vcs_provider.sh`（10/10）
  全合格。
- ドキュメント反映: `dev-tools/docs/spec/issue-mr-workflow.md`（記録範囲・新規サブセクション
  「サブエージェントの使用量記録」・コンポーネント説明・影響範囲・未決定事項）、
  DDR 0006への追記（session-logsコピー方式・二段設計・ネスト対象外の理由）、
  `tests/README.md`の対象欄更新。
