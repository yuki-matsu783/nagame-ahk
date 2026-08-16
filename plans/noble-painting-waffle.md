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

### 参考実装調査（flow-id 11着手時点で追加）

実装着手にあたり、同種の課題（Claude Codeのtranscriptから実働時間を算出する）を扱う参考実装
（ユーザーがローカルにcloneした`参考ディレクトリ/claude-work-timer`（TypeScript）、
`参考ディレクトリ/claude-code-time-tracking`（Python）の2件）を調査した。

- 両実装とも「gapベースのidle検出（既定5分閾値。gapが閾値を超えたら人間の入力待ちとみなし
  除外）」を採用しており、本Planのレビュー反映後の設計（`IDLE_GAP_THRESHOLD_SECONDS`）の妥当性を
  裏付ける先行事例として参照した。
- 一方、`claude-work-timer`は各作業区間（セグメント）の末尾に固定の **tail buffer**
  （既定30秒。応答を読む・軽微な追加操作等、次のgapとしては現れない実作業時間を補うためのもの。
  1イベントのみのセッションでもtail buffer分は稼働時間として計上される）を加算する設計を持って
  おり、本Plan（レビュー反映版）には無かった要素だったため取り入れる（下記「1.」参照）。
  `claude-code-time-tracking`も同種の10分バッファを持つ（値は異なるが考え方は同じ）。
- 両実装とも、複数セッション・複数プロジェクトが同時進行した場合の区間重複除去（overlap dedup）を
  持つが、本issueのスコープ外として見送る（詳細は「対象外」参照）。

## 実施内容

### 1. `.claude/hooks/lib/UsageTracking.sh` — 「稼働時間」の集計ロジック追加

**レビュー指摘（PR #29, yuki-matsu783）**: 計測したいのはClaude Codeが実際に作業している時間であり、
`AskUserQuestion`等で人間の回答を待っている間や、応答終了後に次の指示を待っている間のような
「作業していない時間」は含めたくない、との指摘を受けた。単純な「セッション開始〜最終メッセージ」の
経過時間ではこれらの待機時間をそのまま含んでしまうため、以下のように設計を変更する
（参考実装調査を踏まえ、tail bufferを追加する形にさらに更新）。

- 新しい定数 `IDLE_GAP_THRESHOLD_SECONDS`（既定300秒=5分）を追加する。連続するtranscript entry間の
  時間差（gap）がこの閾値**以上**の場合、「人間の入力待ち」とみなしてその区間自体は稼働時間に
  加算しない（閾値ちょうどは「待ち」側として扱う。参考実装`claude-work-timer`の境界仕様
  `handles exact threshold as idle`に合わせた）。閾値未満のgapは、ツール実行の待ち時間等の実作業と
  みなしてそのまま加算する。
  - `AskUserQuestion`の回答待ちや、応答終了〜次の人間指示までの待機は、通常5分を大きく超えるため
    この閾値判定で除外される。
- 新しい定数 `TAIL_BUFFER_SECONDS`（既定30秒。`claude-work-timer`のデフォルト値を踏襲）を追加する。
  gapが閾値以上になり区間（セグメント）が閉じるたびに、閉じたセグメントの末尾へこの秒数を加算する
  （応答を読む・確認する等、次のgapとしては表れない実作業時間の補完）。加えて、集計対象entryが
  1件以上ある場合、走査完了時点で「現在末尾の（まだ閉じていない）セグメント」に対しても同様に
  1回だけ加算する。これにより、entryが1件しか無いセッション（旧設計では`activeSeconds=0`に
  なっていた）でもtail buffer分が計上される。
  - 走査完了時点のtail buffer加算は「まだ閉じていない区間を暫定的に閉じたとみなす」加算のため、
    次回pushで同じセッションのtranscriptが伸びて再集計すると、この暫定加算分は「実際のgap＋
    新しい末尾へのtail buffer」に置き換わる形で再計算される。置き換え後の値は常に元の値以上になる
    （新しく追加されるgapぶんだけ増える）ため、`activeSeconds`は転記・再集計を繰り返しても
    単調非減少であり続ける。これにより`_usage_merge_state`側の既存の累計差分パターンに影響しない
    （下記参照）。
  - 上記の設計でも、閾値未満の短い待機の混入・閾値以上の長時間ツール実行の除外という2方向の誤差、
    およびtail bufferの固定値ゆえの過不足（実際の読了時間が30秒より長い/短いケース）は残る。
    「目安」である旨をレポート・ドキュメントに明記する（既存のトークン集計と同じ扱い）。
- **実装時に判明した制約: `fromdateiso8601`は開発機のjqでは使えない**。Windowsネイティブ版jq
  （`C:\Program Files\jq\jq.exe`、jq 1.6）は`strptime`/`mktime`が未実装で、`fromdateiso8601`
  （内部で`strptime`を使う）を呼ぶと`strptime/1 not implemented on this platform`で失敗する
  （実機確認済み）。さらに、この失敗が既存の`try fromjson catch empty`（不正なJSON行を無視する
  ためのガード）と組み合わさると、jqが**エラーを一切出さず出力全体が`null`になる**という現象があり
  （実機確認済み。原因特定に時間を要した）、当初この設計のまま実装した結果、テストで気づかず
  マージされていた可能性があった。そのため`strptime`/`mktime`に依存しない、`days_from_civil`
  アルゴリズム（グレゴリオ暦の年月日→エポック日数を四則演算のみで計算する手法。C++の
  `<chrono>`ライブラリ等で広く使われる）による自前のISO8601→epoch秒変換関数
  （`epoch_from_iso8601`）を`_usage_aggregate_transcript`内に実装する。`date -u -d <iso8601> +%s`
  の結果と一致することを手動確認済み。詳細は
  `.claude/rules/shell-script-style.md`「JSON操作」節にも一般的な注意事項として追記した。
- `_usage_aggregate_transcript`: 集計対象entry（`gitBranch`一致・assistant）を時系列順に走査しながら、
  直前entryとの`.timestamp`差（自前実装の`epoch_from_iso8601`でepoch秒変換）を
  `IDLE_GAP_THRESHOLD_SECONDS`と比較し、未満ならその区間分を、以上ならセグメント終端として
  `TAIL_BUFFER_SECONDS`を`activeSeconds`（累計）に加算するreduceロジックを追加する（最初のentryには
  比較対象が無いため加算しない。タイムスタンプが逆行する負のgapは異常値として何も加算しない）。
  走査完了後、集計対象entryが1件以上あれば`TAIL_BUFFER_SECONDS`をもう1回加算する
  （現在末尾のセグメントを閉じる分）。戻り値JSONに
  `activeSeconds`を追加する。
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
  - 閾値未満のgapはそのまま加算・閾値以上のgapはセグメント終端としてtail bufferに置き換わる
  - `gitBranch`不一致entryの除外
  - entryが1件のみのセッションでもtail buffer分が計上される（参考実装`claude-work-timer`の
    `returns single segment for one event`相当）
  - 複数の閾値超gapがある場合、セグメントの数だけtail bufferが積み上がる（`handles multiple idle
    gaps`相当）
- `_usage_merge_state`: 初回push（セッション未記録）と2回目以降のpush、それぞれでの
  `activeSeconds` delta計算（2回目以降は、tail bufferの暫定加算分が実gap＋新しいtail bufferに
  置き換わっても差分が負にならない＝単調非減少であることを含めて確認する）

`tests/README.md` の一覧表に新規テストの行を追加する。

## 対象外

- 5分（既定値）未満の短い待機を稼働時間から完全に除外すること（gap単位の閾値判定という設計上、
  短い待機は区別できない。既知の制約として文書化のみ）。
- tail buffer（既定30秒）の値を実際の読了時間に応じて動的に調整すること（固定値のみ。
  参考実装と同じ簡易な近似に留める）。
- 複数セッション（`/resume`等でtranscriptファイルが切り替わるケース）をまたいだ稼働時間の
  合算、および複数プロジェクト・複数セッション同時進行時の区間重複除去（overlap dedup。
  `claude-work-timer`の`mergeIntervals`/`claude-code-time-tracking`の「Active Hours」相当）
  （既存の懸念点と同様、未対応のまま。本issueは単一ブランチ・単一セッションの範囲で完結する
  対応工数レポートのため、複数セッション間の重複除去は将来必要になった場合に別issueで検討する）。
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
