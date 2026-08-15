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
  - `.claude/hooks/stop-usage-record.ps1`（Stop hook）: セッションのtranscriptからモデル別トークン数・
    ツール呼び出し回数を集計し、ブランチ単位の状態ファイル（`.claude/usage-state/<branch>.json`,
    gitignore対象）へ差分蓄積。
  - `.claude/hooks/post-push-usage-report.ps1`（PostToolUse hook, git push検知）: 蓄積分をMRへ
    新規コメントとして投稿し、投稿成功後にリセット。
  - `.claude/settings.json`にStop/PostToolUseのhook登録を追加。

## 次回やること

- 今回追加したhook（Stop/PostToolUse）が**このセッション自身の次回git push時に実際に発火するか**を確認する
  （settings.json変更が同一セッション内で即時反映されるかは未検証。反映されない場合は次回セッションでの
  実機確認になる）。
- issue-mr-flowの残りステップを継続: MRレビュー→設計反映（`dev-tools/docs/spec/issue-mr-workflow.md`へ
  「Draft PR空コミット自動リトライ」「セッション使用量レポート」の節を追加、`docs/ddr/`へtranscript
  パース方式を採用した経緯を記録）→ plans/worklog削除→Draft解除。

## 判断が分かれるポイント

- PostToolUseの`if`フィールドが`PowerShell`ツールに対しても`Bash`同様に効くかは公式ドキュメントに
  明記が無く未検証（`Bash`側の`git *`サブコマンド単位マッチは明記あり）。効かない場合はPowerShellツール経由の
  `git push`ではレポートが発火せず、次回の対象トリガーまで繰り越されるだけ（データロスは無い設計）。

## 未解決の質問

## 守るべき条件・触ってはいけない範囲

- `.claude/hooks/*.ps1`は新規作成時、**BOM付きUTF-8で保存**すること（BOM無しだとWindows PowerShell 5.1で
  パースエラーになる。実機で確認済み。`.claude/rules/powershell-encoding.md`参照）。
