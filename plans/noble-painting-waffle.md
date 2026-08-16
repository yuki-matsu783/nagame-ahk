---
title: issue #28 対応工数レポートの修正（時間記録の追加）
type: guide
description: 対応工数レポートの日本語修正（済）に加え、かかった時間を記録・表示できるようにする実装計画
tags: [usage-report, issue-28, plan]
keywords: [対応工数, 経過時間, transcript, timestamp, usage-tracking, post-push-hook]
---

# Plan: issue #28 対応工数レポートを修正

## Context

issue #28 は「セッション使用量レポート」の日本語がおかしい点と、かかった時間が記録されない点の
2つを指摘している。ブランチ作成直後の作業ツリーに、出所不明だが issue #28 の意図と一致する
未コミット差分（7ファイル、「セッション使用量レポート」→「対応工数レポート」への文言統一）が
既に存在していた。ユーザーに確認の上、この差分をベースに作業を進めることで合意した
（マージ済みDDR `docs/ddr/0006-...md` 自体のタイトル/本文を書き換えている点も、過去に承認済みの
対応として問題ないとユーザーが確認済み）。

残る作業は、受け入れ条件のうち「かかった時間も記載される」の実装と、それに伴うドキュメント・
テストの追加。

## 実施内容

### 1. `.claude/hooks/lib/UsageTracking.sh` — 経過時間の集計ロジック追加

- `_usage_aggregate_transcript`: 集計対象entry（`gitBranch`一致・assistant）の `.timestamp`
  （ISO8601）から `firstTimestamp` / `lastTimestamp`（`fromdateiso8601` でepoch秒に変換した
  min/max）を算出し、戻り値JSONに追加する。
- セッションごとの永続状態（`sessions[<sessionId>]`）に `lastTimestamp` を
  `lastTokens`/`lastTools`/`lastAssistantCount` と同様に保存する。
- `_usage_merge_state`: `sinceLastPush.elapsedSeconds` を新設し、以下のロジックで加算する
  （`turns`のdelta計算と同じ「累計スナップショットとの差分」パターンを踏襲）。
  - 同一セッションで前回スナップショットがある場合: `delta = max(0, current.lastTimestamp - prevSession.lastTimestamp)`
  - このセッションで初めての場合（`lastAssistantCount`と違い、時刻は0を基準にできないため個別対応）:
    `delta = max(0, current.lastTimestamp - current.firstTimestamp)`（セッション開始からこのpushまでの時間）
  - `sinceLastPush`のリセット形にも `elapsedSeconds: 0` を追加する。

### 2. `.claude/hooks/post-push-usage-report.sh` — レポートへの表示

- `fmt_num` と同じ並びに `fmt_duration`（秒 → `H時間M分`/`M分` 形式）を追加する。
- コメント本文の箇条書き（`assistant応答回数`の行の近く）に
  `- 対応工数（目安）: $(fmt_duration ...)` を追加する。
- 状態リセット時のJSON（`.sinceLastPush = {...}`）に `elapsedSeconds: 0` を追加する。

### 3. ドキュメント更新（受け入れ条件「ドキュメント類も修正する」）

`dev-tools/docs/spec/issue-mr-workflow.md` の「対応工数レポート」節に、経過時間の算出方法
（transcriptのtimestampベース、セッションまたぎ・複数回pushをまたいだ差分計算）と、既知の制約
（離席等のアイドル時間も経過時間に含まれてしまう。除外は未対応）を追記する。制約は
「未決定事項・懸念点」にも1行追記する。

### 4. テスト追加

`tests/test_vcs_provider.sh` と同じ構成（`assert_equal`/`assert_true`、gh/glab呼び出し無し）で
`tests/test_usage_tracking.sh` を新設し、`UsageTracking.sh` の以下を検証する。
- `_usage_aggregate_transcript`: 合成JSONLフィクスチャに対する `firstTimestamp`/`lastTimestamp`
  の抽出、`gitBranch`不一致entryの除外
- `_usage_merge_state`: 初回push（セッション未記録）と2回目以降のpush、それぞれでの
  `elapsedSeconds` delta計算

`tests/README.md` の一覧表に新規テストの行を追加する。

## 対象外

- アイドル時間（離席等）を経過時間から除外するロジック（既知の制約として文書化のみ）。
- 複数セッション（`/resume`等でtranscriptファイルが切り替わるケース）をまたいだ経過時間の
  合算（既存の懸念点と同様、未対応のまま）。
- 出所不明差分に含まれるDDR本文自体の内容修正（ユーザー確認済みのため、そのまま活かす）。
- AHK本体（`src/`）の変更は無し（開発ツール側のみの対応）。

## 検証方法

- 変更した `.sh` は `bash -n <file>` で構文チェックする。
- `bash tests/test_usage_tracking.sh`（新規）と `bash tests/test_vcs_provider.sh`（既存の回帰確認）
  を実行し、`passed=N failures=0` を確認する。
- 本ブランチでの実際の `git push` によりPostToolUse hookが実際に動作するため、Draft PR #29への
  自動投稿コメントに「対応工数（目安）」の行が表示されることを実地確認する
  （`.claude/hooks/post-push-usage-report.sh`の実行はgit push検知で自動発火するため、これが
  そのまま結合テストを兼ねる）。
