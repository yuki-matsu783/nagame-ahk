---
title: 対応工数レポートの集計ロジック修正と詳細テーブル追加
type: rule
description: issue #37対応。push断面ごとのtranscript diffに基づく集計方式への変更と、skill/AskUserQuestion/Agent呼び出しの詳細テーブル追加の実施計画
tags: [usage-tracking, bugfix, reporting]
keywords: [対応工数レポート, UsageTracking, line-offset, diff, session-cursor, skillCalls, agentCalls, askUserQuestions]
---

# 対応工数レポートの集計ロジック修正と詳細テーブル追加

## Context

issue #37「対応工数レポートの数値が間違っていそうなので集計ロジックを修正する」への対応。
利用したツールの数が明らかにずれているという報告を受け、`.claude/hooks/lib/UsageTracking.sh` /
`.claude/hooks/post-push-usage-report.sh` を調査した。

実データ（`.claude/session-logs/feature-45-commit-skill-skip-confirmation/9e53412d-.../main.jsonl`）で、
同一`uuid`のtranscript行が複数回（異なる`gitBranch`ラベル付きも含む）出現することを確認した。
当初この「同一uuidの重複」自体をバグとみなし、uuidベースの重複排除で対応する案を提示したが、
`uuid`はあくまで会話木のノード識別子（`parentUuid`によるチェーン構造）であり、同一uuidが
複数箇所に現れること自体は異常ではないというユーザー指摘により、その案は不採用とした。

代わりに、issue本文が当初から提案していた方式（**push断面ごとにtranscriptの「これまでに処理済みの
行数」を記録し、前回pushからの新規行のみを対象に集計する**）を採用する。この方式は、transcript内の
個々の行の意味（重複か否か・どのブランチのラベルが「正しい」か）を一切詮索せず、「一度数えた範囲は
二度と数え直さない」という機械的な原則だけで、現在の「毎回全件を再パースし、前回の累計との差分を
引き算する」方式が抱える問題（同一セッションが新しいブランチで初めてpushされた際、`prevSession`が
存在せず、蓄積済みの全件がその新しいブランチの初回差分として計上されてしまう）を解消する。

あわせて、issueのもう1つの要望（受け入れ条件にも明記）である「skill呼び出し」「AskUserQuestion」
「Agent(サブエージェント)呼び出し」の詳細テーブル化も、同じissue/PRで実装する（ユーザー承認済み）。

## 対応方針

### A. セッション横断のカーソル管理（新規）

新規ディレクトリ `.claude/usage-state/session-cursors/<sessionId>.json`（サブエージェントは
`<agentId>.json`）に、`{lastLineCount: N}`（transcriptのうち空行を除いた行数で、前回までに
集計済みの行数）を記録する。**ブランチをまたいだセッション再開でも取りこぼし・二重計上が
起きないよう、このカーソルはブランチに紐付けず、セッション（agentId）単位でグローバルに管理する**
（同じディレクトリ配下は`.claude/usage-state/`の既存gitignore設定でそのままカバーされるため、
`.gitignore`の変更は不要）。

### B. 新規行の切り出し・集計（`.claude/hooks/lib/UsageTracking.sh`）

- `_usage_read_new_lines(transcript_path, last_line_count)`: `[inputs | select(length > 0)]`で
  空行を除いた全行を配列化し、`.[$last_line_count:]`で前回カーソル以降の新規行のみを返す
  （総行数も併せて返す）。
- `_usage_aggregate_new_lines(new_lines, branch)`: 新規行のみを対象に、`.type=="assistant"`
  （tokens/tools/turns集計、および`skillCalls`/`agentCalls`抽出）と`.type=="user"`
  （`askUserQuestions`抽出）をそれぞれ`.gitBranch==branch`で絞り込みながら処理する。
  **この結果は「前回pushからの新規分」そのもの（＝差分）であり、既存のような
  `現在の累計 - 前回の累計`という引き算は不要で、素直に`sinceLastPush`へ加算するだけでよい。**
  - tools/tokens/turns（assistantCount）の集計ロジック自体は既存`_usage_aggregate_transcript`
    のtool_use/usageカウント部分を流用する。
  - `skillCalls`: `tool_use`かつ`name=="Skill"` → `{id, skill: .input.skill, args: .input.args}`
  - `agentCalls`: `tool_use`かつ`name=="Agent"` → `{id, subagentType: .input.subagent_type,
    description: .input.description, prompt: .input.prompt}`
  - `askUserQuestions`: `.type=="user"`エントリの`message.content[] | select(.type=="tool_result")`の
    `content`文字列（`"Your questions have been answered: ..."`形式。実データで確認済み）から、
    `"([^"]*)"="([^"]*)"`パターンで質問=回答ペアを`scan`抽出する（`.content`が配列の場合はtext
    ブロックを結合してから処理する）。

### C. `activeSeconds`は既存の全件再パース方式を維持

`activeSeconds`（稼働時間）は、gapベースの区間計算が「毎回全件を時系列で走査し直す」ことを前提に
単調非減少性を保証する設計になっており、新規行だけの断片的な走査では前回pushの「暫定クローズした
末尾セグメント」を正しく補正できない。このリスクを避けるため、**`activeSeconds`の算出だけは
既存の`_usage_aggregate_transcript`（全件再パース＋`sessions[sessionId].lastActiveSeconds`との
スナップショット差分）をそのまま維持**し、変更しない。1回のpushで「新規行diffの集計」と
「全件再パースによるactiveSeconds算出」の両方を行うことになるが、後者は既存コードの再利用であり
実装コストは小さい。

### D. `sync_usage_state` / `_usage_merge_state` の書き換え

- `sync_usage_state`: 新しい流れは以下の通り。
  1. transcriptの総行数（空行除く）を求める。
  2. `.claude/usage-state/session-cursors/<sessionId>.json`から`lastLineCount`を読む（無ければ0）。
  3. 総行数が`lastLineCount`以下なら新規行が無い＝**session-logsへのコピー・状態更新をスキップ**
     する（issue本文の「差分がなければコピーしない」に対応）。
  4. 新規行があれば、既存同様`.claude/session-logs/<branch>/<sessionId>/main.jsonl`へコピーし
     （ローカルデバッグ用の複製は維持）、新規行を`_usage_aggregate_new_lines`で集計する。
  5. 併せて全件再パースで`activeSeconds`を算出する。
  6. `_usage_merge_state`で状態を更新し、`session-cursors/<sessionId>.json`の`lastLineCount`を
     総行数へ更新する。
- `_usage_merge_state`: 引数の意味を変更する。
  - `tokens`/`tools`/`assistantCount`（turns）/`skillCalls`/`agentCalls`/`askUserQuestions`は
    **すでに差分（新規分）** として渡されるため、`sinceLastPush`へそのまま加算・追記する
    （既存の`current - prevSession`という引き算ロジックは撤廃）。これに伴い
    `sessions[sessionId].lastTokens`/`lastTools`/`lastAssistantCount`のスナップショットは
    不要になり削除する。
  - `activeSeconds`は**従来通り**全件再パースの累計値として渡され、
    `sessions[sessionId].lastActiveSeconds`との差分（`[0, cur-prev]|max`）を計算する
    （このフィールドのみ既存ロジックを維持）。
- `_usage_merge_agent_state`/`_usage_aggregate_and_merge_subagents`: サブエージェントの
  transcriptにも同じカーソル管理・diff集計を適用する（`agentId`をカーソルのキーとして使う）。
- `_usage_reset_since_last_push`: `sinceLastPush.skillCalls`/`agentCalls`/`askUserQuestions`も
  空配列へリセットする対象に追加する。

### E. レポート描画（`.claude/hooks/post-push-usage-report.sh`）

既存の「ツール実行回数」セクションの後に、対応する配列が非0件の場合のみ以下を追加する。

- `### skill呼び出し` — `| skill | args |` の2列テーブル
- `### Agent呼び出し` — `| サブエージェント種別 | 説明 | プロンプト |` の3列テーブル
  （既存の「### サブエージェント」＝トークン/稼働時間の実績テーブルとは別セクション。
  こちらは「呼び出し記録」であり、対応するサブエージェントがまだ完了していなくても表示される）
- `### ユーザーへの質問` — `| 質問 | 回答 |` の2列テーブル

各セルは既存の`description`列と同じ`sed 's/|/\\|/g'`でパイプをエスケープし、改行は半角スペースへ
変換する。`prompt`列は長文になりうるため300文字を超える場合は末尾を`…`で省略する。Windowsネイティブ
jqのコマンド置換CR混入対策（既存箇所と同じ`tr -d '\r'`）を、複数要素をforループで扱う新規箇所すべてに
適用する。

### F. テスト（`tests/test_usage_tracking.sh`）

既存テストのうち`activeSeconds`関連（gapベースの計算・単調非減少性）はロジック変更が無いためそのまま
維持できる。一方、`_usage_merge_state`のtokens/tools/turns関連テストは「引き算」から「加算」への
仕様変更に合わせて書き換える。追加するテスト:

1. `_usage_read_new_lines`: カーソル位置以降の行のみが切り出されることの確認。
2. `_usage_aggregate_new_lines`: tools/tokens/turns/skillCalls/agentCalls/askUserQuestionsの抽出が
   正しく行われることの確認（tool_use/tool_resultブロック→期待するJSON構造）。
3. `sync_usage_state`回帰テスト: 同一セッションが**別ブランチで初めてpushされるケース**を再現し、
   新ブランチの初回pushで過去ブランチ分の蓄積が誤って計上されない（＝カーソルがセッション単位で
   引き継がれ、新規行が無ければ差分0になる）ことを確認する（今回の実データで見つかった不具合の
   直接的な回帰テスト）。
4. 「差分が無ければコピー・状態更新をスキップする」ことの確認。
5. `_usage_reset_since_last_push`が新規3配列もリセットすることの確認。

### G. ドキュメント反映（flow-id 16、設計反映時）

`dev-tools/docs/spec/issue-mr-workflow.md`の「対応工数レポート」節を、新しい
「セッションカーソル＋新規行diff集計（tools/tokens/turns/詳細3種）／全件再パース（activeSecondsのみ）」
というハイブリッド方式に合わせて書き直す。

## 対象外

- `activeSeconds`（稼働時間）算出方式の変更（既存の全件再パース＋スナップショット差分を維持）。
- ネストしたサブエージェント（depth 2以降）のskill/agent/question詳細。
- サブエージェント自身が呼び出したskill/agent/questionの詳細（メインセッションのみ対象）。
- 一つのpushの中で、同一セッションがブランチをまたいで新規行を生成した場合の完全な行単位の
  按分（新規行を現在のブランチのみに帰属させる。他ブランチ分は次にそのブランチでpushされるまで
  カーソルが進まないため、そのタイミングで計上される）。

## 検証方法

- `bash tests/test_usage_tracking.sh` で全テストがpassすることを確認する。
- 実データ（`.claude/session-logs/feature-45-commit-skill-skip-confirmation/9e53412d-.../main.jsonl`）
  を使い、疑似的に「別ブランチでの初回push」シナリオ（カーソル未記録の状態からのsync_usage_state
  呼び出し→2回目呼び出しで新規行が無ければ差分0になること）を手動で再現し、現行方式との挙動差を
  確認する。
- 変更した`.sh`ファイルすべてを`bash -n`で構文チェックする。
