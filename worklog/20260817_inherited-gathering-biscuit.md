---
title: 対応工数レポート集計ロジック修正 worklog
type: log
description: issue #37対応の作業ログ。集計ロジックの原因調査・設計転換の経緯を記録
tags: [usage-tracking, bugfix]
keywords: [対応工数レポート, UsageTracking, session-cursor, uuid, resume]
---

# 対応工数レポート集計ロジック修正 worklog

対象issue: #37「対応工数レポートの数値が間違っていそうなので集計ロジックを修正する」
plan: `plans/inherited-gathering-biscuit.md`

## 調査で分かったこと

Explore agentと手動jq調査により、`.claude/hooks/lib/UsageTracking.sh`の集計ロジックを確認した。

- 対応工数レポートは`.claude/hooks/post-push-usage-report.sh`（PostToolUse, `git push`検知）が
  `sync_usage_state`（`UsageTracking.sh`）を呼んで生成する。
- 現行方式: transcript JSONLを毎回全件再パースし（`_usage_aggregate_transcript`）、
  `.claude/usage-state/<branch>.json`の`sessions[sessionId]`に保存した「前回累計」との差分
  （`[0, cur-prev]|max`）を`sinceLastPush`へ加算する。
- 実データ（`.claude/session-logs/feature-45-commit-skill-skip-confirmation/
  9e53412d-a53d-4c08-bff8-6e2f31a89eb3/main.jsonl`）で確認:
  - `assistant`行1178件に対し、`uuid`固有数533件（約2.2倍）。
  - 例: uuid `febc42cc-4d0c-4d98-a145-f0cd73bbffb0`が4回出現し、そのうち3回は
    `gitBranch: "feature-39-use-commit-skill-rule"`、最後の1回だけ
    `gitBranch: "feature-45-commit-skill-skip-confirmation"`だった。
  - これは、同一セッションが複数回・複数ブランチにわたってresumeされる際、Claude Code側が
    過去のtranscript行を「resume時点のgitBranch」で再度書き出す（＝重複行が生まれる）ことに
    起因すると推測される。

## 設計の転換（重要）

最初にuuidベースの重複排除案（「同一uuidの行は最初の出現＝元のブランチのものだけを残す」）で
plan策定・ExitPlanModeを試みたが、ユーザーから却下された。

> あくまでparentuuidなので、重複があるのはおかしくない

`uuid`は会話木のノード識別子（`parentUuid`チェーン構造）であり、同一uuidの重複出現自体を
「異常」と決めつけて排除するのは前提が誤っていた、という指摘。ユーザーからの明示的な指示:

> やはり提案した通り、push毎にjsonlファイルの断面を取り、前回pushからの差分を取得し、
> tool_useの行をすべて数えて今回の作業までで実行されたツールの数をカウントするのが良い

これを受けてplanを全面的に書き直した。新方式:

- `.claude/usage-state/session-cursors/<sessionId>.json`に`lastLineCount`（前回までに処理済みの
  行数）をセッション単位（ブランチに紐付けない）で記録する。
- push毎に、transcriptの新規行（カーソル位置以降）のみを対象にtool_use/tokens/turnsをカウントし、
  そのまま`sinceLastPush`へ加算する（引き算ではなく単純加算）。
- これにより「行の中身が重複かどうか」を一切判断せず、「一度数えた範囲は二度と数え直さない」という
  機械的な原則だけで、実データで見つかった不具合（新ブランチでの初回pushで過去分がまるごと
  計上される）を解消できる。
- `activeSeconds`（稼働時間）は、gapベースの単調非減少性が「全件再パース」を前提にしているため、
  既存方式のまま変更しない（新規行diffだけでは前回の「暫定クローズ」を正しく補正できないリスクが
  あるため）。

この設計転換の経緯は`plans/inherited-gathering-biscuit.md`のContext節にも反映済み。

## 追加の設計変更: `.claude/`配下から`usage/`ディレクトリへの移設

plan策定・commit後、ユーザーから追加指示があった。

> session-logsとusage-stateが.claude配下にあるの微妙なので、プロジェクトルートにusageディレクトリを
> 作成してその中で管理するようにしてほしい

`.claude/`はAIエージェント自体の設定・ルール置き場という性格が強く、対応工数レポートの
ローカル作業状態（gitignore対象）を置くのは筋が悪いという指摘。まだ実装（コード変更）には
着手していなかったため、planへ反映してから実装に進むことにした。

- `.claude/session-logs/` → `usage/session-logs/`
- `.claude/usage-state/` → `usage/state/`（新設カーソルは`usage/state/session-cursors/`）
- `.gitignore`の該当2行を`/usage/`1行へ統合
- `.claude/rules/directory-structure.md`のツリーへ`usage/`を追記（flow-id 17で対応）

詳細はplan本文（対応方針A、E、G、H）に反映済み。

## 次のステップ

- plan本文（対応方針A〜H）に沿って実装する。
- 実装順序の目安: A（`usage/`ディレクトリ移設・`.gitignore`更新）→B（カーソル管理）
  →C（新規行diff集計）→E（sync_usage_state/merge_state書き換え）→F（レポート描画）→G（テスト）
  →H（ドキュメント反映、flow-id 16〜17）。
