<#
    issue駆動MRワークフロー支援の共通レイヤー。
    設計: dev-tools/docs/spec/issue-mr-workflow.md

    GitHub/GitLabの差異を吸収する共通インターフェースを提供する。呼び出し側
    （.claude/skills/issue-mr-flow/SKILL.md 等）はこのファイルをdot-sourceして使う。
        . dev-tools\src\vcs\Provider.ps1

    プロバイダ非依存の関数（New-IssueBranch, Sync-Branch）はここに実装し、
    プロバイダ依存の関数（Get-Issue, New-DraftMergeRequest, Get-MrUnresolvedComments,
    Set-MrDescription）は Get-Provider の判定結果に応じて Github.ps1 / Gitlab.ps1 の
    対応関数（GitHub-Xxx / GitLab-Xxx）へディスパッチする。

    注意（文字コード）: Windows PowerShell 5.1は既定でシステムのANSI/OEMコードページ
    （日本語Windowsではcp932）でコンソール入出力・`Get-Content`等のファイルI/Oを扱う。これに合わせると、
    UTF-8でやり取りする`gh`/`glab`コマンドの結果（issue本文の日本語等）を誤って解釈したり、
    BOM無しUTF-8のテキストファイルを読み込んだ内容が文字化けしたまま`gh api graphql`等へ渡って
    しまったりする不具合が実機で発生することを確認済み（issue #5対応時）。呼び出し側が
    `-Encoding UTF8`を書き忘れても安全なように、dot-source直後に以下2点をこのファイル側で
    強制する（詳細: `.claude/rules/powershell-encoding.md`）。
    - コンソールの入出力エンコーディングをUTF-8へ切り替える（外部コマンドとのI/Oを保護）。
    - `Get-Content`/`Set-Content`/`Add-Content`/`Out-File`の既定エンコーディングをUTF-8へ切り替える
      （`$PSDefaultParameterValues`。ワイルドカード`'*:Encoding'`は他コマンドレットの`-Encoding`
      パラメータ定義と衝突し警告が出たため、対象コマンドレットを個別に指定する）。
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Get-Content:Encoding'] = 'UTF8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'UTF8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'UTF8'
$PSDefaultParameterValues['Out-File:Encoding'] = 'UTF8'

. (Join-Path $PSScriptRoot "Github.ps1")
. (Join-Path $PSScriptRoot "Gitlab.ps1")

# `.mrworkflow.json` が存在しない場合のデフォルト値（nagame-ahk向けの初期値と同一。
# dev-tools/docs/spec/issue-mr-workflow.md の「設定項目」参照）
$script:DefaultWorkflowConfig = @{
    branchPrefixTemplate = "feature-{issue}-{slug}"
    defaultBaseBranch    = "main"
    plansDir             = "plans"
    worklogDir           = "worklog"
    specDirs             = @("docs/spec", "dev-tools/docs/spec")
    ddrDirs              = @("docs/ddr", "dev-tools/docs/ddr")
}

# issue本文に標準として求める見出し（dev-tools/docs/spec/issue-mr-workflow.md
# 「Issueテンプレート標準化」参照。.github/ISSUE_TEMPLATE/task.md, .gitlab/issue_templates/task.md と対応）
$script:RequiredIssueSections = @("目的", "現状", "期待する動作", "受け入れ条件")

function Get-RepoRoot {
    (git rev-parse --show-toplevel) -replace '/', '\'
}

function Get-WorkflowConfig {
    $configPath = Join-Path (Get-RepoRoot) ".mrworkflow.json"
    if (-not (Test-Path $configPath)) {
        return [PSCustomObject]$script:DefaultWorkflowConfig
    }
    Get-Content -Raw -Path $configPath | ConvertFrom-Json
}

# issueタイトル等を英数字・ハイフンのスラッグへ簡易変換する（ブランチ名・ファイル名に使う）
function ConvertTo-Slug {
    param([Parameter(Mandatory)][string]$Text)
    $slug = $Text.ToLowerInvariant()
    $slug = [regex]::Replace($slug, '[^a-z0-9]+', '-')
    $slug = $slug.Trim('-')
    if ($slug.Length -gt 50) { $slug = $slug.Substring(0, 50).Trim('-') }
    if (-not $slug) { $slug = "issue" }
    $slug
}

# issue本文に標準4見出し（目的・現状・期待する動作・受け入れ条件）が揃っているか確認し、
# 欠けている見出し名を配列で返す（揃っていれば空配列）。プロバイダ非依存。
function Test-IssueSections {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Body)

    $missing = @()
    foreach ($section in $script:RequiredIssueSections) {
        $pattern = "(?m)^##\s*" + [regex]::Escape($section) + "\s*$"
        if ($Body -notmatch $pattern) {
            $missing += $section
        }
    }
    $missing
}

# `git remote get-url origin` のホスト名からプロバイダを判定する
function Get-Provider {
    $url = git remote get-url origin
    if ($url -match 'github\.com') { return 'github' }
    if ($url -match 'gitlab') { return 'gitlab' }
    throw "サポート対象外のリモートです（GitHub/GitLabのみ対応）: $url"
}

function Get-Issue {
    param([Parameter(Mandatory)][int]$Number)
    switch (Get-Provider) {
        'github' { GitHub-GetIssue -Number $Number }
        'gitlab' { GitLab-GetIssue -Number $Number }
    }
}

function New-DraftMergeRequest {
    param(
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$Branch,
        [string]$BaseBranch = (Get-WorkflowConfig).defaultBaseBranch,
        [Parameter(Mandatory)][string]$Title
    )
    switch (Get-Provider) {
        'github' { GitHub-NewDraftMergeRequest -IssueNumber $IssueNumber -Branch $Branch -BaseBranch $BaseBranch -Title $Title }
        'gitlab' { GitLab-NewDraftMergeRequest -IssueNumber $IssueNumber -Branch $Branch -BaseBranch $BaseBranch -Title $Title }
    }
}

function Get-MrUnresolvedComments {
    param(
        [Parameter(Mandatory)][int]$MrNumber,
        [switch]$IncludeResolved
    )
    switch (Get-Provider) {
        'github' { GitHub-GetMrUnresolvedComments -MrNumber $MrNumber -IncludeResolved:$IncludeResolved }
        'gitlab' { GitLab-GetMrUnresolvedComments -MrNumber $MrNumber -IncludeResolved:$IncludeResolved }
    }
}

# 指定したレビュースレッドに対応内容を返信する（スレッドの解決＝resolvedはレビュアー側の操作のため
# 行わない）。ThreadId は Get-MrUnresolvedComments の出力に含まれる threadId=... を使う。
function Add-MrThreadReply {
    param(
        [Parameter(Mandatory)][int]$MrNumber,
        [Parameter(Mandatory)][string]$ThreadId,
        [Parameter(Mandatory)][string]$ReplyBody
    )
    switch (Get-Provider) {
        'github' { GitHub-AddMrThreadReply -MrNumber $MrNumber -ThreadId $ThreadId -ReplyBody $ReplyBody }
        'gitlab' { GitLab-AddMrThreadReply -MrNumber $MrNumber -ThreadId $ThreadId -ReplyBody $ReplyBody }
    }
}

function Get-MrForBranch {
    param([Parameter(Mandatory)][string]$Branch)
    switch (Get-Provider) {
        'github' { GitHub-GetMrForBranch -Branch $Branch }
        'gitlab' { GitLab-GetMrForBranch -Branch $Branch }
    }
}

function Set-MrDescription {
    param(
        [Parameter(Mandatory)][int]$MrNumber,
        [Parameter(Mandatory)][string]$BodyFile
    )
    switch (Get-Provider) {
        'github' { GitHub-SetMrDescription -MrNumber $MrNumber -BodyFile $BodyFile }
        'gitlab' { GitLab-SetMrDescription -MrNumber $MrNumber -BodyFile $BodyFile }
    }
}

# issue番号・スラッグから `.mrworkflow.json` の branchPrefixTemplate に沿ったブランチを作成しcheckout、
# リモートへpushする（ステップ3・4: 「issueからMRとブランチを作る」「作成したブランチをfetch, checkout」）。
function New-IssueBranch {
    param(
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$Title
    )
    $config = Get-WorkflowConfig
    $slug = ConvertTo-Slug -Text $Title
    $branch = $config.branchPrefixTemplate -replace '\{issue\}', $IssueNumber -replace '\{slug\}', $slug

    git fetch origin $config.defaultBaseBranch
    git switch -c $branch "origin/$($config.defaultBaseBranch)"
    git push -u origin $branch

    $branch
}

# 新しいセッションで作業を再開するとき用（ステップ4の再開版）。
# ローカルにブランチが無ければ origin から作成し、あれば最新化する。
function Sync-Branch {
    param([Parameter(Mandatory)][string]$Branch)

    git fetch origin

    $localExists = (git branch --list $Branch) -ne $null
    if ($localExists) {
        git checkout $Branch
        git pull --ff-only origin $Branch
    } else {
        git checkout -b $Branch "origin/$Branch"
    }
}

# ブランチ名を branchPrefixTemplate に照らしてissue番号を抽出する（途中引き継ぎ対応のresumeで使用）。
# {issue}/{slug} を記号を含まないプレースホルダに置換してから [regex]::Escape することで、
# テンプレートのリテラル部分（ハイフン等）だけを正しくエスケープしつつプレースホルダを
# 正規表現化する。マッチしなければ $null を返す。
function Get-IssueNumberFromBranch {
    param([string]$Branch = (git branch --show-current))

    $config = Get-WorkflowConfig
    $tokenized = $config.branchPrefixTemplate -replace '\{issue\}', 'ZZISSUEZZ' -replace '\{slug\}', 'ZZSLUGZZ'
    $pattern = [regex]::Escape($tokenized) -replace 'ZZISSUEZZ', '(?<issue>\d+)' -replace 'ZZSLUGZZ', '.+'

    if ($Branch -match "^$pattern`$") {
        [int]$Matches['issue']
    } else {
        $null
    }
}

# 現在のブランチ固有（<defaultBaseBranch> には無い）の plans/worklog ファイル一覧を返す
# （コミット済み差分＋作業ツリーの未コミット分をマージ・重複排除）。プロバイダ非依存。
function Get-BranchWorkFiles {
    $config = Get-WorkflowConfig
    $paths = @($config.plansDir, $config.worklogDir)

    $committed = git diff --name-only "origin/$($config.defaultBaseBranch)...HEAD" -- @paths
    $working = git status --porcelain -- @paths | ForEach-Object { $_.Substring(3).Trim() }

    @($committed) + @($working) | Where-Object { $_ } | Sort-Object -Unique
}
