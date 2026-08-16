---
title: markdownのYAML frontmatter規約
type: rule
description: リポジトリ内markdownドキュメントに付与するOpen Knowledge Format風frontmatterのキー定義・type値一覧・例外ルール
tags: [markdown, frontmatter, rule]
keywords: [okf, frontmatter, フロントマター, キー定義, 開放知識形式, 対象外ファイル, タイプ, keywords]
---

# markdownのYAML frontmatter規約

issue #7対応。リポジトリ内の各markdownファイルに、ファイル種別・要約・タグ等を機械可読な形で
持たせることで、将来的な一覧化・検索・ツール連携をしやすくする。

## キー定義

OKF（Open Knowledge Format、https://okf.md/spec/ ）のフィールド定義に沿って各キーの意味を記載する。

| フィールド | 必須/推奨 | 説明 |
|---|---|---|
| `type` | 必須 | コンセプトのタイプを特定する短い文字列。ルーティング・フィルタリングに使う。中央登録は無く、値は本リポジトリで自由に定義する（値は下表「typeの値」参照） |
| `title` | 推奨 | 人間が読みやすい名前 |
| `description` | 推奨 | 1文でコンセプトを要約する。将来的な一覧化・インデックス生成に使う |
| `resource` | 推奨 | 実リソース（外部URL・社内配布先・BigQueryテーブルURI等）を一意に識別するURI。抽象的な概念や、対応する実リソースが無いファイルではキー自体を省略してよい（空文字列は使わない） |
| `tags` | 推奨 | 横断的カテゴリ分類用の文字列リスト（kebab-case、2〜4個程度。ディレクトリ・技術要素・工程等を表す） |
| `keywords` | 推奨 | OKF標準にはない拡張フィールド。本文中の頻出語・特徴的な語を検索用途で3〜20個（文章量に応じて増減、平均的な長さの文章なら10個前後）リスト形式で記載する。日本語で書かれたファイルでは、英語の技術用語のみに偏らず日本語の単語もバランスよく含める |

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
| `guide` | `README.md`, `DEVELOPERS.md`, `docs/README.md`, `dev-tools/docs/README.md`, `tests/README.md`, `index.md` |
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
| `.claude/agents/*.md` | `title`/`type`/`tags`/`keywords`/（該当すれば`resource`）のみ追加。`description`は追加しない | 既存の`description`はClaude Codeがサブエージェント選択に使う実キーのため、重複させず流用する |
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
keywords: [<本文の頻出語・特徴語, 3〜20個（目安10個）>]
---
```
