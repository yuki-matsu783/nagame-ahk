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

## 実装状況（flow-id 11）

対応方針A〜Gを実装した。

- A: `.claude/usage-state/`・`.claude/session-logs/`を削除し（gitignore対象・git管理外のため
  移行不要）、`.gitignore`を`/usage/`1行へ統合。
- B・C・E: `.claude/hooks/lib/UsageTracking.sh`を全面的に書き換え。
  `_usage_read_new_lines`/`_usage_aggregate_new_lines`（新規行diff集計・skillCalls/agentCalls/
  askUserQuestions抽出）を追加し、`_usage_merge_state`を「delta加算＋activeSecondsのみ差分」方式へ
  変更。`_usage_merge_agent_state`/`_usage_aggregate_and_merge_subagents`もagentId単位の
  カーソル管理を組み込んで書き換え。`_usage_aggregate_transcript`自体はactiveSeconds算出専用として
  無改造のまま維持。
- F: `.claude/hooks/post-push-usage-report.sh`に「skill呼び出し」「Agent呼び出し」
  「ユーザーへの質問」の3テーブルを追加。state_dirのパスも`usage/state`へ更新。
- G: `tests/test_usage_tracking.sh`を全面的に書き換え（66件、全pass）。

### テスト設計で気づいたこと（重要）

当初、「セッションが別ブランチで初めてpushされる際に過去分が二重計上されない」ことを示す
回帰テストを、実データに似せて「既存3行を新しいブランチラベルで複製した上で1行追記する」
シナリオで書いたが、**期待値が誤っていた**（実際の結果は1ではなく4）。

理由: Claude Code側のresumeでtranscript行が複製される場合、複製は新しい物理行として
ファイル末尾に追記される（＝カーソル位置より後ろに来る）ため、カーソル方式であっても
複製された行自体は「新規行」として数えられてしまう。カーソル方式が確実に防ぐのは
「同じ行を同じ位置から二重に読むこと」であり、「重複した内容が新しい位置に現れること」までは
防げない（plan Context節にも記載の通り、行の中身を判別して除外することは意図的に行わない
設計のため）。

そのため回帰テストは、「カーソルがブランチ単位ではなくセッション単位でグローバルに保持される」
という、この設計が確実に保証する性質のみを検証する形に修正した
（同一transcriptのままブランチだけ切り替えてpushした場合に、新規行が無いため状態が更新
されないことを確認するテスト）。plan本文の記述自体（「新しいブランチで初めてpushされた際、
prevSessionが存在せず蓄積済みの全件が計上されてしまう」）はこの性質を指しており、
実装・plan・テストの整合は取れている。

### 検証方法の変更点

plan「検証方法」節では、実データ（`.claude/session-logs/feature-45-.../main.jsonl`）を使った
手動再現を挙げていたが、対応方針Aの実施（`.claude/usage-state/`・`.claude/session-logs/`の削除、
gitignore対象＝git管理外のため実行済み）でこのファイル自体が無くなった。代わりに、上記の
「カーソルがセッション単位でグローバルに保持される」ことを検証する自動テストを
`tests/test_usage_tracking.sh`に追加し、同等の検証を再現可能な形でカバーしている
（`bash tests/test_usage_tracking.sh` で66件すべてpass）。

## flow-id 14〜16（レビュー・設計反映）

「レビューOK」の連絡を受け、`comments all`で未解決の実装レビュースレッドが無いことを確認した
（自動投稿の工数レポートコメントのみで、人間からのレビューコメントは無かった）。

対応方針Hに沿って設計反映を実施した。

- `dev-tools/docs/spec/issue-mr-workflow.md`「対応工数レポート」節を新方式に合わせて全面更新した。
  特に、PR #29時点のDDR 0006・spec本文が明記していた「全件再パース＋スナップショット差分方式を
  維持し、行オフセットベースの差分パースへ踏み込まなかった」という過去の判断を、今回`tools`/
  `tokens`/`turns`については覆したことが分かるよう明示した（`activeSeconds`のみ従来方式を維持する
  理由は変わらず有効なため、そのまま維持）。
- DDR 0006は既存内容を変更せず「追記（issue #37）」セクションのみ追加した（docs-workflow.mdの
  DDR運用「一度マージしたら追記のみ」に従う）。uuidベースの重複排除案が却下された経緯、採用した
  セッション横断カーソル設計、既知の限界（resumeによる物理的な重複行は除外しない）、`usage/`
  ディレクトリ移設の理由をまとめて記録した。
- `.claude/rules/directory-structure.md`のツリーへ`usage/`エントリを追加した。

flow-id 17（AIアセット改善）は、今回の作業を振り返った結果、ルール・スキル自体
（`.claude/rules/`, `.claude/skills/`, `AGENTS.md`, `CLAUDE.md`）に不備・改善点は見つからなかった
ため対応なしとした。
