# 途中引き継ぎ対応（resumeサブコマンド + 状態調査サブエージェント）

## Context

PR #4のレビューで、「複数人でこのフローを引き継ぐ場合、途中からでも再開できるようにAIアセットを
整えてほしい」との指摘を受けた。具体的な不足点はユーザー確認の結果、「担当者が変わった際に、
そもそも『今どのブランチ／PRのどの段階か』をAIが自力で特定できない（`start`/`sync`は引数で
issue番号・ブランチ名を渡す前提になっている）」こと。

設計は `dev-tools/docs/spec/issue-mr-workflow.md`「途中引き継ぎ対応（resume）」節に承認済み
（サブエージェント化の方針はユーザー提案）。情報収集・突き合わせの試行錯誤でメイン会話の
コンテキストを汚さないよう、専用の読み取り専用サブエージェント `issue-mr-resume` に分離する
（`.claude/agents/ahk-code-reviewer.md` と同じ形式）。

## 実装内容

### 1. `dev-tools/src/vcs/Provider.ps1`

- `Get-IssueNumberFromBranch [-Branch <name>]`（既定は現在のブランチ）: `.mrworkflow.json` の
  `branchPrefixTemplate` を正規表現化してブランチ名からissue番号を抽出する。
  `{issue}`/`{slug}` をいったん記号を含まないプレースホルダ文字列に置換してから
  `[regex]::Escape` し、その後プレースホルダを `(?<issue>\d+)` / `.+` に戻す実装にする
  （テンプレートのリテラル部分（`-` 等）を正しくエスケープしつつプレースホルダだけ正規表現化するため）。
  マッチしなければ `$null` を返す。
- `Get-MrForBranch -Branch <name>`（ディスパッチャ）: `Get-Provider` に応じて
  `GitHub-GetMrForBranch` / `GitLab-GetMrForBranch` へディスパッチする。
- `Get-BranchWorkFiles`: `git diff --name-only "origin/$($config.defaultBaseBranch)...HEAD" --
  <plansDir> <worklogDir>` と `git status --porcelain -- <plansDir> <worklogDir>` の結果を
  マージ・重複排除し、現在のブランチ固有の `plans/`/`worklog/` ファイル一覧を返す（プロバイダ非依存）。

### 2. `dev-tools/src/vcs/Github.ps1`

- `GitHub-GetMrForBranch -Branch <name>`: `gh pr view <branch> --json number,url,isDraft,title`
  を実行し、`$LASTEXITCODE` で存在確認（無ければ `$null`）。あれば `Number`/`Url`/`IsDraft`/`Title`
  を持つオブジェクトを返す。

### 3. `dev-tools/src/vcs/Gitlab.ps1`

- `GitLab-GetMrForBranch -Branch <name>`（未検証）: `glab mr view <branch> --output json` を実行し、
  同様に存在確認。`iid`/`web_url`/`work_in_progress`/`title` をマッピングする。

### 4. `.claude/agents/issue-mr-resume.md`（新規サブエージェント）

`.claude/agents/ahk-code-reviewer.md` と同じ frontmatter形式（`name`/`description`/`tools`/`model`）。
`tools: Read, Grep, Glob, Bash, PowerShell`（Provider.ps1呼び出しにPowerShellが必要なため）。
読み取り専用（Write/Editを持たない）。手順:

1. リポジトリルートで `. dev-tools\src\vcs\Provider.ps1` をdot-sourceする。
   `gh`/`glab` がPATHに見つからない場合は
   `$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
   [System.Environment]::GetEnvironmentVariable("Path","User")` で再構築してから使う
   （このマシンでのインストール直後PATH未反映問題への対処。worklog参照）。
2. `git branch --show-current` で現在のブランチを取得。`<defaultBaseBranch>` 上、または空なら
   その旨を報告して終了する。
3. `Get-IssueNumberFromBranch` でissue番号を抽出。取得できれば `Get-Issue -Number <n>`。
   できなければ「命名規則に一致しないブランチ」である旨を記録し続行。
4. `Get-MrForBranch -Branch <branch>` でPR/MRの有無・番号・URL・Draft状態を取得。
5. PR/MRがあれば `Get-MrUnresolvedComments -MrNumber <n> -IncludeResolved` で全件取得し、
   未解決件数を集計。
6. `Get-BranchWorkFiles` でブランチ固有のplan/worklogファイルを列挙。
7. `HANDOFF.md` を読む。
8. 1〜7を下記フォーマットで報告する。HANDOFF.mdの記述と実際の状態に矛盾があれば
   「矛盾・注意点」に明記する。次にすべきことの最終判断はしない（呼び出し元に委ねる）。

   ```markdown
   ## 現在地サマリ
   - ブランチ: <branch>
   - issue: #<n> <title> (<url>) ／ 特定できず
   - PR/MR: #<n> <title> (<url>) [Draft/Ready] ／ なし
   - 未解決レビューコメント: N件
   - ブランチ固有のplans/worklogファイル: <一覧> ／ なし
   - HANDOFF.md:
     <引用>

   ## 矛盾・注意点
   - <あれば列挙。無ければ「特になし」>
   ```

### 5. `.claude/skills/issue-mr-flow/SKILL.md`

- `resume`（新規サブコマンド、引数なし）: Agentツールで `issue-mr-resume` サブエージェントを
  起動し、返ってきた「現在地サマリ」をユーザーに提示する。そのうえで全体フロー20ステップの
  どこから再開すべきかを判断し、次にすべきことを提案する旨を記載する。
- `comments` / `describe` の手順1「現在のブランチに紐づくMR番号を取得する」を、
  生の `gh pr view --json number --jq .number` 等の記述から `Get-MrForBranch -Branch <現在のブランチ>`
  の呼び出しに統一する。
- 全体フロー表・前提節に `resume` を反映する。

## 影響範囲

新規: `.claude/agents/issue-mr-resume.md`
変更: `dev-tools/src/vcs/Provider.ps1`, `dev-tools/src/vcs/Github.ps1`, `dev-tools/src/vcs/Gitlab.ps1`,
`.claude/skills/issue-mr-flow/SKILL.md`

（`dev-tools/docs/spec/issue-mr-workflow.md` は承認済みのため今回変更しない）

## 検証方法

1. **構文チェック**: `Provider.ps1` をdot-sourceし、新規関数が読み込めることを確認する。
2. **`Get-IssueNumberFromBranch` の単体確認**: `.mrworkflow.json` 既定の
   `feature-{issue}-{slug}` パターンに対し、`feature-42-window-detect` → `42`、
   `main`（不一致）→ `$null` を返すことを確認する。現在の実ブランチ
   `3-開発フローを変える` は独自命名（GitHub側で作られた既存ブランチ）でパターンに一致しない
   ため `$null` になる想定で、これは既知の制約として扱う（worklogに記録）。
3. **`Get-MrForBranch` の実機確認**: 現在のブランチに対して実行し、PR #4の情報
   （番号・URL・Draft状態）が取得できることを確認する（読み取りのみ）。
4. **`Get-BranchWorkFiles` の実機確認**: 現在のブランチで実行し、`plans/misty-foraging-torvalds.md`
   等このブランチで追加・変更されたファイルが列挙されることを確認する。
5. **サブエージェントの実機確認**: Agentツールで `issue-mr-resume` を実際に起動し、
   「現在地サマリ」が期待どおりの内容（issue番号は特定できず、PR #4の情報、HANDOFF.mdの内容等）で
   返ってくることを確認する。

## worklog

`worklog/20260815_misty-foraging-torvalds.md` に追記して進める（新規作成しない）。
