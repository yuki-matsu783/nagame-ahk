# plan: 全markdownドキュメントへのYAML frontmatter追加（issue #7）

## Context

issue #7「各markdownドキュメントにopen knowledge formatのyaml-frontmatterを追加する」対応。
リポジトリ内の各markdownファイルに、ファイル種別・要約・タグを機械可読な形で持たせることで、
将来的な一覧化・検索・ツール連携をしやすくする。issue本文は空だったため、ユーザーへのヒアリングで
以下を確定した。

- frontmatterキー: `type`（必須）/ `title` / `description` / `resource` / `tags` / `timestamp`（推奨）。
  当初`title`/`type`/`description`/`tag`の4キーで実装を進めていたが、レビュー後に
  `resource`（実リソースへのリンク）と`timestamp`（更新時刻）を追加する方針変更を受けた
  （`tag`→複数形`tags`は当初案のまま）。詳細は`.claude/rules/markdown-frontmatter.md`のキー定義表を参照
- `type`の値は自動判定せず、ファイルごとに内容を見て個別に決定する（本plan内の表がそれに当たる）
- `resource`は対応する外部リソース（社内配布先URL等）が無いファイルではキー自体を省略する
  （空文字列は使わない）。今回の対象39ファイルはいずれも該当する外部リソースが無いため、
  全ファイルで省略した
- `timestamp`は今回は全ファイル一律で作業時点の現在時刻（ISO 8601、タイムゾーン省略。
  例: `2026-08-16T05:31:36`）を機械的に付与した（`sed`によるコマンド一括追加。個別のEditツールでの
  手作業は行っていない）
- 対象範囲: リポジトリ内の全markdown。ただし調査の結果、既に別スキーマのfrontmatterを持つ
  ファイルが見つかったため、下記の例外処理を行う

## 対象外・特殊対応ファイル（ユーザー確認済み）

| ファイル | 扱い | 理由 |
|---|---|---|
| `.gitlab/issue_templates/task.md` | **対象外**（frontmatter追加しない） | GitLabはissueテンプレートのfrontmatterを特別扱いしないため、追加すると issue作成のたびに本文へYAMLがそのまま挿入されてしまう |
| `.github/ISSUE_TEMPLATE/task.md` | **対象外**（frontmatter追加しない。レビューで方針変更） | 既存のGitHub仕様`title:`との衝突を避けるため当初は`type`/`description`/`tags`のみ追加する案だったが、レビューでissueテンプレートにはOKF frontmatterそのものが不要と判断し、完全に対象外とした |
| `.claude/agents/ahk-code-reviewer.md`, `.claude/agents/issue-mr-resume.md` | `title`/`type`/`tags`を追加（`description`は追加しない） | 既存の`description`はClaude Codeがサブエージェント選択に使う実キーのため、重複させず流用する |
| `.claude/skills/ahk-implement/SKILL.md`, `.claude/skills/issue-mr-flow/SKILL.md` | 同上（`title`/`type`/`tags`のみ追加） | 同上（skill選択に使う`description`を保持） |
| `.claude/rules/directory-structure.md`, `docs-workflow.md`, `git-workflow.md`, `plan-mode-safety.md` | 既存`alwaysApply: true`の下に新キーを追記 | 実装時に発覚。`alwaysApply`はClaude Codeのルール常時適用設定として実際に使われるキーのため、値・位置を変更しない |
| `.claude/rules/ahk-style.md` | 既存`paths:`の下に新キーを追記 | 実装時に発覚。`paths`は対象ファイルパターンを表す既存メタ情報のため保持する |

いずれも既存のfrontmatterブロックは1つのまま、新キーを末尾に追記する形にし、既存キーの値・順序は変更しない。

## frontmatterフォーマット（新規追加ファイル）

```yaml
---
title: <ファイルの題名>
type: <下表のtype値>
description: <1行要約>
resource: <対応する実リソースがあれば記載。無ければキー自体を省略>
tags: [<kebab-caseのキーワード, 2〜4個>]
timestamp: <更新時刻。ISO 8601、タイムゾーン省略>
---
```

既存frontmatterを持つファイル（agent/skill/github issue template/alwaysApplyルール/ahk-style.md）は、
既存キーの下に不足しているキーのみを追記する形にする。詳細（キー定義・typeの値一覧・例外ルール）は
`.claude/rules/markdown-frontmatter.md`を正とする（本plan内の記述と重複する場合はそちらを優先する）。

## typeの値割り当て（全38ファイル。対象外の2ファイルを除く）

| type | 対象 | 件数 |
|---|---|---|
| `ddr` | `docs/ddr/*.md`, `dev-tools/docs/ddr/*.md` | 8 |
| `rule` | `.claude/rules/*.md`（7）, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` | 10 |
| `agent` | `.claude/agents/*.md` | 2 |
| `skill` | `.claude/skills/*/SKILL.md` | 2 |
| `template` | `worklog/TEMPLATE.md` | 1 |
| `guide` | `README.md`, `DEVELOPERS.md`, `docs/README.md`, `dev-tools/docs/README.md`, `tests/README.md` | 5 |
| `handoff` | `HANDOFF.md` | 1 |
| `spec` | `docs/spec/*.md`（6）, `dev-tools/docs/spec/*.md`（3） | 9 |

`description`はファイル冒頭の見出し・本文から1行で要約する（既存の見出しや導入文を流用し、
新規の解釈を持ち込まない）。`tags`は2〜4個、ディレクトリ・技術要素・工程を表すkebab-caseの
キーワードとする（例: `docs/spec/logger.md` → `["logger", "spec", "ahk"]`、
`.claude/rules/git-workflow.md` → `["git", "branch", "workflow"]`）。

## 実施内容

1. 上記38ファイルそれぞれに、Editツールでfrontmatterを追加/マージする。
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

- `.gitlab/issue_templates/task.md`、`.github/ISSUE_TEMPLATE/task.md`へのfrontmatter追加
  （両方ともissueテンプレートは対象外。前者はGitLab仕様上の本文混入、後者はレビューでの方針変更）
- frontmatterを解釈・検証する自動ツール／lintの実装（本issueはドキュメントへの付与のみが範囲）
- 既存frontmatter（agent/skillの`name`/`description`、GitHub issueテンプレートの
  `name`/`about`/`title`/`labels`/`assignees`）の値変更

## 検証方法

- 変更した各ファイルについて、`---`で始まり2つ目の`---`で閉じる単一のYAMLブロックになっているか
  目視確認する（`grep -c '^---$' <file>`が2であることを機械的に確認する簡易チェックをbashで回す）。
- `.claude/agents/*.md` / `.claude/skills/*/SKILL.md` / `alwaysApply`を持つルールファイル /
  `ahk-style.md`は、既存キー（`name`/`description`/`tools`/`model`/`alwaysApply`/`paths`）の値が
  変更前と完全一致することをdiffで確認する（新キーの追記のみになっているか）。
- 全対象ファイルに`timestamp:`行が存在し、タイムゾーンオフセット（`+HH:MM`/`-HH:MM`）を含まないことを
  `grep`で機械的に確認する。
- `resource`キーは今回対象の全ファイルで省略していることを確認する（該当する外部リソースが後日
  見つかった場合のみ個別に追加する）。
- `git diff --stat`で対象ファイル数が想定（38ファイル + 新規ルール1ファイル）と一致することを確認する。
