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

- **hookの実地E2E確認が未完了**。今回commit・push直後にPR #17のコメントを確認したが投稿されなかった。
  ただし原因は特定できていない可能性が高い理由がある: このpushを行った時点で、当該ターンの`Stop`イベントが
  まだ発火していなかった（Stopは応答ターン終了時に発火するため）ので、`.claude/usage-state/feature-15-mr.json`
  が未作成＝蓄積0件であり、`post-push-usage-report.ps1`が「投稿しない」を選ぶのは設計通りの可能性が高い。
  次回、何かしらの応答ターンが1回でも完了した**後**に`git push`を行い、実際にMRへコメントが投稿されるかを
  確認すること。投稿されない場合は、`.claude/settings.json`の変更が同一セッション内で即時反映されるか
  （＝再起動しないとhook登録が有効化されないのではないか）を疑うこと。
- 上記が確認できたら、issue-mr-flowの残りステップを継続: MRレビュー→設計反映
  （`dev-tools/docs/spec/issue-mr-workflow.md`へ「Draft PR空コミット自動リトライ」「セッション使用量
  レポート」の節を追加、`docs/ddr/`へtranscriptパース方式を採用した経緯を記録）→ plans/worklog削除→
  Draft解除。

## 判断が分かれるポイント

- PostToolUseの`if`フィールドが`PowerShell`ツールに対しても`Bash`同様に効くかは公式ドキュメントに
  明記が無く未検証（`Bash`側の`git *`サブコマンド単位マッチは明記あり）。効かない場合はPowerShellツール経由の
  `git push`ではレポートが発火せず、次回の対象トリガーまで繰り越されるだけ（データロスは無い設計）。

## 未解決の質問

## 守るべき条件・触ってはいけない範囲

- `.claude/hooks/*.ps1`は新規作成時、**BOM付きUTF-8で保存**すること（BOM無しだとWindows PowerShell 5.1で
  パースエラーになる。実機で確認済み。`.claude/rules/powershell-encoding.md`参照）。
