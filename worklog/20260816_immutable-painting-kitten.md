# worklog: immutable-painting-kitten

対象: 各markdownドキュメントへのYAML frontmatter（title/type/description/tags）追加（issue #7）（2026-08-16）。
plan: `plans/immutable-painting-kitten.md`

## 試したこと

- issue #7の本文が空だったため、ヒアリングでfrontmatterキー（title/type/description/tag→tags）、
  対象範囲（リポジトリ内の全markdown）、`type`値の決め方（自動判定せずファイルごとに個別決定）を確定した。
- 対象40ファイルを`git ls-files '*.md'`で洗い出し、既存frontmatterの有無・用途を調査した。
  - `.claude/agents/*.md`, `.claude/skills/*/SKILL.md`: Claude Codeが`name`/`description`を実際に
    読み込んで使用（サブエージェント/スキル選択）していることを確認。
  - `.github/ISSUE_TEMPLATE/task.md`: GitHub仕様の`title`/`about`/`labels`/`assignees`等を保持。
  - `.gitlab/issue_templates/task.md`: frontmatterはGitLab側で特別扱いされず、issueテンプレート
    使用時に本文へそのまま挿入される仕様であることを確認。

## うまくいったこと

- 上記調査結果をユーザーに提示し、以下の対応方針で合意した。
  - `.gitlab/issue_templates/task.md`は対象外（本文へのYAML混入を避けるため）。
  - `.github/ISSUE_TEMPLATE/task.md`は既存`title:`との衝突を避け、`type`/`description`/`tags`の
    3キーのみ追加。
  - `.claude/agents/*.md` / `.claude/skills/*/SKILL.md`は既存`description`を流用し、
    `title`/`type`/`tags`のみ追加。
  - 上記以外の34ファイルは`title`/`type`/`description`/`tags`の4キーを新規追加。
- 全39対象ファイルに`type`値を個別に割り当て、8種類のtype語彙（ddr/rule/agent/skill/template/
  guide/handoff/spec）に整理した（詳細は`plans/immutable-painting-kitten.md`参照）。

## ダメだったこと

- 特になし。

## 次の一歩

- plan承認後、39ファイルへのfrontmatter追加・マージ、および新規ルール
  `.claude/rules/markdown-frontmatter.md`の作成を実施する。
- 実施後、既存frontmatterファイル（agent/skill/github issue template）は既存キーの値が
  変更されていないことをdiffで確認する。

---
