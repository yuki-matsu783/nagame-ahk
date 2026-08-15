---
title: markdownのYAML frontmatter規約
type: rule
description: リポジトリ内markdownドキュメントに付与するOpen Knowledge Format風frontmatterのキー定義・type値一覧・例外ルール
tags: [markdown, frontmatter, rule]
timestamp: "2026-08-16T05:31:36"
---

# markdownのYAML frontmatter規約

issue #7対応。リポジトリ内の各markdownファイルに、ファイル種別・要約・タグ等を機械可読な形で
持たせることで、将来的な一覧化・検索・ツール連携をしやすくする。

## キー定義

| フィールド | 必須/推奨 | 説明 |
|---|---|---|
| `type` | 必須 | コンセプトの種類。ルーティング・フィルタ・表示に使う（値は下表「typeの値」参照） |
| `title` | 推奨 | タイトル |
| `description` | 推奨 | 説明 |
| `resource` | 推奨 | 実リソースへのリンク。**対応する実リソース（外部URL・社内配布先・BigQueryテーブルURI等）が無いファイルではキー自体を省略してよい**（空文字列は使わない） |
| `tags` | 推奨 | タグ配列（kebab-case、2〜4個程度。ディレクトリ・技術要素・工程等を表す） |
| `timestamp` | 推奨 | 更新時刻（ISO 8601）。タイムゾーンは省略する（例: `2026-08-16T05:31:36`） |

新規markdown作成時は原則このfrontmatterを付与する。既存のfrontmatterを持つファイル（後述）は
既存キーを変更せず、不足しているキーのみを追記する。

## typeの値

| type | 対象 |
|---|---|
| `ddr` | `docs/ddr/*.md`, `dev-tools/docs/ddr/*.md` |
| `rule` | `.claude/rules/*.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` |
| `agent` | `.claude/agents/*.md` |
| `skill` | `.claude/skills/*/SKILL.md` |
| `template` | `worklog/TEMPLATE.md` |
| `guide` | `README.md`, `DEVELOPERS.md`, `docs/README.md`, `dev-tools/docs/README.md`, `tests/README.md` |
| `handoff` | `HANDOFF.md` |
| `spec` | `docs/spec/*.md`, `dev-tools/docs/spec/*.md` |

`type`の値は自動判定せず、ファイルごとに内容を見て個別に決定する。上表は現時点の割り当て例であり、
新しいディレクトリ・用途が増えた場合はこの表に追記する。

## 対象外・特殊対応ファイル

以下は既に別スキーマのfrontmatterを持つか、機能上frontmatterの追加が適さないため、通常の
4〜6キーをそのまま追加しない。

| ファイル | 扱い | 理由 |
|---|---|---|
| `.gitlab/issue_templates/task.md` | **対象外**（frontmatter追加しない） | GitLabはissueテンプレートのfrontmatterを特別扱いしないため、追加すると issue作成のたびに本文へYAMLがそのまま挿入されてしまう |
| `.github/ISSUE_TEMPLATE/task.md` | **対象外**（frontmatter追加しない） | GitHub仕様の`title`等の既存frontmatterと衝突・干渉するため。issueテンプレートにOKF frontmatterは不要と判断した |
| `.claude/agents/*.md` | `title`/`type`/`tags`/（該当すれば`resource`/`timestamp`）のみ追加。`description`は追加しない | 既存の`description`はClaude Codeがサブエージェント選択に使う実キーのため、重複させず流用する |
| `.claude/skills/*/SKILL.md` | 同上 | 同上（skill選択に使う`description`を保持） |
| `.claude/rules/*.md`のうち`alwaysApply: true`を持つファイル | 既存キーの下に新キーを追記する | `alwaysApply`はClaude Codeのルール常時適用設定として実際に使われるため、値・位置を変更しない |
| `.claude/rules/ahk-style.md` | 既存の`paths:`キーの下に新キーを追記する | `paths`は対象ファイルパターンを表す既存メタ情報のため保持する |

いずれも既存のfrontmatterブロックは1つのまま、新キーを既存キーの下に追記する形にし、既存キーの
値・順序は変更しない。

## 新規ファイル作成時のフォーマット例

```yaml
---
title: <ファイルの題名>
type: <上表のtype値>
description: <1行要約>
resource: <対応する実リソースがあれば記載。無ければキー自体を省略>
tags: [<kebab-caseのキーワード, 2〜4個>]
timestamp: <更新時刻。ISO 8601、タイムゾーン省略>
---
```
