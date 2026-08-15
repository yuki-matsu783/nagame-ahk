# plan: 全markdownドキュメントへのYAML frontmatter追加（issue #7）

## Context

issue #7「各markdownドキュメントにopen knowledge formatのyaml-frontmatterを追加する」対応。
リポジトリ内の各markdownファイルに、ファイル種別・要約・タグを機械可読な形で持たせることで、
将来的な一覧化・検索・ツール連携をしやすくする。issue本文は空だったため、ユーザーへのヒアリングで
以下を確定した。

- frontmatterキー: `title` / `type` / `description` / `tags`（`tag`は配列前提のため複数形`tags`を採用）
- `type`の値は自動判定せず、ファイルごとに内容を見て個別に決定する（本plan内の表がそれに当たる）
- 対象範囲: リポジトリ内の全markdown。ただし調査の結果、既に別スキーマのfrontmatterを持つ
  ファイルが見つかったため、下記の例外処理を行う

## 対象外・特殊対応ファイル（ユーザー確認済み）

| ファイル | 扱い | 理由 |
|---|---|---|
| `.gitlab/issue_templates/task.md` | **対象外**（frontmatter追加しない） | GitLabはissueテンプレートのfrontmatterを特別扱いしないため、追加すると issue作成のたびに本文へYAMLがそのまま挿入されてしまう |
| `.github/ISSUE_TEMPLATE/task.md` | `type`/`description`/`tags`の3キーのみ追加（`title`は追加しない） | 既存のGitHub仕様`title:`（issue作成時の初期タイトル欄、現状空文字）と同名衝突するため |
| `.claude/agents/ahk-code-reviewer.md`, `.claude/agents/issue-mr-resume.md` | `title`/`type`/`tags`を追加（`description`は追加しない） | 既存の`description`はClaude Codeがサブエージェント選択に使う実キーのため、重複させず流用する |
| `.claude/skills/ahk-implement/SKILL.md`, `.claude/skills/issue-mr-flow/SKILL.md` | 同上（`title`/`type`/`tags`のみ追加） | 同上（skill選択に使う`description`を保持） |

いずれも既存のfrontmatterブロックは1つのまま、新キーを末尾に追記する形にし、既存キーの値・順序は変更しない。

## frontmatterフォーマット（新規追加ファイル）

```yaml
---
title: <ファイルの題名>
type: <下表のtype値>
description: <1行要約>
tags: [<kebab-caseのキーワード, 2〜4個>]
---
```

既存frontmatterを持つファイル（agent/skill/github issue template）は、既存キーの下に
`title`（該当する場合）/`type`/`tags`を追記する形にする。

## typeの値割り当て（全39ファイル。対象外の1ファイルを除く）

| type | 対象 | 件数 |
|---|---|---|
| `ddr` | `docs/ddr/*.md`, `dev-tools/docs/ddr/*.md` | 8 |
| `rule` | `.claude/rules/*.md`（7）, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` | 10 |
| `agent` | `.claude/agents/*.md` | 2 |
| `skill` | `.claude/skills/*/SKILL.md` | 2 |
| `template` | `.github/ISSUE_TEMPLATE/task.md`, `worklog/TEMPLATE.md` | 2 |
| `guide` | `README.md`, `DEVELOPERS.md`, `docs/README.md`, `dev-tools/docs/README.md`, `tests/README.md` | 5 |
| `handoff` | `HANDOFF.md` | 1 |
| `spec` | `docs/spec/*.md`（6）, `dev-tools/docs/spec/*.md`（3） | 9 |

`description`はファイル冒頭の見出し・本文から1行で要約する（既存の見出しや導入文を流用し、
新規の解釈を持ち込まない）。`tags`は2〜4個、ディレクトリ・技術要素・工程を表すkebab-caseの
キーワードとする（例: `docs/spec/logger.md` → `["logger", "spec", "ahk"]`、
`.claude/rules/git-workflow.md` → `["git", "branch", "workflow"]`）。

## 実施内容

1. 上記39ファイルそれぞれに、Editツールでfrontmatterを追加/マージする。
2. 新しい規約として `.claude/rules/markdown-frontmatter.md` を新規作成し、以下を記載する
   （`directory-structure.md`は配置ルール、本ファイルはfrontmatterの中身のルールを扱う）。
   - キー定義（title/type/description/tags）とtypeの値一覧（上表）
   - 新規markdown作成時は原則frontmatterを付与すること
   - 例外ルール（GitHub issueテンプレートの`title`衝突、GitLab issueテンプレートは対象外、
     agent/skillは既存`description`を流用しtitleのみ追加）とその理由
3. `AGENTS.md`または`.claude/rules/directory-structure.md`から新規ルールファイルへのポインタが
   必要か確認し、既存の参照パターンに合わせて追記する（他の`.claude/rules/*.md`と同じ扱いなら
   `directory-structure.md`の記述で既にカバーされているため追記不要な可能性が高い。実装時に確認）。

## 対象外

- `.gitlab/issue_templates/task.md`へのfrontmatter追加
- frontmatterを解釈・検証する自動ツール／lintの実装（本issueはドキュメントへの付与のみが範囲）
- 既存frontmatter（agent/skillの`name`/`description`、GitHub issueテンプレートの
  `name`/`about`/`title`/`labels`/`assignees`）の値変更

## 検証方法

- 変更した各ファイルについて、`---`で始まり2つ目の`---`で閉じる単一のYAMLブロックになっているか
  目視確認する（`grep -c '^---$' <file>`が2であることを機械的に確認する簡易チェックをbashで回す）。
- `.claude/agents/*.md` / `.claude/skills/*/SKILL.md` / `.github/ISSUE_TEMPLATE/task.md`は、
  既存キー（`name`/`description`/`tools`/`model`/`about`/`labels`/`assignees`）の値が変更前と
  完全一致することをdiffで確認する（新キーの追記のみになっているか）。
- `git diff --stat`で対象ファイル数が想定（39ファイル + 新規ルール1ファイル）と一致することを確認する。
