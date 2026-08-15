<#
    Claude Code Stop hook。
    設計: plans/groovy-zooming-balloon.md（issue #15）。実装完了後は
    dev-tools/docs/spec/issue-mr-workflow.md へ反映する。

    Claudeが1ターンの応答を終える（Stop）たびに発火し、集計処理本体（.claude/hooks/lib/UsageTracking.ps1
    の Sync-UsageState）を呼んで、ブランチ単位のローカル状態ファイル（.claude/usage-state/<branch>.json）
    の `sinceLastPush` を更新する（このスクリプトでは `-IncrementTurn` を指定し、1ターン完了として
    turnsを+1する）。実際にMRへコメント投稿するのは post-push-usage-report.ps1
    （PostToolUse, git push検知時。そちらも同じSync-UsageStateを`-IncrementTurn`無しで呼び直す）側の責務。

    注意: transcript_path が指すJSONLの形式・gitBranchフィールドの扱いはClaude Code非公開の内部
    フォーマットに依存する（詳細はUsageTracking.ps1のコメント参照）。失敗しても握りつぶしてexit 0する
    （トークン集計の失敗でセッション進行を妨げない）。

    注意: SessionStart hook同様、サブエージェント内実行では何もしない（agent_idの有無で判定）。

    注意（文字コード）: .claude/hooks/session-start.ps1 と同じ理由により、コンソールの
    入出力エンコーディングをUTF-8へ明示的に切り替える（詳細: .claude/rules/powershell-encoding.md）。
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd()
$hookInput = $null
try {
    if ($raw) { $hookInput = $raw | ConvertFrom-Json }
} catch {
    # stdinが壊れていても後続に影響しないよう無視する
}

# サブエージェント内実行では何もしない（SessionStart hookと同じガード）
if ($hookInput -and $hookInput.PSObject.Properties.Name -contains "agent_id" -and $hookInput.agent_id) {
    exit 0
}

if (-not $env:CLAUDE_PROJECT_DIR) {
    exit 0
}

try {
    Set-Location $env:CLAUDE_PROJECT_DIR
    . (Join-Path $env:CLAUDE_PROJECT_DIR "dev-tools\src\vcs\Provider.ps1")
    . (Join-Path $env:CLAUDE_PROJECT_DIR ".claude\hooks\lib\UsageTracking.ps1")

    $branch = (git branch --show-current 2>$null)
    $config = Get-WorkflowConfig
    if (-not $branch -or $branch -eq $config.defaultBaseBranch) {
        exit 0
    }

    $sessionId = $hookInput.session_id
    $transcriptPath = $hookInput.transcript_path
    if (-not $sessionId -or -not $transcriptPath) {
        exit 0
    }

    Sync-UsageState -RepoRoot (Get-RepoRoot) -Branch $branch -SessionId $sessionId `
        -TranscriptPath $transcriptPath -IncrementTurn | Out-Null
} catch {
    # トークン集計・状態保存の失敗はセッション進行を妨げない（握りつぶす）
}

exit 0
