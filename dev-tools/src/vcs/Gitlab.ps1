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
    [int](glab mr view $Branch --output json --jq ".iid")
}

# resolved: false のdiscussion内のnoteをまとめて返す。個人メモ（individual_note）等
# resolvable でないnoteは常に含める。
function GitLab-GetMrUnresolvedComments {
    param([Parameter(Mandatory)][int]$MrNumber)

    $discussions = glab api "projects/:id/merge_requests/$MrNumber/discussions" | ConvertFrom-Json

    $lines = @()
    foreach ($discussion in $discussions) {
        foreach ($note in $discussion.notes) {
            if ($note.resolvable -and $note.resolved) { continue }
            $lines += "[$($note.author.username)]: $($note.body)"
        }
    }

    $lines -join "`n`n"
}

function GitLab-SetMrDescription {
    param(
        [Parameter(Mandatory)][int]$MrNumber,
        [Parameter(Mandatory)][string]$BodyFile
    )
    $description = Get-Content -Raw -Path $BodyFile
    glab mr update $MrNumber --description $description | Out-Null
}
