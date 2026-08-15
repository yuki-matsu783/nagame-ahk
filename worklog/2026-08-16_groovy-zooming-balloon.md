# worklog: issue #15 MR使用量レポート + Draft PR空コミット自動化

計画: [plans/groovy-zooming-balloon.md](../plans/groovy-zooming-balloon.md)

## 経緯・調査メモ

- PR #13（issue #12）は既にmergedだった（SessionStart hookの表示は古いスナップショットで`[Ready]`と
  出ていたが、`gh pr view`で確認すると`MERGED`）。mainを最新化してから`feature-15-mr`ブランチを作成した。
- `New-DraftMergeRequest`実行時、実際に「No commits between main and feature-15-mr」で失敗した
  （既知の制約。`dev-tools/docs/spec/issue-mr-workflow.md`未決定事項に記載済み）。ユーザー指示により、
  この場その場の回避（空コミット）ではなく、同じブランチでツール自体を修正することにした。
- Claude Codeの公式hooksドキュメント（code.claude.com/docs/en/hooks）を調査:
  - Stopフックのstdin JSONにトークン/コスト情報は含まれない。
  - transcript_path先のJSONLは非公開の内部フォーマット（将来変更されうる旨が明記）。他に手段が無いため
    ベストエフォートで自前パースする方針とした。
  - PostToolUseの`if`フィールド（permission rule syntax）でマッチしない場合はプロセス起動されない
    （`Bash(git push*)`のように`&&`/`;`区切りの各サブコマンドを個別評価）。
  - SessionEndは既定1.5秒の共有予算（設定で最大60秒まで拡張可）だが、今回はStop/PostToolUseで完結する
    設計にしたため直接は関係しない。
- ユーザーとの合意: 投稿トリガーは「Stop毎にローカル記録、git push成功時に差分をサマリ投稿」、記録範囲は
  「モデル別トークン数＋ツール実行回数＋ターン数」（USD費用・diff・プロンプト内容は対象外）。

## 実装ログ

- `Provider.ps1`に`Add-MrComment`（dispatch）・`Add-EmptyCommitForDraftMr`（共通ヘルパー）を追加。
- `Github.ps1`/`Gitlab.ps1`の`New-DraftMergeRequest`実装に、`$LASTEXITCODE -ne 0`検知→
  `Add-EmptyCommitForDraftMr`→1回だけリトライを追加（`GitHub-GetMrForBranch`と同じ
  `$LASTEXITCODE`判定方式に合わせた。try/catchにしなかった理由: native exeの非0終了は
  PowerShell 5.1では既定で例外化されないため）。`GitHub-AddMrComment`/`GitLab-AddMrComment`も追加。
- **実機検証**: 修正直後、実際に issue #15 のブランチ（`feature-15-mr`、コミット差分無し）で
  `New-DraftMergeRequest`を実行 → 想定通り初回`gh pr create`が失敗 → 空コミット
  （`1e8924d`）をpush → リトライで成功し、Draft PR #17
  （https://github.com/yuki-matsu783/nagame-ahk/pull/17）が作成された。回避策が机上の空論でなく
  実地で機能することを確認できた。
- `Add-MrComment`を手動で1回呼び出し、PR #17へコメントが投稿されることを確認（確認後にテストコメントは削除）。
- `.claude/hooks/stop-usage-record.ps1`・`.claude/hooks/post-push-usage-report.ps1`を新規作成。
  **BOM無しUTF-8で保存されており`.claude/rules/powershell-encoding.md`の規約違反で構文エラーになった**
  （実機確認）。`[System.Text.UTF8Encoding($true)]`で再保存しBOM付きにして解消。以後.ps1新規作成時は
  この点に要注意（ルール自体は既知だったが、Writeツールでの新規作成時にBOM無しになることを見落としていた）。
  - 実transcript（過去セッションのjsonl）を使ったドライラン検証で、`message.usage`
    （input_tokens/output_tokens/cache_creation_input_tokens/cache_read_input_tokens）と
    `message.model`、`message.content[].type=="tool_use"`の`name`が想定通りの位置にあることを確認。
    集計結果を状態ファイルに書き出せることも確認。
  - `post-push-usage-report.ps1`もドライラン実行し、PR #17へ実際にレポートコメントが投稿されることを
    確認（テーブル・免責文言とも意図通り。確認後にテストコメント・テスト状態ファイルは削除済み）。
  - 既知の懸念点として残す: コメント本文のBOM混入（`Set-Content -Encoding UTF8`がPS5.1既定でBOM付与する
    ため、gh投稿本文の先頭に不可視文字が入る。GitHub側の表示には実害無いため今回は許容し、
    `Set-MrDescription`等の既存箇所と同じ挙動として揃えた）。
- `.claude/settings.json`に`Stop`・`PostToolUse`（matcher `Bash|PowerShell`、`if`で`git push`検知）を追加。
  JSONとして妥当であることを確認済み。
- `.gitignore`に`/.claude/usage-state/`を追加。

## 実地E2E確認（2026-08-16、手動ドライランではなく実ハーネス発火での確認）

- commit・push直後（同ターン内）にPR #17を確認した際はコメントが無かったが、これは
  push時点で当該ターンの`Stop`イベントがまだ発火していなかった（応答終了時に発火するため）ことによる
  想定通りの結果だった。
- 次ターンで`.claude/usage-state/feature-15-mr.json`を確認すると、前ターンの`Stop` hookにより
  実際のトークン数・ツール呼び出し回数が`sinceLastPush`に記録されていた。
- 確認用の空コミットをpushしたところ、`post-push-usage-report.ps1`が実際に発火し、PR #17
  （https://github.com/yuki-matsu783/nagame-ahk/pull/17）へ実データを含む自動コメントが投稿された
  （コメントID 5303199534）。投稿後は状態ファイルの`sinceLastPush`が正しくリセットされていることも確認。
- 副次的な確認事項として、`.claude/settings.json`のhooks変更が**同一セッション内で即時反映される**
  （プロセス再起動不要）ことも分かった。

## 追加対応: 初回push時の記録漏れ・他ブランチ混入バグの修正（同日2回目）

ユーザー指摘: 「最初のpush時にそれまで使ったトークン量を投稿できるようにしたい。stop以外のhookで
記録するようにすれば良いか？」

- 原因調査の過程で、実transcriptの`gitBranch`フィールド（各assistantメッセージに実行時のブランチ名が
  付与されている）を発見。既存実装は**セッション全体の累計を無条件にそのブランチの使用量として扱って
  おり、複数ブランチを跨いだ場合に他ブランチ分が混入するバグ**があったことも同時に発覚した。
  実際にこのセッションのtranscriptで検証したところ、`feature-15-mr`分17,634,027トークンに対し、
  無関係な`feature-12-...`/`main`分が452,144トークン混入する状態だった（既存実装の実害を定量確認）。
- 対応: `.claude/hooks/lib/UsageTracking.ps1`を新規作成し、`ConvertTo-HashtableDeep`/
  `Get-ZeroTokenBucket`/集計本体（`Sync-UsageState`関数、`entry.gitBranch -eq $Branch`でフィルタ）を
  共有ロジックとして集約。`stop-usage-record.ps1`・`post-push-usage-report.ps1`はこれをdot-sourceして
  呼ぶだけに簡素化した。
- `post-push-usage-report.ps1`は投稿要否判定の**前**に自分でも`Sync-UsageState`を呼ぶよう変更。これにより
  「Stopがまだ発火していないターン途中でのgit push」でも、その時点までtranscriptに書き出し済みの内容が
  反映されるようになった（`Stop`は「ターン数のカウント」のためだけに残した`-IncrementTurn`指定で維持）。
- 新規ファイルは今回もBOM無しUTF-8で作成されたため、都度BOM付きに変換＋`ParseFile`で構文検証した。
- **実機検証**: 状態ファイルを削除した状態から、実セッションの`session_id`/`transcript_path`を使って
  `post-push-usage-report.ps1`を実行（＝「このターンのStopがまだ発火していない」状況を正確に再現）。
  投稿されたレポートの「対象ターン数」が`0`（Stop未発火）でありながら、実際のトークン数・ツール実行回数が
  正しく反映されていることを確認した（確認後にテストコメントは削除）。
