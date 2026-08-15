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
  - `.claude/hooks/lib/UsageTracking.ps1`（共有ライブラリ）: `Sync-UsageState`が集計本体。
    `entry.gitBranch -eq $Branch` でフィルタして集計する（複数ブランチを跨いだ際の他ブランチ分混入
    バグを修正済み。実データで452,144トークン分の混入を確認・解消した）。トークン数・ツール実行回数・
    assistant応答回数（旧称「ターン数」）のいずれも「transcriptとの差分をsinceLastPushへ加算」する
    同じ方式で算出する。
  - `.claude/hooks/post-push-usage-report.ps1`（PostToolUse hook, git push検知）**のみ**で完結する
    構成にした。投稿前に自分で`Sync-UsageState`を呼んで最新化してから投稿・リセットする。
  - **`Stop` hook（`stop-usage-record.ps1`）は廃止・削除済み**。当初はターン数カウント専用に
    残していたが、その仕組み自体が「Stop未発火のpushで過少カウントされる」という、トークン集計で
    直したのと同じ不具合を抱えていたため（実際に「対象ターン数: 0」という不整合な投稿を確認した）、
    PostToolUse側のtranscript差分方式に統合し、Stop hookごと削除した。`.claude/settings.json`の
    `hooks.Stop`設定も削除済み。
  - `.claude/settings.json`にPostToolUseのhook登録のみ追加（Stopは登録しない）。

## 次回やること

- **hookの実地E2E確認は完了済み**（2026-08-16、複数回実施、うち1回は手動実行を挟まない本番動作）。
  最終構成（PostToolUseのみ、Stopなし）でのドライラン確認で、assistant応答回数が0にならず
  正しく計算されることを確認済み（テスト投稿は削除済み）。**次回のcommit・pushで、Stop無しの
  最終構成でも本番動作として正しく発火するか、念のため再確認する**（settings.jsonの変更は
  同一セッション内で即時反映されることは既に確認済みのため、大きな懸念は無い）。
- issue-mr-flowの残りステップを継続: 上記commit・push→MRレビュー→plans/worklog削除→Draft解除。

## 判断が分かれるポイント

- PostToolUseの`if`フィールドが`PowerShell`ツールに対しても`Bash`同様に効くかは公式ドキュメントに
  明記が無く未検証（`Bash`側の`git *`サブコマンド単位マッチは明記あり）。効かない場合はPowerShellツール経由の
  `git push`ではレポートが発火せず、次回の対象トリガーまで繰り越されるだけ（データロスは無い設計）。

## 未解決の質問

## 守るべき条件・触ってはいけない範囲

- `.claude/hooks/*.ps1`は新規作成時、**BOM付きUTF-8で保存**すること（BOM無しだとWindows PowerShell 5.1で
  パースエラーになる。実機で確認済み。`.claude/rules/powershell-encoding.md`参照）。
