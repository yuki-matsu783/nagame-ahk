<#
    GitLab固有の処理（`glab` CLIラッパー）。
    設計: dev-tools/docs/spec/issue-mr-workflow.md

    単体でdot-sourceせず、必ず dev-tools/src/vcs/Provider.ps1 経由で使う
    （Provider.ps1 が Get-Provider の判定結果に応じてこのファイルの関数へディスパッチする）。
    前提: `glab` CLIがインストール・認証済み（`glab auth login`）であること。

    【未検証】このリポジトリのremoteはGitHubのみのため、以下は`glab`のドキュメントを元にした
    実装であり実機での動作確認ができていない（dev-tools/docs/spec/issue-mr-workflow.md の
    「未決定事項・懸念点」参照）。GitLabリポジトリで実際に使う前に動作確認すること。
#>

$ErrorActionPreference = "Stop"

function GitLab-GetIssue {
    param([Parameter(Mandatory)][int]$Number)

    $issue = glab issue view $Number --output json | ConvertFrom-Json
    [PSCustomObject]@{
        Number = $issue.iid
        Title  = $issue.title
        Body   = $issue.description
        Url    = $issue.web_url
        Slug   = ConvertTo-Slug -Text $issue.title
    }
}

function GitLab-NewDraftMergeRequest {
    param(
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$BaseBranch,
        [Parameter(Mandatory)][string]$Title
    )

    $description = "Closes #$IssueNumber`n`n(plan作成中。/issue-mr-flow describe で更新する)"
    glab mr create --draft --source-branch $Branch --target-branch $BaseBranch `
        --title $Title --description $description --yes | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # baseとの差分（コミット）が無いブランチでは `glab mr create` が失敗する既知の制約
        # （dev-tools/docs/spec/issue-mr-workflow.md参照）。空コミットで解消して1回だけリトライする。
        # 【未検証】このリポジトリのremoteはGitHubのみのためGitLab側の実機確認はできていない。
        Add-EmptyCommitForDraftMr
        glab mr create --draft --source-branch $Branch --target-branch $BaseBranch `
            --title $Title --description $description --yes | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "glab mr create に失敗しました（空コミットでのリトライ後も失敗）"
        }
    }
    [int](glab mr view $Branch --output json --jq ".iid")
}

# discussion内のnoteをまとめて返す。既定では resolved: false（未解決）のnoteのみを対象とし、
# 対応済み（解決済み）は機械的に除外する。-IncludeResolved 指定時は解決済みも含めた全件を返す。
# 個人メモ（individual_note）等 resolvable でないnoteは常に含める。
function GitLab-GetMrUnresolvedComments {
    param(
        [Parameter(Mandatory)][int]$MrNumber,
        [switch]$IncludeResolved
    )

    $discussions = glab api "projects/:id/merge_requests/$MrNumber/discussions" | ConvertFrom-Json

    $lines = @()
    foreach ($discussion in $discussions) {
        foreach ($note in $discussion.notes) {
            $isResolved = $note.resolvable -and $note.resolved
            if ($isResolved -and -not $IncludeResolved) { continue }
            $status = if ($isResolved) { "resolved" } else { "unresolved" }
            $lines += "[$status threadId=$($discussion.id)] $($note.author.username): $($note.body)"
        }
    }

    $lines -join "`n`n"
}

# 指定したdiscussion（スレッド）に対応内容を返信する。スレッドの解決（resolved）はレビュアー側の
# 操作のためここでは行わない。【未検証】このリポジトリのremoteはGitHubのみのため実機確認できていない。
function GitLab-AddMrThreadReply {
    param(
        [Parameter(Mandatory)][int]$MrNumber,
        [Parameter(Mandatory)][string]$ThreadId,
        [Parameter(Mandatory)][string]$ReplyBody
    )

    glab api "projects/:id/merge_requests/$MrNumber/discussions/$ThreadId/notes" -X POST -f "body=$ReplyBody" | Out-Null
}

# 指定ブランチに紐づくMR（無ければ $null）を返す。途中引き継ぎ対応（resume）と、
# comments/describeサブコマンドでの「現在のブランチのMR番号取得」の共通実装として使う。
# 【未検証】このリポジトリのremoteはGitHubのみのため実機確認できていない。
function GitLab-GetMrForBranch {
    param([Parameter(Mandatory)][string]$Branch)

    $json = glab mr view $Branch --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }

    $mr = $json | ConvertFrom-Json
    [PSCustomObject]@{
        Number  = $mr.iid
        Url     = $mr.web_url
        IsDraft = $mr.work_in_progress
        Title   = $mr.title
    }
}

function GitLab-SetMrDescription {
    param(
        [Parameter(Mandatory)][int]$MrNumber,
        [Parameter(Mandatory)][string]$BodyFile
    )
    $description = Get-Content -Raw -Path $BodyFile
    glab mr update $MrNumber --description $description | Out-Null
}

# MRへ新規コメントを1件投稿する（スレッド返信・レビューではない通常コメント）。
# 【未検証】このリポジトリのremoteはGitHubのみのため実機確認できていない。
function GitLab-AddMrComment {
    param(
        [Parameter(Mandatory)][int]$MrNumber,
        [Parameter(Mandatory)][string]$BodyFile
    )
    $body = Get-Content -Raw -Path $BodyFile
    glab mr note $MrNumber --message $body | Out-Null
}
