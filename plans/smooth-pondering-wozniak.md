# issue #12: adr を ddr (Design Decision Record) に改称する

## Context

issue #12 より。現状 `docs/adr/` `dev-tools/docs/adr/` はADR(Architecture Decision Record)慣習に
沿った命名だが、実際にはアーキテクチャに限らない意思決定（運用ルールの決定等）も記録しており、
実態と名前が合っていない。ディレクトリ名・文章上の `adr` 表記を `ddr`（Design Decision Record）に
統一し、より広い意味に対応させる。

ユーザーへの事前確認で以下2点を決定済み:

- 既にマージ済みの過去ADRレコード本文（`dev-tools/docs/adr/0002`,`0004`）中の「adr/ADR」という
  語句も書き換える（追記のみ・変更不可ルールは決定内容そのものの改変を禁じる趣旨であり、
  プロジェクト全体の用語統一には適用しない、という解釈）。
- 受け入れ条件「必要に応じてその意味の説明文書も記載する」への対応として、この改称の決定自体を
  新規DDRレコードとして記録する（プロジェクト内にこれまでADR/DDRの英語正式名称を書いた説明文が
  一切無かったため、今回それも合わせて追加する）。

## 実施内容

### 1. ディレクトリを git mv でリネーム（履歴を保持）

- `docs/adr/` → `docs/ddr/`（`.gitkeep` のみ）
- `dev-tools/docs/adr/` → `dev-tools/docs/ddr/`（0001〜0004の4ファイル）

### 2. 既存ファイル中の `adr`/`ADR` 表記を `ddr`/`DDR` に置換

対象ファイル（パス参照・概念説明の両方を含む）:

- `.claude/rules/directory-structure.md`（ディレクトリツリー内の `adr/` 表記、worklog説明中の
  「spec/adrへ反映」）
- `.claude/rules/docs-workflow.md`（ドキュメント運用表の `docs/adr/000N-タイトル.md` 行）
- `.claude/rules/git-workflow.md`（「コード＋spec/adr」の表記）
- `.claude/skills/issue-mr-flow/SKILL.md`（全体フロー表のステップ16、詳細ルールへのポインタ節）
- `.claude/skills/ahk-implement/SKILL.md`（`docs/adr/000N-タイトル.md` への記録指示）
- `.claude/agents/ahk-code-reviewer.md`（`docs/adr/` への記録に関する言及）
- `.mrworkflow.json`（設定キー `adrDirs` → `ddrDirs`、値 `docs/adr`→`docs/ddr` 等）
- `dev-tools/src/vcs/Provider.ps1`（`Get-WorkflowConfig` の既定値 `adrDirs` → `ddrDirs`。
  現状このキーを読む処理は無い＝デッドな既定値だが、設定キー名としても統一する）
- `dev-tools/docs/spec/issue-mr-workflow.md`（複数箇所の `docs/adr/` 参照、設定サンプル中の
  `adrDirs`）
- `dev-tools/docs/spec/distribution.md`（`docs/adr/0001-...` へのリンク文字列）
- `DEVELOPERS.md`（同上リンク文字列）
- `docs/README.md`（見出し `## adr（意思決定ログ）` → `## ddr（意思決定ログ）`、箇条書きの説明文）
- `dev-tools/docs/README.md`（同上の見出し・リンク一覧）
- `dev-tools/docs/ddr/0002-issue-mr-flowへの実装フロー統合.md`（本文中の `docs/adr/` パス表記）
- `dev-tools/docs/ddr/0004-AI返信は署名で識別しbotアカウント分離は見送る.md`（本文末尾
  「本ADRが唯一の記録となる」→「本DDRが唯一の記録となる」）

### 3. DDRの意味の説明文を追加

`docs/README.md` と `dev-tools/docs/README.md` の `## ddr（意思決定ログ）` 節に、DDR =
Design Decision Record であること、architectureに限らない意思決定も対象とする旨を1〜2文で
追記する。

### 4. 改称の決定自体を新規DDRレコードとして記録

`docs/ddr/0001-意思決定ログをADRからDDRへ改称.md` を新規作成する（既存ADRファイルと同じ章立て:
`# 0001. タイトル` / `## 背景` / `## 決定` / `## 却下した案`）。背景にissue #12の内容
（architecture以外の決定も残したい）を記載する。

`docs/README.md` の `## ddr` 節にこの新規エントリへのリンクを追加する。

### 5. 副次的な修正: 壊れたリンクを解消

`docs/README.md` / `DEVELOPERS.md` / `dev-tools/docs/spec/distribution.md` は
`docs/adr/0001-ahk2exeビルドの環境依存対応.md` にリンクしているが、実際のファイルは
`dev-tools/docs/adr/0001-...` にのみ存在し、`docs/adr/` 側には存在しない（既存の壊れたリンク、
本issueの主題とは別の既存不具合だが、ユーザーの指示により今回まとめて修正する）。

- `docs/README.md`: `0001` を新規DDRレコードとして使うため、実体の無いこのエントリは一覧から
  削除する（番号衝突回避）。
- `DEVELOPERS.md` / `dev-tools/docs/spec/distribution.md`: リンク先を正しいパス
  `dev-tools/docs/ddr/0001-ahk2exeビルドの環境依存対応.md` に修正する（`adr`→`ddr` の置換と
  合わせて、誤っていたディレクトリ階層 `docs/adr/` → `dev-tools/docs/adr/` も訂正する）。

## 対象外

- `dev-tools/docs/adr/0001`,`0003` の本文（`adr`/`ADR` という語句自体を含まないため変更不要）。

## 検証方法

- `git mv` 後、`ls docs/ddr dev-tools/docs/ddr` でファイルが正しく移動していることを確認する。
- リポジトリ全体で `rg -i adr` を実行し、残存する意図しない `adr` 表記が無いことを確認する
  （`RecentDocsWatcher.ahk` の `_ReadRecentFileNames` 等、単語境界のない偶然の部分一致は
  対象外として無視する）。
- `docs/README.md` / `dev-tools/docs/README.md` 内のリンクが実在するファイルを指しているか
  目視確認する。
- `.mrworkflow.json` がJSONとして valid であることを確認する。
