<#
    stop-usage-record.ps1 / post-push-usage-report.ps1 共有ロジック。
    設計: plans/groovy-zooming-balloon.md（issue #15、追加計画セクション）。実装完了後は
    dev-tools/docs/spec/issue-mr-workflow.md へ反映する。

    単体でdot-sourceせず、両hookスクリプトから `. (Join-Path $PSScriptRoot "lib\UsageTracking.ps1")`
    の形でdot-sourceして使う。

    注意: transcript_path が指すJSONLの形式はClaude Code非公開の内部フォーマットであり、
    将来のバージョンで変更されうる（公式ドキュメントに明記）。他に取得手段が無いためベストエフォートで
    パースする。呼び出し元（各hookスクリプト）側でtry/catchして握りつぶす想定で、本ファイル内では
    集計ロジックの例外を意図的に外へ伝播させる。

    注意: 各assistantメッセージには実行時のgitBranchが記録されている（実機確認済み）。これで
    フィルタしない場合、同一セッション内で複数ブランチを跨いだ際に他ブランチ分のトークンが
    混入するため、必ず `entry.gitBranch -eq $Branch` で絞り込む。
#>

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

# 指定ブランチ・セッションのtranscriptを集計し、状態ファイル（.claude/usage-state/<branch>.json）の
# sinceLastPush へ「前回このセッションで記録した累計との差分」を加算して保存する。更新後の状態を
# hashtableで返す。呼び出し元（Stop/PostToolUse双方）が同じロジックを共有できるようにするための関数。
#
# -IncrementTurn 指定時のみ sinceLastPush.turns を+1する（1ターン完了を表すのはStopの時だけであり、
# PostToolUse側でのpush時同期では加算しない）。
function Sync-UsageState {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$TranscriptPath,
        [switch]$IncrementTurn
    )

    if (-not (Test-Path $TranscriptPath)) { return $null }

    # --- transcript JSONLを集計（ベストエフォート。1行ずつパースし壊れた行はスキップ） ---
    # 実行時点のgitBranchが記録されているエントリのみを対象にする（他ブランチ分の混入防止）。
    $currentTokens = @{}
    $currentTools = @{}

    foreach ($line in (Get-Content -Path $TranscriptPath)) {
        if (-not $line) { continue }
        $entry = $null
        try { $entry = $line | ConvertFrom-Json } catch { continue }
        if (-not $entry -or $entry.type -ne 'assistant' -or -not $entry.message) { continue }
        if ($entry.gitBranch -ne $Branch) { continue }

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
    $stateDir = Join-Path $RepoRoot ".claude\usage-state"
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    $safeBranch = ($Branch -replace '[^a-zA-Z0-9_-]', '_')
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
    if (-not $state.sessions.ContainsKey($SessionId)) {
        $state.sessions[$SessionId] = @{ lastTokens = @{}; lastTools = @{} }
    }
    $prevTokens = $state.sessions[$SessionId].lastTokens
    $prevTools = $state.sessions[$SessionId].lastTools

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

    if ($IncrementTurn) {
        $state.sinceLastPush.turns = [int]$state.sinceLastPush.turns + 1
    }
    $state.sessions[$SessionId].lastTokens = $currentTokens
    $state.sessions[$SessionId].lastTools = $currentTools
    $state.branch = $Branch

    $state | ConvertTo-Json -Depth 10 | Set-Content -Path $stateFile
    $state
}
