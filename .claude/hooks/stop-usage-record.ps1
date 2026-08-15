<#
    Claude Code Stop hook。
    設計: plans/groovy-zooming-balloon.md（issue #15）。実装完了後は
    dev-tools/docs/spec/issue-mr-workflow.md へ反映する。

    Claudeが1ターンの応答を終える（Stop）たびに発火し、そのセッションのtranscript_path
    （JSONL）からモデル別トークン数・ツール呼び出し回数を集計し、前回このフックが記録した
    セッション内累計との差分を、ブランチ単位のローカル状態ファイル（.claude/usage-state/<branch>.json）
    の `sinceLastPush` へ加算する。実際にMRへコメント投稿するのは post-push-usage-report.ps1
    （PostToolUse, git push検知時）側の責務。

    注意: transcript_path が指すJSONLの形式はClaude Code非公開の内部フォーマットであり、
    将来のバージョンで変更されうる（公式ドキュメントに明記）。他に取得手段が無いためベストエフォートで
    パースし、失敗しても握りつぶしてexit 0する（トークン集計の失敗でセッション進行を妨げない）。

    注意: SessionStart hook同様、サブエージェント内実行では何もしない（agent_idの有無で判定）。

    注意（文字コード）: .claude/hooks/session-start.ps1 と同じ理由により、コンソールの
    入出力エンコーディングをUTF-8へ明示的に切り替える（詳細: .claude/rules/powershell-encoding.md）。
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# JSONをネストしたHashtableへ変換する（Windows PowerShell 5.1の ConvertFrom-Json は
# -AsHashtable を持たないため、動的キー（モデル名・ツール名）を扱うために自前で変換する）
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

function Get-ZeroTokenBucket {
    @{ input = 0; output = 0; cacheCreate = 0; cacheRead = 0 }
}

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

    $branch = (git branch --show-current 2>$null)
    $config = Get-WorkflowConfig
    if (-not $branch -or $branch -eq $config.defaultBaseBranch) {
        exit 0
    }

    $sessionId = $hookInput.session_id
    $transcriptPath = $hookInput.transcript_path
    if (-not $sessionId -or -not $transcriptPath -or -not (Test-Path $transcriptPath)) {
        exit 0
    }

    # --- transcript JSONLを集計（ベストエフォート。1行ずつパースし壊れた行はスキップ） ---
    $currentTokens = @{}
    $currentTools = @{}

    foreach ($line in (Get-Content -Path $transcriptPath)) {
        if (-not $line) { continue }
        $entry = $null
        try { $entry = $line | ConvertFrom-Json } catch { continue }
        if (-not $entry -or $entry.type -ne 'assistant' -or -not $entry.message) { continue }

        $msg = $entry.message
        if ($msg.usage) {
            $model = if ($msg.model) { $msg.model } else { 'unknown' }
            if (-not $currentTokens.ContainsKey($model)) { $currentTokens[$model] = Get-ZeroTokenBucket }
            $u = $msg.usage
            if ($u.input_tokens) { $currentTokens[$model].input += [int]$u.input_tokens }
            if ($u.output_tokens) { $currentTokens[$model].output += [int]$u.output_tokens }
            if ($u.cache_creation_input_tokens) { $currentTokens[$model].cacheCreate += [int]$u.cache_creation_input_tokens }
            if ($u.cache_read_input_tokens) { $currentTokens[$model].cacheRead += [int]$u.cache_read_input_tokens }
        }

        if ($msg.content) {
            foreach ($block in @($msg.content)) {
                if ($block.type -eq 'tool_use' -and $block.name) {
                    if (-not $currentTools.ContainsKey($block.name)) { $currentTools[$block.name] = 0 }
                    $currentTools[$block.name] += 1
                }
            }
        }
    }

    # --- 状態ファイルの読み込み ---
    $stateDir = Join-Path (Get-RepoRoot) ".claude\usage-state"
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    $safeBranch = ($branch -replace '[^a-zA-Z0-9_-]', '_')
    $stateFile = Join-Path $stateDir "$safeBranch.json"

    $state = if (Test-Path $stateFile) {
        ConvertTo-HashtableDeep -InputObject (Get-Content -Raw -Path $stateFile | ConvertFrom-Json)
    } else {
        @{}
    }
    if (-not $state.ContainsKey('sessions')) { $state['sessions'] = @{} }
    if (-not $state.ContainsKey('sinceLastPush')) {
        $state['sinceLastPush'] = @{ tokensByModel = @{}; toolCalls = @{}; turns = 0 }
    }
    if (-not $state.sessions.ContainsKey($sessionId)) {
        $state.sessions[$sessionId] = @{ lastTokens = @{}; lastTools = @{} }
    }
    $prevTokens = $state.sessions[$sessionId].lastTokens
    $prevTools = $state.sessions[$sessionId].lastTools

    # --- 前回このセッションで記録した累計との差分を sinceLastPush へ加算 ---
    foreach ($model in $currentTokens.Keys) {
        $prev = if ($prevTokens.ContainsKey($model)) { $prevTokens[$model] } else { Get-ZeroTokenBucket }
        if (-not $state.sinceLastPush.tokensByModel.ContainsKey($model)) {
            $state.sinceLastPush.tokensByModel[$model] = Get-ZeroTokenBucket
        }
        foreach ($field in @('input', 'output', 'cacheCreate', 'cacheRead')) {
            $delta = [Math]::Max(0, [int]$currentTokens[$model][$field] - [int]$prev[$field])
            $state.sinceLastPush.tokensByModel[$model][$field] = [int]$state.sinceLastPush.tokensByModel[$model][$field] + $delta
        }
    }

    foreach ($tool in $currentTools.Keys) {
        $prevCount = if ($prevTools.ContainsKey($tool)) { [int]$prevTools[$tool] } else { 0 }
        $delta = [Math]::Max(0, [int]$currentTools[$tool] - $prevCount)
        if (-not $state.sinceLastPush.toolCalls.ContainsKey($tool)) { $state.sinceLastPush.toolCalls[$tool] = 0 }
        $state.sinceLastPush.toolCalls[$tool] = [int]$state.sinceLastPush.toolCalls[$tool] + $delta
    }

    $state.sinceLastPush.turns = [int]$state.sinceLastPush.turns + 1
    $state.sessions[$sessionId].lastTokens = $currentTokens
    $state.sessions[$sessionId].lastTools = $currentTools
    $state.branch = $branch

    $state | ConvertTo-Json -Depth 10 | Set-Content -Path $stateFile
} catch {
    # トークン集計・状態保存の失敗はセッション進行を妨げない（握りつぶす）
}

exit 0
