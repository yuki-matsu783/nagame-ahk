<#
    Claude Code PostToolUse hook（git push検知）。
    設計: plans/groovy-zooming-balloon.md（issue #15）。実装完了後は
    dev-tools/docs/spec/issue-mr-workflow.md へ反映する。

    .claude/settings.json 側で matcher: "Bash|PowerShell" と、各エントリの if フィールド
    （"Bash(git push*)" / "PowerShell(git push*)"）によって、tool_input のコマンドが
    git push を含む場合のみ起動される（マッチしなければClaude Code側でプロセスが起動されず、
    通常のBash/PowerShell利用への性能影響は無い）。if フィルタはベストエフォートのため、
    本スクリプト側でも念のため command 文字列を正規表現で再チェックする。

    stop-usage-record.ps1 が `.claude/usage-state/<branch>.json` の `sinceLastPush` に
    積み上げた「前回push以降の使用量」を読み、MRへ新規コメントとして投稿する（レビューではない
    通常コメントのため、レビュー合否判定には影響しない）。投稿に成功したら `sinceLastPush` を
    リセットする。失敗時は状態を変更せず握りつぶす（次のpush時に繰り越されるだけで、
    git push自体をブロックしない）。

    注意（文字コード）: .claude/hooks/session-start.ps1 と同じ理由により、コンソールの
    入出力エンコーディングをUTF-8へ明示的に切り替える（詳細: .claude/rules/powershell-encoding.md）。
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# stop-usage-record.ps1 と同じ変換ヘルパー（各hookスクリプトは独立プロセスとして起動されるため、
# 共有モジュール化はせず自己完結させている。既存のsession-start.ps1と同じ方針）
function ConvertTo-HashtableDeep {
    param($InputObject)
    if ($null -eq $InputObject) { return @{} }
    $ht = @{}
    foreach ($p in $InputObject.PSObject.Properties) {
        if ($p.Value -is [System.Management.Automation.PSCustomObject]) {
            $ht[$p.Name] = ConvertTo-HashtableDeep -InputObject $p.Value
        } else {
            $ht[$p.Name] = $p.Value
        }
    }
    $ht
}

$raw = [Console]::In.ReadToEnd()
$hookInput = $null
try {
    if ($raw) { $hookInput = $raw | ConvertFrom-Json }
} catch {
    exit 0
}

if (-not $hookInput) { exit 0 }

# サブエージェント内実行では何もしない（SessionStart/Stop hookと同じガード。並行書き込みによる
# 状態ファイル競合を避ける意味もある）
if ($hookInput.PSObject.Properties.Name -contains "agent_id" -and $hookInput.agent_id) {
    exit 0
}

if (-not $env:CLAUDE_PROJECT_DIR) { exit 0 }

$toolName = $hookInput.tool_name
if ($toolName -ne 'Bash' -and $toolName -ne 'PowerShell') { exit 0 }

$command = $hookInput.tool_input.command
if (-not $command -or ($command -notmatch '(?i)git\s+push')) { exit 0 }

try {
    Set-Location $env:CLAUDE_PROJECT_DIR
    . (Join-Path $env:CLAUDE_PROJECT_DIR "dev-tools\src\vcs\Provider.ps1")

    $branch = (git branch --show-current 2>$null)
    $config = Get-WorkflowConfig
    if (-not $branch -or $branch -eq $config.defaultBaseBranch) { exit 0 }

    $stateDir = Join-Path (Get-RepoRoot) ".claude\usage-state"
    $safeBranch = ($branch -replace '[^a-zA-Z0-9_-]', '_')
    $stateFile = Join-Path $stateDir "$safeBranch.json"
    if (-not (Test-Path $stateFile)) { exit 0 }

    $state = ConvertTo-HashtableDeep -InputObject (Get-Content -Raw -Path $stateFile | ConvertFrom-Json)
    if (-not $state.ContainsKey('sinceLastPush')) { exit 0 }
    $usage = $state.sinceLastPush

    # 合計が0なら投稿しない（初回push・使用量が積み上がっていないpush対策）
    $total = 0
    if ($usage.tokensByModel) {
        foreach ($m in $usage.tokensByModel.Values) {
            $total += [int]$m.input + [int]$m.output + [int]$m.cacheCreate + [int]$m.cacheRead
        }
    }
    if ($total -eq 0) { exit 0 }

    $mr = Get-MrForBranch -Branch $branch
    if (-not $mr) { exit 0 }

    # --- コメント本文の組み立て ---
    $lines = @()
    $lines += "## 🤖 セッション使用量レポート（自動投稿・前回pushからの差分）"
    $lines += ""
    $lines += "> このコメントはClaude Codeによる自動投稿です。**レビューの合否判定には使用しないでください。**"
    $lines += ""
    $lines += "- ブランチ: $branch"
    $lines += "- 対象ターン数: $([int]$usage.turns)"
    $lines += ""
    $lines += "| モデル | Input | Output | Cache Write | Cache Read |"
    $lines += "|---|---:|---:|---:|---:|"
    foreach ($model in ($usage.tokensByModel.Keys | Sort-Object)) {
        $m = $usage.tokensByModel[$model]
        $lines += "| $model | {0:N0} | {1:N0} | {2:N0} | {3:N0} |" -f [int]$m.input, [int]$m.output, [int]$m.cacheCreate, [int]$m.cacheRead
    }
    $lines += ""
    if ($usage.toolCalls -and $usage.toolCalls.Count -gt 0) {
        $toolSummary = ($usage.toolCalls.Keys | Sort-Object | ForEach-Object { "$($_): $([int]$usage.toolCalls[$_])" }) -join ", "
        $lines += "**ツール実行回数**: $toolSummary"
        $lines += ""
    }
    $lines += "---"
    $lines += "Claude Codeより: 自動投稿（stop-usage-record.ps1 / post-push-usage-report.ps1 による集計。"
    $lines += "transcriptの非公開フォーマットに依存したベストエフォートの集計のため、目安として扱ってください）"

    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tmpFile -Value ($lines -join "`n") -Encoding UTF8
        Add-MrComment -MrNumber $mr.Number -BodyFile $tmpFile

        # 投稿成功時のみ sinceLastPush をリセットする（失敗時は次回pushへ繰り越す）
        $state.sinceLastPush = @{ tokensByModel = @{}; toolCalls = @{}; turns = 0 }
        $state.lastPostedAt = (Get-Date).ToString("o")
        $state | ConvertTo-Json -Depth 10 | Set-Content -Path $stateFile
    } finally {
        Remove-Item -Path $tmpFile -ErrorAction SilentlyContinue
    }
} catch {
    # 投稿失敗はgit push自体をブロックしない（状態は変更せず次回pushへ繰り越す）
}

exit 0
