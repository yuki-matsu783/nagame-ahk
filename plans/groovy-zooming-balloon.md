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

---

# 追加計画（同issue #15内、2026-08-16 2回目）: 初回push時のトークン記録漏れ対応

**注記**: 上記が最初に承認・実装・実機検証済みの計画（実装完了）。本セクションは同じセッション内で
発覚した追加課題に対する2つ目の計画（`.claude/rules/plan-mode-safety.md`に従い、承認済み計画を書き換える
のではなく新セクションとして追記する。既存文書ツールの都合上ファイルは分けていないが、内容は独立した
計画として扱う）。

## Context

ユーザーからの指摘: 「最初のpush時にそれまで使ったトークン量を投稿できるようにしたい。stop以外のhookで
記録するようにすれば良いか？」

原因: `Stop`は**1ターン完了時**にしか発火しない。1ターンの途中で`git push`が実行されると
（実際、今回のissue #15対応でも「ブランチ作成→調査→実装→push」を1ターン内で行っており、最初のpushは
ターン途中で発生していた）、そのターンで既に消費したトークンは、まだ`Stop`によって状態ファイルへ
記録されていない。そのため`post-push-usage-report.ps1`は「記録が0件」と判断し投稿しない
（設計通りだが、ユーザー体験としては「最初のpushで何も投稿されない」という欠落に見える）。

調査の結果、より良い解決策が判明した。「Stopの代わりに別のhookで記録する」のではなく、
**`post-push-usage-report.ps1`自身が投稿直前に自分でtranscriptを読み直す**（`Stop`同様の集計処理を
共通化して呼ぶ）ことで、その時点までにtranscriptへ書き出し済みの内容を漏れなく反映できる
（`transcript_path`は`PostToolUse`のペイロードにも含まれる共通フィールドであるため）。`Stop`は
「ターン数のカウント」のためにこのまま維持する。

**追加で発見した既存バグ**: 現在の実装（`Get-ZeroTokenBucket`集計ロジック）はセッション全体の累計を
無条件にそのブランチの使用量として扱っており、**同一セッション内で複数ブランチを跨いだ場合に
他ブランチ分のトークンまで混入する**。実際に今回のセッションのtranscriptを確認したところ、
`gitBranch`フィールド（各assistantメッセージに付与されている。全assistantエントリ198件中198件に
存在することを確認済み）が `feature-12-adr-ddr-design-decision-record`(32件) → `main`(6件) →
`feature-15-mr`(274件) と遷移しており、既に投稿済みのレポート（PR #17, comment id 5303199534）には
本来issue #15と無関係な`feature-12`ブランチでの消費分が混入していたことを確認した。これも今回合わせて
修正する（`gitBranch`でフィルタして集計する）。既に投稿済みの当該コメントは実害が小さく
（「目安」であることを明記済み・レビュー判定にも不使用）、遡っての訂正は行わない。

## 変更するファイル

1. **`.claude/hooks/lib/UsageTracking.ps1`**（新規、共有ライブラリ）
   - `ConvertTo-HashtableDeep`・`Get-ZeroTokenBucket`: 既存2スクリプトから移設
   - `Sync-UsageState -RepoRoot -Branch -SessionId -TranscriptPath [-IncrementTurn]`:
     既存の集計ロジックを移設した上で、`type=="assistant"`に加え**`entry.gitBranch -eq $Branch`**
     でフィルタするよう変更（ブランチ混入バグの修正）。状態ファイルの読み込み・差分計算・
     `sinceLastPush`への加算・保存までを行い、更新後の`$state`を返す。`-IncrementTurn`指定時のみ
     `sinceLastPush.turns`を+1する。

2. **`.claude/hooks/stop-usage-record.ps1`**（修正）
   - 集計処理本体を`UsageTracking.ps1`のdot-source＋`Sync-UsageState -IncrementTurn`呼び出しに置き換え。
     冒頭のガード処理（サブエージェント判定・mainブランチ判定等）はそのまま維持。

3. **`.claude/hooks/post-push-usage-report.ps1`**（修正）
   - 「状態ファイルを読んで合計0なら終了」の**前**に、`UsageTracking.ps1`をdot-sourceし
     `Sync-UsageState`（`-IncrementTurn`無し）を呼んで状態を最新化してから、以降の投稿要否判定・
     投稿処理を行う。これにより、当該ターンの`Stop`が未発火でも、その時点までtranscriptに
     書き出し済みの内容が反映される（初回pushでも記録漏れが起きなくなる）。

## 対象外（今回やらないこと）

- セッション（transcriptファイル）を跨いだ集計の継続（`/resume`等で新しいtranscriptファイルに
  切り替わった場合、旧セッション分との合算は行わない。現行実装でも未対応で、今回もスコープ外のまま）
- 既に投稿済みのコメント（PR #17, comment id 5303199534）の遡及的な訂正・削除

## 検証方法

- 修正後、`.claude/usage-state/feature-15-mr.json`を一旦削除し、実際に何らかのBash/PowerShell操作を
  行った直後（＝`Stop`が発火する前）に`git push`を実行して、`post-push-usage-report.ps1`が
  その時点までの使用量を反映したコメントをPR #17へ投稿することを実地確認する。
- 現セッションのtranscript（`gitBranch`混在済み）で`Sync-UsageState`を手動実行し、
  `feature-15-mr`分のみが集計され、`feature-12-...`/`main`分の数値が含まれないことを確認する。

---

# 追加計画（同issue #15内、2026-08-16 3回目）: Stop hookの削除とターン数算出の一本化

## Context

ユーザー指摘: 「`.claude\hooks\stop-usage-record.ps1`とかはもう利用していないのなら消してしまって
ほしい」。

調査の結果、`Stop` hookが担っていた役割は「`sinceLastPush.turns`（ターン数）を+1する」ことのみで、
トークン・ツール呼び出し集計自体は既に`post-push-usage-report.ps1`が投稿直前に自分で
`Sync-UsageState`を呼んで最新化する設計（前回の追加計画）に変わっている。加えて、この
`Stop`依存のターン数カウントは、**トークン集計で直したのと同じ穴**（そのターンの`Stop`がまだ
発火していない状態でpushすると過少カウントされる）を抱えたまま残っていた。実際、直近の自動投稿
コメントは実データ（トークン数・ツール実行回数）があるにもかかわらず「対象ターン数: 0」と
表示されていた（本来の意味とズレた不正確な値）。

`Stop`を残す積極的な理由が無くなったため、削除しPostToolUse（git push検知）1本の構成へ単純化する。

## 決定

**`turns`（ターン数）も、トークン・ツール呼び出しと同じ方法（transcriptとの差分）で算出するよう
`Sync-UsageState`を変更し、`Stop` hookを廃止する。**

- `Sync-UsageState`内で、`gitBranch`フィルタ後の**assistantエントリ件数**を数え、セッションの
  前回記録値（`sessions[$SessionId].lastAssistantCount`、新規追加）との差分を`sinceLastPush.turns`
  へ加算する（tokens/toolCallsと全く同じ「差分を加算」パターン）。`-IncrementTurn`スイッチは廃止する
  （常にtranscriptから直接算出するため、呼び出し元に関わらず一貫した値になる）。
- **注意**: 1ユーザーターンの中で複数回のツール呼び出しが発生すると、assistantメッセージ自体は
  複数生成されうる（tool_use→tool_result→assistantの応答ループのため）。そのため本来の
  「会話ターン数」とは厳密には一致せず、「assistant応答回数」に近い値になる。この違いは
  懸念点として明記し、レポート上のラベルも「対象ターン数」から**「assistant応答回数」**に変更する
  （実態と表現を一致させる）。

## 変更するファイル

1. **`.claude/hooks/lib/UsageTracking.ps1`**: `Sync-UsageState`内でassistantエントリ件数を集計し
   `sinceLastPush.turns`への差分加算に組み込む。`-IncrementTurn`パラメータを削除。
2. **`.claude/hooks/stop-usage-record.ps1`**: 削除。
3. **`.claude/hooks/post-push-usage-report.ps1`**: `Sync-UsageState`呼び出しから
   `-IncrementTurn`指定が無くなる点のみ（既に指定していないため実質変更なし）。レポート本文の
   ラベル「対象ターン数」→「assistant応答回数」に変更。
4. **`.claude/settings.json`**: `hooks.Stop`エントリを削除。
5. **既に（未コミットの）今回のセッションで書いたspec/DDR**（`dev-tools/docs/spec/issue-mr-workflow.md`、
   `dev-tools/docs/ddr/0006-...`）: `Stop`の役割に関する記述を、上記の新設計に合わせて修正する
   （まだコミット前のため、修正版をそのまま設計反映として書く。訂正コミットは不要）。

## 対象外

- 「本来の会話ターン数」を厳密に算出する対応（Stopに依存せず正確なターン境界を知る手段が無いため、
  「assistant応答回数」という近似値で妥協する）。

## 検証方法

- `Sync-UsageState`を実transcriptで手動実行し、`turns`（新ラベルではassistant応答回数）が
  0にならず、tokens/toolCallsと同様に妥当な値になることを確認する。
- `.claude/settings.json`から`hooks.Stop`を削除した状態で、実際に何らかの作業→`git push`を行い、
  `post-push-usage-report.ps1`単体でレポートが正しく投稿されることを実地確認する。
