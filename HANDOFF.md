# HANDOFF

<!--
AIセッション間・AI⇔人間の状況引継ぎメモ。常に「このブランチの現状」を表現する
-->

## 現在地

- issue #15（作業にかかったトークン等の情報をMRのコメントに記載する）対応中。
- ブランチ: `feature-15-mr` / Draft PR #17（https://github.com/yuki-matsu783/nagame-ahk/pull/17）
- 計画: [plans/groovy-zooming-balloon.md](plans/groovy-zooming-balloon.md) / 詳細ログ:
  [worklog/2026-08-16_groovy-zooming-balloon.md](worklog/2026-08-16_groovy-zooming-balloon.md)
- 実装済み（実機検証済み）:
  - `dev-tools/src/vcs/Provider.ps1`/`Github.ps1`/`Gitlab.ps1`: `New-DraftMergeRequest`が
    base差分無しブランチで失敗した場合に空コミット→1回リトライする自動化（`Add-EmptyCommitForDraftMr`）。
    `Add-MrComment`（MRへ新規コメント投稿）を追加。
  - `.claude/hooks/lib/UsageTracking.ps1`（新規・共有ライブラリ）: `Sync-UsageState`が集計本体。
    `entry.gitBranch -eq $Branch` でフィルタして集計する（複数ブランチを跨いだ際の他ブランチ分混入
    バグを修正済み。実データで452,144トークン分の混入を確認・解消した）。
  - `.claude/hooks/stop-usage-record.ps1`（Stop hook）: `Sync-UsageState -IncrementTurn`を呼ぶだけに
    簡素化。ターン数カウントの役割のみ残した。
  - `.claude/hooks/post-push-usage-report.ps1`（PostToolUse hook, git push検知）: 投稿前に自分でも
    `Sync-UsageState`を呼んで最新化してから投稿・リセットする（Stop未発火のターン中の初回pushでも
    記録漏れが起きないよう修正済み。実機検証済み：「対象ターン数0」でも実データが反映されることを確認）。
  - `.claude/settings.json`にStop/PostToolUseのhook登録を追加。

## 次回やること

- **hookの実地E2E確認は完了済み**（2026-08-16、3回実施、うち1回は手動実行なしの本番動作）。
  1回目: ターン終了→`Stop` hookが状態ファイルへ実データを蓄積→空コミットでのgit push→`PostToolUse` hook
  が実際に発火しPR #17へ自動投稿されることを確認。2回目: `gitBranch`混入バグ修正後、状態ファイルを
  削除した状態から実セッションの`session_id`で`post-push-usage-report.ps1`を実行し、Stop未発火
  （ターン途中）でも実データが反映されることを確認（1・2回目のテスト投稿は確認後に削除済み）。
  3回目: 修正一式をcommit・pushした際、**手動実行を挟まず**hookが自然発火し、PR #17へ実データの
  コメント（comment id 5303251381）が投稿された。これは削除せず作業ログとして残している。
- issue-mr-flowの残りステップを継続: MRレビュー→設計反映（`dev-tools/docs/spec/issue-mr-workflow.md`へ
  「Draft PR空コミット自動リトライ」「セッション使用量レポート」の節を追加、`docs/ddr/`へtranscript
  パース方式を採用した経緯・gitBranchフィルタの理由を記録）→ plans/worklog削除→Draft解除。

## 判断が分かれるポイント

- PostToolUseの`if`フィールドが`PowerShell`ツールに対しても`Bash`同様に効くかは公式ドキュメントに
  明記が無く未検証（`Bash`側の`git *`サブコマンド単位マッチは明記あり）。効かない場合はPowerShellツール経由の
  `git push`ではレポートが発火せず、次回の対象トリガーまで繰り越されるだけ（データロスは無い設計）。

## 未解決の質問

## 守るべき条件・触ってはいけない範囲

- `.claude/hooks/*.ps1`は新規作成時、**BOM付きUTF-8で保存**すること（BOM無しだとWindows PowerShell 5.1で
  パースエラーになる。実機で確認済み。`.claude/rules/powershell-encoding.md`参照）。
