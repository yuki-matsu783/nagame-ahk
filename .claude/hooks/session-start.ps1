<#
    Claude Code SessionStart hook。
    設計: dev-tools/docs/spec/issue-mr-workflow.md「セッション開始時の自動コンテキスト注入」

    セッション開始・resume・clear時（.claude/settings.jsonのmatcher参照）に、現在チェックアウトされて
    いるブランチに紐づくissue/MRの状態を取得し、追加コンテキストとしてコンテキストに注入する。

    前提: `gh` CLIがインストール・認証済みであること（未認証・未インストールの場合は非侵襲的に
    失敗メッセージのみ返し、セッション開始はブロックしない）。

    注意: SessionStart hookはTask tool経由のサブエージェント内でも発火する（公式ドキュメント確認済み）。
    サブエージェント実行時はstdinのJSONに`agent_id`が含まれるため、これを見て即終了する
    （メインセッションのコンテキストのみを汚す設計）。

    注意（文字コード）: Windows PowerShell 5.1は既定でシステムのANSI/OEMコードページ
    （日本語Windowsではcp932）でコンソール入出力を扱う。これに合わせると、UTF-8で出力する
    `gh`コマンドの結果（issue本文の日本語等）を誤って解釈してしまい、`ConvertFrom-Json`が
    構文エラーになる、またはClaude Codeへ返す追加コンテキストが文字化けする、といった問題が
    実機で発生することを確認済み。そのため起動直後にコンソールの入出力エンコーディングを
    明示的にUTF-8へ切り替える。
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

function Write-AdditionalContext {
    param([Parameter(Mandatory)][string]$Text)
    $output = [PSCustomObject]@{
        hookSpecificOutput = [PSCustomObject]@{
            hookEventName    = "SessionStart"
            additionalContext = $Text
        }
    }
    $output | ConvertTo-Json -Depth 5 -Compress
}

$raw = [Console]::In.ReadToEnd()
$hookInput = $null
try {
    if ($raw) { $hookInput = $raw | ConvertFrom-Json }
} catch {
    # stdinが壊れていても後続の判定に影響しないよう、パース失敗はそのまま無視する
}

# サブエージェント内実行では何もしない（agent_idはサブエージェント呼び出し時のみ付与される）
if ($hookInput -and $hookInput.PSObject.Properties.Name -contains "agent_id" -and $hookInput.agent_id) {
    exit 0
}

if (-not $env:CLAUDE_PROJECT_DIR) {
    exit 0
}

try {
    Set-Location $env:CLAUDE_PROJECT_DIR
    . (Join-Path $env:CLAUDE_PROJECT_DIR "dev-tools\src\vcs\Provider.ps1")

    $branch = (git branch --show-current 2>$null)
    $config = Get-WorkflowConfig
    if (-not $branch -or $branch -eq $config.defaultBaseBranch) {
        # 作業ブランチ未チェックアウト（mainブランチ上）のときは注入しない
        exit 0
    }

    $lines = @("## 現在の作業ブランチ情報 (SessionStart hook)", "- ブランチ: $branch")

    $issueNumber = Get-IssueNumberFromBranch -Branch $branch
    if ($issueNumber) {
        $issue = Get-Issue -Number $issueNumber
        $lines += "- issue: #$($issue.Number) $($issue.Title) ($($issue.Url))"
    } else {
        $lines += "- issue: 特定できず（ブランチ名がissue命名規則に一致しません）"
    }

    $mr = Get-MrForBranch -Branch $branch
    if ($mr) {
        $draftLabel = if ($mr.IsDraft) { "[Draft]" } else { "[Ready]" }
        $lines += "- PR: #$($mr.Number) $($mr.Title) $draftLabel ($($mr.Url))"

        try {
            $commentsText = Get-MrUnresolvedComments -MrNumber $mr.Number
            $ids = [regex]::Matches($commentsText, '\[review unresolved threadId=(\S+)') |
                ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
            $lines += "- 未解決レビューコメント: $($ids.Count)件"
        } catch {
            $lines += "- 未解決レビューコメント: 取得に失敗しました ($($_.Exception.Message))"
        }
    } else {
        $lines += "- PR: なし"
    }

    Write-AdditionalContext -Text ($lines -join "`n")
} catch {
    Write-AdditionalContext -Text "(issue/MR情報の取得に失敗しました: $($_.Exception.Message))"
}

exit 0
