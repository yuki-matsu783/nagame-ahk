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

### 1. `.claude/hooks/lib/UsageTracking.sh` — 「稼働時間」の集計ロジック追加

**レビュー指摘（PR #29, yuki-matsu783）**: 計測したいのはClaude Codeが実際に作業している時間であり、
`AskUserQuestion`等で人間の回答を待っている間や、応答終了後に次の指示を待っている間のような
「作業していない時間」は含めたくない、との指摘を受けた。単純な「セッション開始〜最終メッセージ」の
経過時間ではこれらの待機時間をそのまま含んでしまうため、以下のように設計を変更する。

- 新しい定数 `IDLE_GAP_THRESHOLD_SECONDS`（既定300秒=5分）を追加する。連続するtranscript entry間の
  時間差（gap）がこの閾値を超える場合、「人間の入力待ち」とみなしてその区間を稼働時間に加算しない。
  閾値以下のgapは、ツール実行の待ち時間等の実作業とみなしてそのまま加算する。
  - `AskUserQuestion`の回答待ちや、応答終了〜次の人間指示までの待機は、通常5分を大きく超えるため
    この閾値判定で除外される。
  - 逆に、閾値以下の短い待機（人間がすぐ返信した場合等）は稼働時間に含まれてしまう、閾値を超える
    長時間のツール実行（大きめのビルド等）は稼働時間から漏れる、という2方向の誤差が生じうる。
    「目安」である旨をレポート・ドキュメントに明記する（既存のトークン集計と同じ扱い）。
- `_usage_aggregate_transcript`: 集計対象entry（`gitBranch`一致・assistant）を時系列順に走査しながら、
  直前entryとの`.timestamp`差（`fromdateiso8601`でepoch秒変換）を`IDLE_GAP_THRESHOLD_SECONDS`と比較し、
  閾値以下ならその区間分を`activeSeconds`（累計）に加算するreduceロジックを追加する
  （最初のentryには比較対象が無いため加算しない）。戻り値JSONに`activeSeconds`を追加する。
  - この`activeSeconds`は「セッション開始から現在までの累計稼働秒数」であり、`assistantCount`と
    同じ「0始まりの累計値」という性質を持つため、`_usage_merge_state`側は既存の`turns`と全く同じ
    差分計算パターン（`current - prevSession値`、前回スナップショット無しなら`current - 0`）を
    そのまま流用できる（`firstTimestamp`のような特別なベースライン計算は不要）。
- セッションごとの永続状態（`sessions[<sessionId>]`）に `lastActiveSeconds` を
  `lastTokens`/`lastTools`/`lastAssistantCount` と同様に保存する。
- `_usage_merge_state`: `sinceLastPush.activeSeconds` を新設し、`turns`と同じ差分パターンで加算する。
  `sinceLastPush`のリセット形にも `activeSeconds: 0` を追加する。

### 2. `.claude/hooks/post-push-usage-report.sh` — レポートへの表示

- `fmt_num` と同じ並びに `fmt_duration`（秒 → `H時間M分`/`M分` 形式）を追加する。
- コメント本文の箇条書き（`assistant応答回数`の行の近く）に
  `- 対応工数（目安・入力待ち時間を除く）: $(fmt_duration ...)` を追加する（ラベルに「待ち時間を
  除く」旨を明記し、レビュー指摘の意図がUI上でも分かるようにする）。
- 状態リセット時のJSON（`.sinceLastPush = {...}`）に `activeSeconds: 0` を追加する。

### 3. ドキュメント更新（受け入れ条件「ドキュメント類も修正する」）

`dev-tools/docs/spec/issue-mr-workflow.md` の「対応工数レポート」節に、稼働時間の算出方法
（`IDLE_GAP_THRESHOLD_SECONDS`によるgapベースの人間待ち時間除外、セッションまたぎ・複数回pushを
またいだ差分計算）と、既知の制約（上記の2方向の誤差）を追記する。制約は「未決定事項・懸念点」にも
追記する。

### 4. テスト追加

`tests/test_vcs_provider.sh` と同じ構成（`assert_equal`/`assert_true`、gh/glab呼び出し無し）で
`tests/test_usage_tracking.sh` を新設し、`UsageTracking.sh` の以下を検証する。
- `_usage_aggregate_transcript`: 合成JSONLフィクスチャに対する `activeSeconds` の算出
  （閾値以下のgapは加算・閾値超のgapは除外・`gitBranch`不一致entryの除外、の3パターン）
- `_usage_merge_state`: 初回push（セッション未記録）と2回目以降のpush、それぞれでの
  `activeSeconds` delta計算

`tests/README.md` の一覧表に新規テストの行を追加する。

## 対象外

- 5分（既定値）以下の短い待機を稼働時間から完全に除外すること（gap単位の閾値判定という設計上、
  短い待機は区別できない。既知の制約として文書化のみ）。
- 複数セッション（`/resume`等でtranscriptファイルが切り替わるケース）をまたいだ稼働時間の
  合算（既存の懸念点と同様、未対応のまま）。
- 出所不明差分に含まれるDDR本文自体の内容修正（ユーザー確認済みのため、そのまま活かす）。
- AHK本体（`src/`）の変更は無し（開発ツール側のみの対応）。

## 検証方法

- 変更した `.sh` は `bash -n <file>` で構文チェックする。
- `bash tests/test_usage_tracking.sh`（新規）と `bash tests/test_vcs_provider.sh`（既存の回帰確認）
  を実行し、`passed=N failures=0` を確認する。
- 本ブランチでの実際の `git push` によりPostToolUse hookが実際に動作するため、Draft PR #29への
  自動投稿コメントに「対応工数（目安・入力待ち時間を除く）」の行が表示されることを実地確認する
  （`.claude/hooks/post-push-usage-report.sh`の実行はgit push検知で自動発火するため、これが
  そのまま結合テストを兼ねる）。
