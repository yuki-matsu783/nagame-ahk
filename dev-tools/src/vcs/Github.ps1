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

    # gh api graphqlの{owner}/{repo}プレースホルダはクエリ文字列中には展開されず、
    # -F フィールドの値としてのみ機能する（`gh api graphql --help` のGraphQL例を参照）。
    # そのため owner/repo もGraphQL変数として宣言し、-F 経由で渡す。
    $query = @'
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          path
          line
          comments(first: 50) { nodes { author { login } body diffHunk } }
        }
      }
      comments(first: 100) { nodes { author { login } body } }
    }
  }
}
'@

    $result = gh api graphql -F "owner={owner}" -F "repo={repo}" -F "number=$MrNumber" -f "query=$query" | ConvertFrom-Json
    $pr = $result.data.repository.pullRequest

    $lines = @()
    foreach ($thread in $pr.reviewThreads.nodes) {
        if ($thread.isResolved) { continue }
        $location = if ($thread.path) { "$($thread.path):$($thread.line)" } else { "(場所不明)" }
        foreach ($comment in $thread.comments.nodes) {
            $entry = "[review $location] $($comment.author.login): $($comment.body)"
            if ($comment.diffHunk) {
                $entry += "`n--- diff ---`n$($comment.diffHunk)"
            }
            $lines += $entry
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
