---
title: issue #28 対応工数レポート — サブエージェント集計＋session-logsローカルコピー方式
type: guide
description: PR #29レビュー指摘対応。サブエージェントのトークン・ツール使用量を別行で記録し、集計対象を~/.claude/projectsからリポジトリ内ローカルコピーへ変更する実装計画
tags: [usage-report, issue-28, subagent, plan]
keywords: [サブエージェント, session-logs, transcript, agentId, agentType, tokensByModel, gitignore]
---

# Plan: 対応工数レポートへのサブエージェント集計＋session-logsローカルコピー方式の追加

## Context

PR #29（issue #28対応工数レポート機能）へのレビューで、以下2点の指摘を受けた。

1. サブエージェント（Task/Agentツール等で起動される別セッション）のトークン・ツール使用量が
   現状のレポートに一切反映されていない。実機調査の結果、
   `~/.claude/projects/<projectDirHash>/<sessionId>/subagents/agent-<agentId>.jsonl`
   （＋同名`.meta.json`。`agentType`等を含む）にメインtranscriptと同一スキーマで記録されており、
   集計に取り込めることを確認した。
2. 集計対象を毎回`~/.claude/projects`配下の外部パスから直接読むのではなく、`git push`検知時に
   まずリポジトリ内のgitignore対象ディレクトリへコピーしてから、そのローカルコピーを元に処理する
   方式へ変更してほしい。

人間には既にスコープ確認済みで、issue #28を分割せず**PR #29内でこのまま対応する**方針で合意している
（本来は新issueへ分離すべき規模だが、レビューループを継続する形で進める）。

## 実施内容

### 1. `.claude/hooks/lib/UsageTracking.sh`

- `_usage_safe_branch_name(branch)`: 既存の`sed -E 's/[^a-zA-Z0-9_-]/_/g'`をヘルパー関数として切り出す
  （現状`sync_usage_state`内と`post-push-usage-report.sh`内の2箇所に重複しており、今回3箇所目の
  利用が発生するため関数化する）。
- `_usage_sync_session_logs(repo_root, branch, session_id, transcript_path)`（新規）: 集計対象を
  リポジトリ内へコピーする。
  - コピー先: `.claude/session-logs/<safeBranch>/<sessionId>/main.jsonl`
    （＋サブエージェントがあれば`subagents/agent-<agentId>.jsonl`と`.meta.json`）。
  - メインtranscriptのコピー失敗はそのまま呼び出し元へエラー伝播（`[ -f "$transcript_path" ]`と
    同格の致命条件）。サブエージェント個別ファイルのコピー失敗は`|| true`で握りつぶし他へ波及させない
    （次回pushの全件再パースで自然に回収される）。
  - サブエージェントの発見: `${transcript_path%.jsonl}/subagents/agent-*.jsonl` を列挙する。
    **ネスト（サブエージェントがさらに起動するサブエージェント、depth 2以降）は対象外**とする
    （実データで未観測かつスキーマ未確認のため。既存の「複数セッション同時進行の重複除去は
    対象外」と同種の判断）。
  - stdoutへコピー先ディレクトリパスを返す。
- `_usage_merge_agent_state(existing, agent_id, agent_type, current, branch)`（新規）: 1つの
  サブエージェント（`agentId`単位）について、既存の`_usage_merge_state`と全く同じ
  「current - prevSnapshot（下限0）」ロジックを適用する。具体的には`existing.agents[agent_id]`を
  `_usage_merge_state`が期待する`sessions[sessionId]`相当の疑似オブジェクトとして渡し、
  戻り値を`existing.agents[agent_id]`（`agentType`付き）と`existing.sinceLastPush.subagentsByType[agent_type]`
  （加算）へ書き戻す。**`_usage_aggregate_transcript`・`_usage_merge_state`本体は無改造**（サブエージェント
  側から再利用するのみ）。
  - スナップショット単位は`agentId`（二重計上・過小計上防止。長時間実行中のバックグラウンドサブ
    エージェントが複数pushをまたいで追記され続けても、既存の単調性保証がそのまま効く）。
  - 表示集約単位は`agentType`（同じ`agentType`の複数`agentId`分の差分を`subagentsByType`へ合算）。
- `_usage_aggregate_and_merge_subagents(existing, log_dir, branch)`（新規）: `${log_dir}/subagents/agent-*.jsonl`
  を列挙し、各ファイルについて隣接する`.meta.json`の`.agentType // "unknown"`を読み取り、
  `_usage_aggregate_transcript`（無改造）で集計→`_usage_merge_agent_state`で畳み込む、を繰り返す。
- `sync_usage_state`: `_usage_sync_session_logs`でコピーしてから、集計対象パスを
  `${log_dir}/main.jsonl`（コピー先）に差し替える。`_usage_merge_state`実行後に
  `_usage_aggregate_and_merge_subagents`を呼んでから状態ファイルへ保存する。
  - **既存の全件再パース＋スナップショット差分方式は維持し、行オフセットベースの差分パースへは
    踏み込まない**（`activeSeconds`のgapベースtail buffer計算・単調性保証が「毎回全件を時系列で
    走査し直す」ことを前提にしており、オフセット方式にすると前回の`prevTimestamp`等を新たに
    永続化する必要が生じ、既に検証済みの単調性証明が崩れるリスクが大きいため）。低頻度
    （`git push`時のみ）処理であり、1セッション分のtranscriptサイズなら全件再パースの性能コストは
    許容範囲と判断する。

### 2. `.claude/hooks/post-push-usage-report.sh`

- `state.sinceLastPush.subagentsByType`を取得し、投稿要否判定の`total`計算にサブエージェント分の
  トークン合計も含める（メイン自身の消費がほぼ0でも、サブエージェント作業だけのpushでレポートが
  握りつぶされないようにするため）。
- サブエージェント分が1件以上あれば、既存の「モデル別トークンテーブル＋ツール実行回数」の直後に
  新規セクション「### サブエージェント」を追加する（既存テーブルへの行追加ではなく独立セクション。
  主体が異なる数値を同じテーブルに混在させると「誰の消費か」が曖昧になるため）。
  - 「メインセッションの数値には含まれません。ネストしたサブエージェントは対象外」という注記。
  - `agentType`×`model`のテーブル（既存の全項目0行除外ロジックをそのまま適用）。
  - サブエージェント合計のツール実行回数（1行）。
  - サブエージェントの稼働時間（`activeSeconds`）は**メインの「対応工数」行には合算せず**、
    参考値として別行に表示する（Taskツール待ち区間とサブエージェント内稼働区間が重複しうるため、
    単純合算するとwall clock時間より過大になりうる。既知の制約としてドキュメントに明記）。
- 状態リセット時のJSON（`.sinceLastPush = {...}`）に`subagentsByType: {}`を追加。

### 3. `.gitignore`

`/.claude/usage-state/`の直後に追記:
```
# 対応工数レポート機能のサブエージェント集計用ローカルコピー（ブランチ横断・非コミット対象）
/.claude/session-logs/
```

### 4. テスト（`tests/test_usage_tracking.sh`）

既存パターン（`mk_entry`ヘルパー、`assert_equal`/`assert_true`、`$TMPDIR`完結）に沿って追加する。
コピー処理のテストも対象パスを全て`$TMPDIR`配下に自作した疑似`~/.claude/projects`ツリーとし、
実ホームディレクトリには一切触れない。

- `_usage_merge_agent_state`: 単一`agentId`の初回・2回目以降の差分、異なる`agentId`・同一`agentType`
  が正しく`subagentsByType`へ合算されることを検証。
- `_usage_aggregate_transcript`: `agentId`/`isSidechain`等の余分なフィールドを持つエントリを流し込んでも
  既存の集計結果に影響しないことを確認する回帰テスト。
- `_usage_sync_session_logs`: 疑似ツリーからのコピー後、期待通りのディレクトリレイアウトになることを検証。
- `_usage_aggregate_and_merge_subagents`: コピー済みディレクトリ構造から集計→マージまでの
  エンドツーエンドテスト。

`tests/README.md`の該当行の「対象」列に上記を追記する。

### 5. ドキュメント反映

- `dev-tools/docs/spec/issue-mr-workflow.md`:
  - 「記録範囲」節の「サブエージェント...詳細往復は対象外」の記述を「直接の子（depth 1）
    サブエージェントの使用量は別集計として反映する。ネストしたサブエージェント（depth 2以降）は
    対象外」に修正。
  - 新規サブセクション「サブエージェントの使用量記録」を「稼働時間の算出方法」の後に追加し、
    発見方法・コピー方式・`agentId`/`agentType`の二段設計・稼働時間を別集計にする理由を記載。
  - 「コンポーネント」の`UsageTracking.sh`説明に新規関数を追記。
  - 「影響範囲」に本ラウンドの変更ファイル一覧を追記。
  - 「未決定事項・懸念点」に「ネストしたサブエージェント（depth 2以降）は未対応・未検証」
    「サブエージェントの`activeSeconds`はメインと別集計であり重複除去はしていない」を追記。
- `dev-tools/docs/ddr/0006-対応工数レポートはtranscript自前パースで実装する.md`（マージ済み、
  既存内容は変更せず追記のみ）: 末尾に「## 追記（PR #29レビュー指摘: サブエージェント使用量と
  session-logsコピー方式）」を追加し、コピー方式を採用した理由・全件再パース方式を維持した理由・
  `agentId`/`agentType`二段設計の理由・depth 2以降を対象外とした理由を記載する。

## 対象外

- ネストしたサブエージェント（depth 2以降）の集計（実データ未観測・スキーマ未確認のため）。
- 行オフセットベースの差分パース（性能改善目的の設計変更。`activeSeconds`単調性証明との整合リスクが
  大きいため見送り、将来問題が顕在化した場合に別issueで検討）。
- サブエージェントの`activeSeconds`とメインの`activeSeconds`の重複除去（Taskツール待ち区間との
  overlap dedup）。
- `.claude/session-logs/`配下の古いセッション分のプルーニング・削除（既存の`.claude/usage-state/`の
  `sessions{}`が無制限蓄積するのと同じ扱いとし、今回は対応しない）。
- `tool-results/`ディレクトリ（サブエージェントのツール実行結果キャッシュ）の取り込み。

## 検証方法

- 変更した`.sh`は`bash -n <file>`で構文チェックする。
- `bash tests/test_usage_tracking.sh`（新規テスト含む）と`bash tests/test_vcs_provider.sh`
  （既存の回帰確認）を実行し、`passed=N failures=0`を確認する。
- 本ブランチでの実際の`git push`によりPostToolUse hookが動作するため、Draft PR #29への自動投稿
  コメントで、サブエージェント（`issue-mr-resume`等）を起動した後のpushで「### サブエージェント」
  セクションが表示されることを実地確認する。
