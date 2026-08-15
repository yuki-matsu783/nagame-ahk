# issue-mr-flowへの実装フロー統合 + 「reflect」の分割

## Context

PR #4（issue駆動MRワークフロー支援）へのレビューで、以下3件のコメントを受けた
（`/issue-mr-flow comments` で取得。詳細は `worklog/20260815_misty-foraging-torvalds.md`）。

1. `.claude/skills/issue-mr-flow/SKILL.md:9` — 「今のワークフローを作り変えて、issue-mr-flowに統一したい」
   → ユーザー確認の結果: `.claude/rules/docs-workflow.md` / `.claude/rules/git-workflow.md` の
   実装フロー内容を `.claude/skills/issue-mr-flow/SKILL.md` に統合し、そちらを**唯一の実装フロー定義**に
   する。今後は全タスクをissue起点で進める前提とする（ahk-implementスキルも含め、issueなしの
   非issueタスクの実装フローは別途残さない）。
2. `.gitlab/issue_templates/task.md:1` — 「このファイルについてはgithub側と統一して問題ない」
   → 承認コメントとして解釈（変更不要）。
3. `dev-tools/docs/spec/issue-mr-workflow.md:89` — 「reflectというワードだと何をするルールなのか
   わからないので修正してほしい」
   → ユーザー確認の結果: 「reflect」は実は2つの異なる作業を指していた。
   - **設計反映**: `plans/` `worklog/` の内容を `docs/spec/` `docs/adr/` へ反映する（従来のreflect）
   - **AIアセット改善**: 作業中に気づいたルール・スキルの不備を `.claude/rules/` `.claude/skills/`
     `CLAUDE.md` `AGENTS.md` に反映する（今回のようなケースそのもの。従来は無名だった）
   の2ステップに分割して命名する。

これに伴い、`.claude/rules/docs-workflow.md`（実装フロー（必須）節）と `.claude/rules/git-workflow.md`
（worklogとreflect節・PR・マージ節）の**手順（順序立ったフロー）部分**を
`.claude/skills/issue-mr-flow/SKILL.md` に統合する。ドキュメントの置き場所・ライフサイクルの参照表
（docs-workflow.mdの「ドキュメント運用」）やブランチ命名規則など、フロー本体ではない参照情報は
既存ファイルに残し、SKILL.mdからはそれらを参照する形にする（`ahk-style.md` を `ahk-implement`
スキルが参照するのと同じ構造）。

## 変更方針・対象ファイル

### 1. `.claude/skills/issue-mr-flow/SKILL.md`（主となる書き換え）

以下を統合した、issue起票からマージまでの**唯一の順序立ったフロー**をこのファイルに記載する
（現状の4サブコマンド説明は維持しつつ、その前後にフロー全体の文脈を追加する構成）。

順序（担当列: 人間 / `/issue-mr-flow <サブコマンド>` / エージェント通常操作）:

1. 人間がissueを起票（`.github/ISSUE_TEMPLATE/task.md` / `.gitlab/issue_templates/task.md`）
2. `start <issue番号>` — issue取得・`Test-IssueSections`警告
3. `start` — ブランチ・Draft MR作成（既存なら `sync`）
4. `docs/spec/機能名.md` の設計ドキュメント作成（AHK機能実装は `.claude/skills/ahk-implement/SKILL.md`
   の詳細手順に従う。それ以外のタスク種別は目的に応じた設計ドキュメントを作る）
5. 人間の承認を得る（承認まで実装着手しない）
6. Planモードで実行手順に合意（`plans/` へ出力・コミット。`worklog/日付_<plan名>.md` 作成）
7. commit, push
8. 人間がMRでレビュー・コメント
9. `comments` — レビュー取得 → plan修正（8〜9を合意まで繰り返す）
10. `describe` — planをもとにMR description更新
11. 設計・実装を進めドキュメント更新（`.claude/rules/ahk-style.md` 等の規約に従う。worklogに書き足す）
12. commit, push
13. `describe` — 作業内容をもとにMR description更新
14. 人間がMRでレビュー・コメント（8〜14の実装ループを合意まで繰り返す）
15. **設計反映**: `plans/` `worklog/` の内容を `docs/spec/` `docs/adr/` へ反映
16. **AIアセット改善**: 作業中に気づいたルール・スキルの不備があれば `.claude/rules/` `.claude/skills/`
    `CLAUDE.md` `AGENTS.md` に反映
17. commit, push → 人間レビュー（15〜17を合意まで繰り返す）
18. `plans/` `worklog/` を削除、`HANDOFF.md` を次タスクへリセット
19. commit, push
20. 人間がマージ（squash merge。ブランチは削除してよい）

前提節（`gh`/`glab`、`.mrworkflow.json`、issueテンプレート）は現状のまま維持する。

### 2. `.claude/rules/docs-workflow.md`（縮小）

- 「実装フロー（必須）」節を削除し、冒頭に
  「開発フロー全体（issue起票〜マージ）は `.claude/skills/issue-mr-flow/SKILL.md` を参照する
  （唯一の実装フロー定義）。本ファイルはドキュメントの置き場所・ライフサイクルの参照表。」という
  一文を置く。
- 「ドキュメント運用」表はそのまま残す。ただし「reflect」という表現が出てくる箇所
  （`worklog/日付_<plan名>.md` 行、`HANDOFF.md` 行）を「設計反映」に置き換える。
  `CLAUDE.md` / `.claude/rules/*.md` 行の内容列も「規約・構成」に更新する（実装フローの記述は
  SKILL.mdへ移動したため）。

### 3. `.claude/rules/git-workflow.md`（縮小）

- 「worklogとreflect」節の手順1〜5、「PR・マージ」節の手順的な記述はSKILL.mdへ移動するため削除する。
- 「適用範囲」「ブランチ運用」（ブランチ命名規則）は参照情報としてそのまま残す。
- squash mergeの方針（事実としての記述）は残すが、番号付き手順としては書かない。
- 冒頭に docs-workflow.md 同様の「フロー全体はSKILL.md参照」のポインタを追加する。

### 4. `.claude/skills/ahk-implement/SKILL.md`（位置づけ変更）

- 冒頭を「このスキルは `.claude/skills/issue-mr-flow/SKILL.md` のフローのうち、
  設計ドキュメント作成〜実装ステップ（AHK機能実装の場合）で呼び出される」という説明に更新する
  （独立した最上位エントリーポイントではなく、issue-mr-flowから呼ばれるサブフローという位置づけに）。
- 手順5「整合性を維持する」内の「reflect」表記を「設計反映」に置き換える。
- それ以外（設計docの章立て、ahk-style.mdへの参照、実装手順の詳細）は変更しない。

### 5. `dev-tools/docs/spec/issue-mr-workflow.md`（背景・目的とステップ対応表を全面更新）

- 「背景・目的」から「既存の実装フローはそのまま踏襲し...薄い層を追加するもの」という記述を削除し、
  「docs-workflow.md/git-workflow.mdの実装フロー部分を統合し、issue-mr-flowを唯一の実装フロー定義とする」
  という新方針を明記する。
- 既存の「ステップ対応表」（22行）は `.claude/skills/issue-mr-flow/SKILL.md` の内容と重複・乖離する
  リスクがあるため削除し、代わりに「詳細な手順は `.claude/skills/issue-mr-flow/SKILL.md` を参照」という
  短い記述に置き換える（spec側は仕様の全体像、SKILL.md側が実行手順という役割分担にする）。
- 「Issueテンプレート標準化」節はそのまま残す。
- 「未決定事項・懸念点」に、今回の統合で `ahk-implement` スキルが独立エントリーポイントでなくなった旨を
  一言残す（既存の非issueタスクが実際に無くなるかは運用してみないと分からないため）。

### 6. `AGENTS.md`（1行追加）

「ルール」の箇条書きに以下を追加する:
「開発フロー全体（issueの起票〜マージ）は `.claude/skills/issue-mr-flow/SKILL.md` を参照する
（唯一の実装フロー定義）。全タスクはissueを起点に進める。」

### 7. worklog / HANDOFF

同一ブランチ・同一PRでの継続作業のため、新規worklogは作らず
`worklog/20260815_misty-foraging-torvalds.md` に追記する。完了後 `HANDOFF.md` を更新する。

## 影響範囲

変更: `.claude/skills/issue-mr-flow/SKILL.md`, `.claude/rules/docs-workflow.md`,
`.claude/rules/git-workflow.md`, `.claude/skills/ahk-implement/SKILL.md`,
`dev-tools/docs/spec/issue-mr-workflow.md`, `AGENTS.md`

## 検証方法

1. 各ファイルをMarkdownとして目視確認し、内部リンク（`.claude/skills/issue-mr-flow/SKILL.md` への
   相対パス参照等）が正しいことを確認する。
2. 「reflect」という単語がプロジェクト全体に残っていないか `grep -ri reflect` で確認する
   （英語の一般語としての誤検出は除外して判断）。
3. docs-workflow.md / git-workflow.md / ahk-implement/SKILL.md / issue-mr-flow/SKILL.md の間で、
   同じ手順が矛盾した内容で重複していないかを通し読みで確認する。
4. `/issue-mr-flow comments` でPR #4の当該3コメントに対応する変更であることを、コミットメッセージ・
   PR descriptionに明記する（`/issue-mr-flow describe` で反映）。

## worklog

`worklog/20260815_misty-foraging-torvalds.md` に追記して進める（新規作成しない）。
