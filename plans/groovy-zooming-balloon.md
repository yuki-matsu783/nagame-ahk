# issue #15: 作業にかかったトークン等の情報をMRコメントに記載する（+ Draft PR作成の空コミット自動化）

## Context

issue #15（https://github.com/yuki-matsu783/nagame-ahk/issues/15）は、AIが1回の作業にどれだけ
トークンを使ったかが不明確なため、MRにコメントとして残して見えるようにしたい、という要望。受け入れ条件は
「何をコメントするかが明確」「MRにコメントされる」「レビューOK判定には使われない」の3点。

このセッションで issue #15 に着手する過程で `New-DraftMergeRequest`（`dev-tools/src/vcs/Provider.ps1`）が
「base との差分（コミット）が無いブランチでは失敗する」という既知の制約（`dev-tools/docs/spec/issue-mr-workflow.md`
の未決定事項に記載済み。issue #5 対応時に実機確認・空コミットで回避済みだが自動化はスコープ外にしていた）に
実際に当たった。ユーザー指示により、これを別issueには起票せず、issue #15 と同じブランチでついでに直接修正する。

トークン情報の取得方法を公式ドキュメント（code.claude.com/docs/en/hooks）で調査した結果:
- Stopフックのstdin JSONにトークン/コスト情報は**含まれない**（`session_id`/`transcript_path`/`last_assistant_message`等のみ）。
- 取得するには `transcript_path` が指すJSONLを自前パースする以外に手段が無いが、この**JSONLフォーマットは非公開
  内部仕様**であり将来のバージョンで変更されうる（公式に明記）。
- `PostToolUse` の `if` フィールド（permission rule syntax）でツール入力文字列にマッチした場合のみプロセスを
  起動できる（マッチしなければ起動コストゼロ）。`&&`/`;` 区切りの各サブコマンドを個別に評価する。

ユーザーとの合意事項:
- 投稿トリガー: **Stop毎にローカル状態ファイルへ累計記録し、git push成功時に前回投稿からの差分をMRへ新規
  コメントとして投稿**する（upsertや毎ターン投稿ではない）。
- 記録範囲: **モデル別トークン数（input/output/cache write/cache read）＋ツール実行回数＋ターン数**。
  USD推定コスト・ファイルdiff・プロンプト本文・サブエージェント詳細往復は今回スコープ外。

## 変更するファイル

1. **`dev-tools/src/vcs/Provider.ps1`**（provider非依存の追加）
   - `Add-EmptyCommitForDraftMr`: 空コミット+push（`New-DraftMergeRequest`失敗時の共通リトライ処理）
   - `Add-MrComment`（dispatch関数、既存の`Set-MrDescription`と同型）: MRへ新規コメントを投稿

2. **`dev-tools/src/vcs/Github.ps1`**
   - `GitHub-NewDraftMergeRequest`: `gh pr create`後に`$LASTEXITCODE -ne 0`なら`Add-EmptyCommitForDraftMr`→
     1回だけリトライ。既存コード（`GitHub-GetMrForBranch`）と同じ「$LASTEXITCODEで判定」方式に合わせる
     （try/catchではなく。native exeの非0終了はPS 5.1では既定で例外化されないため）。
   - `GitHub-AddMrComment`（新規）: `gh pr comment $MrNumber --body-file $BodyFile`
     （`GitHub-SetMrDescription`と同じ`--body-file`パターンで日本語・改行を安全に渡す）

3. **`dev-tools/src/vcs/Gitlab.ps1`**
   - `GitLab-NewDraftMergeRequest`: 同様の失敗検知・リトライ（【未検証】注記を維持）
   - `GitLab-AddMrComment`（新規）: `glab mr note $MrNumber --message <BodyFileの中身>`
     （`GitLab-SetMrDescription`と同じ「ファイルを読んで文字列で渡す」パターン）

4. **`.claude/hooks/stop-usage-record.ps1`**（新規）
   - `Stop`イベントで発火。`session-start.ps1`と同じ冒頭ガード（コンソールUTF-8化→サブエージェント判定
     `agent_id`→`CLAUDE_PROJECT_DIR`未設定なら終了→mainブランチなら終了）。
   - `transcript_path`のJSONLを1行ずつベストエフォートでパース（壊れた行はスキップ）し、
     `type=="assistant"` の `message.usage`（input/output/cache_creation/cache_read）を`message.model`別に、
     `message.content[].type=="tool_use"`を`name`別に、セッション内**累計**として集計する。
   - `.claude/usage-state/<branchをファイル名安全化したもの>.json` を読み、このセッションで前回記録した
     累計（`sessions[session_id].lastTotals`）との**差分**を`sinceLastPush`へ加算、`sinceLastPush.turns`を+1。
   - 例外は全て握りつぶしexit 0（トークン集計に失敗してもセッション継続を妨げない）。

5. **`.claude/hooks/post-push-usage-report.ps1`**（新規）
   - `PostToolUse`イベント（matcher `Bash|PowerShell`、各エントリに`if: "Bash(git push*)"` /
     `if: "PowerShell(git push*)"`）で発火。マッチしなければClaude Code側でプロセス起動されないため、
     通常のBash/PowerShell利用への性能影響は無い。
   - 状態ファイルの`sinceLastPush`が全て0なら何もしない（初回pushや無変化push対策）。
   - `Provider.ps1`をdot-sourceし`Get-MrForBranch`でMR番号取得。MR無ければ何もしない。
   - Markdownテーブル（モデル別トークン数・ツール実行回数・ターン数）を組み立て、冒頭に
     「自動投稿・レビュー判定には使用しないでください」の明記を入れて`Add-MrComment`で投稿
     （受け入れ条件「レビューOK判定に利用されない」に対応。通常コメントでありレビューではないため
     承認状態にも影響しない）。
   - 投稿成功後、`sinceLastPush`をリセットし`lastPostedAt`を更新。失敗時は状態を変更せず握りつぶす
     （次のpush時に繰り越されるだけで、pushやコミット自体をブロックしない）。

6. **`.claude/settings.json`**
   - `hooks.Stop`・`hooks.PostToolUse`を追加（`timeout`は`SessionStart`同様に明示）。

7. **`.gitignore`**
   - `.claude/usage-state/` を追加（ローカルの作業状態。ブランチ横断で使うためコミット対象外）。

## 対象外（今回やらないこと）

- USD推定コストの算出・表示（モデル単価表の保守負担を避ける）
- ツール入力内容・ファイルdiffの記録
- ユーザープロンプト本文の記録
- サブエージェント往復の詳細記録（Task呼び出し回数はツール実行回数に含まれるが内訳の深掘りはしない）
- `SessionEnd`フックの追加（Stop/PostToolUseのみで完結させる）
- GitLab側の実機検証（このリポジトリのremoteはGitHubのみのため、既存の【未検証】注記を踏襲するのみ）

## 検証方法

- `Add-EmptyCommitForDraftMr`/`GitHub-NewDraftMergeRequest`修正後、**まさにこのブランチ
  （`feature-15-mr`、現在コミット差分無し）でDraft PR作成を実行**し、空コミット経由で成功することを実地確認する
  （回避策が必要な状況が既に手元にあるため、モック無しで実際に検証できる）。
- `Add-MrComment`を手動で1回呼び出し、実際にMRへコメントが投稿されることを確認する。
- `.claude/settings.json`へのhook登録後、実際に何らかのBash/PowerShellコマンド（git push以外）を実行しても
  hookが起動しない（`if`フィルタが効いている）ことと、`git push`実行時にのみ起動し、MRへ差分サマリが
  投稿されることを実機確認する。
- `stop-usage-record.ps1`の集計値が、目視で大きく外れていない（0件やマイナス値にならない）ことを確認する
  （transcript内部フォーマットの正確な突合は困難なため、ベストエフォートの範囲で確認する）。

## 実装後（設計反映で対応。今は着手しない）

- `dev-tools/docs/spec/issue-mr-workflow.md` に「Draft PR作成の空コミット自動リトライ」「セッション使用量
  レポート機能」の節を追加し、未決定事項の該当項目を解消する。
- `docs/ddr/` に「transcript JSONLパース方式を採用した理由（他に確実な取得手段が無いため）とその既知のリスク
  （非公開フォーマットで将来壊れうる）」を記録する。
