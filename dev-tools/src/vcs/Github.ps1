<#
    GitHub固有の処理（`gh` CLIラッパー）。
    設計: dev-tools/docs/spec/issue-mr-workflow.md

    単体でdot-sourceせず、必ず dev-tools/src/vcs/Provider.ps1 経由で使う
    （Provider.ps1 が Get-Provider の判定結果に応じてこのファイルの関数へディスパッチする）。
    前提: `gh` CLIがインストール・認証済み（`gh auth login`）であること。
#>

$ErrorActionPreference = "Stop"

function GitHub-GetIssue {
    param([Parameter(Mandatory)][int]$Number)

    $issue = gh issue view $Number --json number,title,body,url | ConvertFrom-Json
    [PSCustomObject]@{
        Number = $issue.number
        Title  = $issue.title
        Body   = $issue.body
        Url    = $issue.url
        Slug   = ConvertTo-Slug -Text $issue.title
    }
}

function GitHub-NewDraftMergeRequest {
    param(
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$BaseBranch,
        [Parameter(Mandatory)][string]$Title
    )

    $body = "Closes #$IssueNumber`n`n(plan作成中。/issue-mr-flow describe で更新する)"
    gh pr create --draft --base $BaseBranch --head $Branch --title $Title --body $body | Out-Null
    [int](gh pr view $Branch --json number --jq ".number")
}

# 未解決（isResolved: false）のレビュースレッド＋通常のissueコメントをまとめて返す。
# resolved/unresolvedの概念を持たない通常コメントは常に含める。
function GitHub-GetMrUnresolvedComments {
    param([Parameter(Mandatory)][int]$MrNumber)

    $query = @'
query($number: Int!) {
  repository(owner: "{owner}", name: "{repo}") {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          comments(first: 50) { nodes { author { login } body } }
        }
      }
      comments(first: 100) { nodes { author { login } body } }
    }
  }
}
'@

    $result = gh api graphql -f query=$query -F "number=$MrNumber" | ConvertFrom-Json
    $pr = $result.data.repository.pullRequest

    $lines = @()
    foreach ($thread in $pr.reviewThreads.nodes) {
        if ($thread.isResolved) { continue }
        foreach ($comment in $thread.comments.nodes) {
            $lines += "[review] $($comment.author.login): $($comment.body)"
        }
    }
    foreach ($comment in $pr.comments.nodes) {
        $lines += "[comment] $($comment.author.login): $($comment.body)"
    }

    $lines -join "`n`n"
}

function GitHub-SetMrDescription {
    param(
        [Parameter(Mandatory)][int]$MrNumber,
        [Parameter(Mandatory)][string]$BodyFile
    )
    gh pr edit $MrNumber --body-file $BodyFile | Out-Null
}
