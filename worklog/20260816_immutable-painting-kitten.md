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

## レビュー対応（1回目）

- PRレビューで「TEMPLATEはやっぱりfrontmatter不要で良いや」との指摘。対象を確認したところ
  `.github/ISSUE_TEMPLATE/task.md`のみを指す（`worklog/TEMPLATE.md`は従来通りtitle/type/
  description/tagsを追加する）とのことだったため、planを以下の通り修正した。
  - `.github/ISSUE_TEMPLATE/task.md`を「type/description/tagsのみ追加」から「完全に対象外」へ変更。
  - `type`割り当て表の`template`から同ファイルを除外し、対象ファイル数を39→38に修正。

## 実装（1回目）

- plan通り38ファイルへ`title`/`type`/`description`/`tags`を追加/マージした。
- 実装中に、当初planの対象外表に無かった既存frontmatterを追加発見した。
  - `.claude/rules/directory-structure.md`, `docs-workflow.md`, `git-workflow.md`,
    `plan-mode-safety.md`: 既に`alwaysApply: true`を持つ（Claude Codeのルール常時適用設定として
    実際に使われる）。既存キーの下に新キーを追記する形でマージした。
  - `.claude/rules/ahk-style.md`: 既に`paths:`（対象ファイルパターン）を持つ。同様に既存キーの下へ
    追記した。
  - 対応方針をplanの「対象外・特殊対応ファイル」表に追記した。

## スキーマ変更（ユーザーからの追加指示）

- 実装完了後、ユーザーから「推奨フィールドとして`resource`（実リソースへのリンク）と`timestamp`
  （更新時刻、ISO 8601）を追加してほしい。`type`のみ必須、他は推奨」との指示を受けた。
- `resource`は今回対象の全ファイルに該当する外部リソースが無いため、全ファイルでキー自体を省略する
  方針とした（ユーザー確認済み）。
- `timestamp`はユーザー指示により以下の対応をした。
  1. 当初タイムゾーン付き（`+09:00`）で4ファイルに手動Edit追加したところ、ユーザーから
     「タイムゾーンは省略してよい」「コマンドで機械的に追加すること」との訂正を受けた。
  2. `sed`を使い、変更済み全38ファイルに対して`tags:`行の直後へ
     `timestamp: "2026-08-16T05:31:36"`（タイムゾーン省略、全ファイル一律の値）を一括追加する
     bashスクリプトに切り替えた（既にタイムゾーン付きで追加していた4ファイルは同じスクリプトで
     タイムゾーン部分を除去して修正）。
  3. `grep`で全38ファイルに`timestamp:`行が存在し、タイムゾーン付きが残っていないことを確認した。
- 新規ルール`.claude/rules/markdown-frontmatter.md`を作成し、キー定義表（type必須・他は推奨）・
  typeの値一覧・対象外/特殊対応ファイル（今回発見したalwaysApply/pathsのファイルを含む）を記載した。
- `plans/immutable-painting-kitten.md`を新スキーマに合わせて更新した。
- `.claude/rules/`は個別ファイルを列挙しない包括的な参照運用のため、新規ルールファイルへの
  追加ポインタは不要と判断した（directory-structure.mdの記述を確認済み）。

## 次の一歩

- commit・push、PR description更新、HANDOFF更新。
- レビュー依頼。

---
