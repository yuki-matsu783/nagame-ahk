# issue #5: セッション開始時に現在ブランチのissue/MR情報を自動注入するSessionStart hook

## Context

issue-mr-flowはissue/MRベースで開発を進める前提だが、現在ブランチに紐づくissue/MRの状態確認は
`resume`サブコマンド（`issue-mr-resume`サブエージェント手動起動）でしか行えず、機械的に実行されない。
issue #5は、これをClaude CodeのSessionStart hookとして自動化し、セッション開始・resume・clear時に
毎回自動でコンテキストへ注入することを求めている（受け入れ条件: セッション開始/clear時に自動注入・
サブエージェント起動時は実行せずコンテキストを汚さない・hooksディレクトリ配下にスクリプトを作成）。

対象はAHK本体ではなく開発者向けツール（Claude Code hook）のため、`ahk-implement`スキルの対象外。
`dev-tools/docs/spec/issue-mr-workflow.md`（既存の同機能領域のspec）に追記する形で設計する。

事前調査で以下を確認済み:
- SessionStart hookは公式ドキュメント上、**Task tool経由のサブエージェント内でも発火する**
  （`agent_id`/`agent_type`フィールドがstdin JSONに追加される場合のみ）。そのため「サブエージェントでは
  実行しない」は matcher では実現できず、スクリプト内で`agent_id`の有無を見て早期returnする実装が必要。
- 追加コンテキストの注入は `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}`
  形式のJSONをstdoutに返す方式を使う（ユーザー承認済みの方式）。
- 情報収集ロジックは`.claude/agents/issue-mr-resume.md`と同じ`dev-tools/src/vcs/Provider.ps1`の関数
  （`Get-IssueNumberFromBranch` / `Get-Issue` / `Get-MrForBranch` / `Get-MrUnresolvedComments`）を
  再利用する。hookはサブエージェントを起動できないため、同種のロジックを持つ独立スクリプトとして実装する
  （ユーザーへの確認で「サブエージェントの情報収集ロジックを流用」を選択、その技術的な実現方法として合意）。

## 実施内容

### 1. 新規: `.claude/hooks/session-start.ps1`

`dev-tools/src/build.ps1`と同じスタイル（ファイル先頭に`<# 用途/使い方/前提 #>`コメント、
`$ErrorActionPreference = "Stop"`）で実装する。

処理フロー:
1. stdinを`[Console]::In.ReadToEnd()`で読み、`ConvertFrom-Json`でパース。
2. `agent_id`プロパティが存在すれば（サブエージェント内実行）、即座に何も出力せず終了する
   （受け入れ条件「サブエージェント起動時には実行されず」に対応）。
3. `Set-Location $env:CLAUDE_PROJECT_DIR`し、`. dev-tools\src\vcs\Provider.ps1`をdot-source。
4. `git branch --show-current`で現在のブランチを取得。空、または`Get-WorkflowConfig`の
   `defaultBaseBranch`と同じであれば、追加コンテキスト無しで終了（mainブランチ上では注入しない）。
5. 以降は全体を`try/catch`で包み、失敗時は例外を握りつぶし「(issue/MR情報の取得に失敗しました: ...)」
   という短い1行を`additionalContext`として返す（hookの失敗でセッション開始をブロックしない）。
   - `Get-IssueNumberFromBranch`でissue番号を抽出。取得できれば`Get-Issue`でtitle/urlを取得。
     取得できなければ「ブランチ名がissue命名規則に一致しないため特定できず」の旨を記録。
   - `Get-MrForBranch`でPR/MRの有無・番号・URL・Draft状態を取得。
   - MRが見つかった場合のみ、`Get-MrUnresolvedComments -MrNumber <n>`（`-IncludeResolved`無し=未解決のみ）
     を呼び、返却テキストから`threadId=`の出現をユニークカウントして未解決件数を算出する
     （この呼び出しだけは内側で個別に`try/catch`し、失敗してもissue/MR情報自体は出す）。
6. 収集結果を箇条書きテキストに整形し、`{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<text>"}}`
   をJSONでstdoutに出力して`exit 0`。

出力イメージ:
```
## 現在の作業ブランチ情報 (SessionStart hook)
- ブランチ: feature-5-mr-issue
- issue: #5 作業を開始する際に現在のブランチに紐づいているMRやissueの内容を確認する (https://github.com/.../issues/5)
- PR: #10 ... [Draft] (https://github.com/.../pull/10)
- 未解決レビューコメント: 0件
```

スコープ外（今回やらない）: `Get-BranchWorkFiles`によるplan/worklogファイル一覧、`HANDOFF.md`の内容表示。
これらは既存の`resume`（`issue-mr-resume`サブエージェント）の役割のまま残し、hookは「issue/MRの状態」に絞る。

### 2. 変更: `.claude/settings.json`

`hooks.SessionStart`を追加する。matcherは`"startup|resume|clear"`とし、`compact`（コンテキスト圧縮の
たびにgh API呼び出しが走るのを避ける）と`fork`（今回はスコープ外、必要になれば別途拡張）は対象外とする。
Windowsのシェル自動判定（Git Bash優先）に依存せず明示的にpowershellを指定するため、exec form
（`args`指定）で`powershell.exe`を直接呼ぶ。

```json
"hooks": {
  "SessionStart": [
    {
      "matcher": "startup|resume|clear",
      "hooks": [
        {
          "type": "command",
          "command": "powershell.exe",
          "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "${CLAUDE_PROJECT_DIR}/.claude/hooks/session-start.ps1"],
          "timeout": 30
        }
      ]
    }
  ]
}
```

### 3. 変更: `dev-tools/docs/spec/issue-mr-workflow.md`

既存の「issue駆動MRワークフロー支援」specに追記する（新規specファイルは作らない。同一機能領域のため）。

- 「## 仕様」に新セクション「### セッション開始時の自動コンテキスト注入（SessionStart hook）」を追加し、
  上記1・2の設計内容（コンポーネント・処理フロー・matcher選定理由・サブエージェント除外の実現方法・
  エラー時はbest-effortで握りつぶす方針・スコープ外事項）を記載。
- 「## 影響範囲」に新規`.claude/hooks/session-start.ps1`、変更`.claude/settings.json`、
  変更（本ドキュメント）を追記。
- 「## 決定済み事項」に、SessionStartがsubagent内でも発火する仕様であることの確認結果と
  `agent_id`判定での回避方針、matcherを`startup|resume|clear`に絞った理由を追記。

## 対象外

- GitLab版の動作確認（既存機能同様、実remoteがGitHubのみのため未検証のまま）。
- `compact`/`fork`時の注入（受け入れ条件に無いスコープ拡張は行わない）。
- plan/worklogファイル一覧・HANDOFF.md内容の注入（`resume`の役割のまま維持）。

## 検証方法

- 疑似stdin JSONを標準入力として渡し、PowerShellスクリプトを単体実行して確認する。
  - メインセッション相当（`agent_id`無し）・issueブランチ上 → issue/MR情報を含むJSONが出力されること。
  - `agent_id`ありの疑似入力 → 何も出力せず`exit 0`で終了すること。
  - `main`ブランチ上（`git checkout main`した状態）→ 追加コンテキスト無しで終了すること。
  - `gh`コマンドを一時的に失敗させる（例: 存在しないissue番号のブランチ名にする）→ セッションをブロックせず
    短い失敗メッセージのみが返ること。
- `.claude/settings.json`のJSON構文が妥当であること（`ConvertFrom-Json`等でパース確認）。
- 実際に新しいClaude Codeセッションを開始し、SessionStart hookが発火してコンテキストに反映されることを
  目視確認する（可能であれば）。
