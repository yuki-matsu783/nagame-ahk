---
title: PR #23レビュー対応（round 3: keywordsの日本語バランス・index.md/directory-structure.md重複解消・yq優先利用）
type: guide
description: PR #23レビューで指摘されたkeywordsの日本語バランス・index.mdとdirectory-structure.mdの記載重複・extract-frontmatter.shでのyq優先利用への対応計画
tags: [markdown, frontmatter, dev-tools]
keywords: [okf, keywords, 日本語, index, directory-structure, yq, jq, 重複解消]
---

# plan: PR #23レビュー対応（round 3）

## Context

`plans/purrfect-churning-oasis.md`（round 2、commit e273f4f）で対応した内容に対し、PR #23で新たに
3件のフィードバックを受けた（`plans/immutable-painting-kitten.md`・round 2のplanファイルは承認済み
スナップショットのため上書きせず、本round用に新規ファイルを作成する。`.claude/rules/plan-mode-safety.md`
「計画ごとに新しいplanファイル名を使う」に従う）。

1. `.claude/rules/markdown-frontmatter.md:19`（keywords行、unresolved）: 「keywordは日本語のmarkdown
   であれば日本語の単語もバランスよく含むようにしてほしい」。round 2で付与したkeywordsは
   英語のkebab-case技術用語（`okf`, `frontmatter`, `yaml`等）に偏っており、日本語コンテンツの
   ファイルにも日本語の単語をバランスよく含める必要がある。
2. `index.md:12`（新規、unresolved）: 「`.claude/rules/directory-structure.md`と役割が重複している
   記載を修正したい。ディレクトリの役割説明はindex.md、その中の各ファイルの役割説明をrules配下に
   する形で重複する記載を削除すること」。両ファイルの責務を明確に分離する。
3. `dev-tools/src/extract-frontmatter.sh:26`（新規、unresolved）: 「yq, jqがあればインストールされて
   いればそれを利用した方が良いか？」。`yq`がPATH上にあれば優先的に使い、フルYAML文法への対応力を
   上げつつ、無ければround 2で実装した自前の軽量パーサーへフォールバックする設計にする
   （新規の必須外部依存にはしない）。

## 実施内容

### 1. keywordsの日本語バランス

- `.claude/rules/markdown-frontmatter.md`の`keywords`行の説明を「本文中の頻出語・特徴的な語を
  検索用途で3〜20個（文章量に応じて増減、平均的な長さの文章なら10個前後）リスト形式で記載する。
  日本語で書かれたファイルでは、英語の技術用語のみに偏らず日本語の単語もバランスよく含める」に修正する。
- 対象39ファイル全ての`keywords`を、既存の技術用語（関数名・コマンド名・キー識別子など英字表記が
  自然なもの）と、本文中の日本語の名詞・フレーズ（例:
  `markdown-frontmatter.md`なら「フロントマター」「キー定義」「開放知識形式」等、
  `activity-status.md`なら「操作状態表示」「非アクティブ」「ツールチップ」等）を概ね半々程度で
  混在させる形に書き直す（Editツールで各ファイルの`keywords:`行を置換）。判定基準はレビュー指摘の
  「バランスよく」を、既存の英語kebab-case用語を全て日本語へ置き換えるのではなく、両者を混在
  させる方針で解釈する。

### 2. index.md と directory-structure.md の責務分離

- **役割分担**: `index.md`＝各ディレクトリの役割説明（正）、
  `.claude/rules/directory-structure.md`＝ディレクトリツリー構造・配置ルール・主要ファイル単位の
  役割説明（正）とする。
- `directory-structure.md`のツリーから、ディレクトリに対する役割説明コメント（例: `features/` の
  「機能単位の自動化ロジック（1機能 = 1ファイル目安）」、`plans/` の「AIエージェントのplanモードが
  出力する計画ファイル。タスクごとに新規生成し、そのままコミットして履歴として残す」等）を削除し、
  ディレクトリ名のみを残す。ファイル単位のコメント（`main.ahk`, `Settings.ahk`, `App.ahk`,
  `Hotkeys.ahk`, `TrayMenu.ahk`, `docs/README.md`, `dev-tools/docs/README.md`, `.gitignore`,
  `CLAUDE.md`, `HANDOFF.md`, `README.md`）は残す。ツリー直前に
  「各ディレクトリの役割は [index.md](../../index.md) を参照」の一文を追加する。
- 削除する記述のうち、`plans/`・`worklog/`の運用ルール（新規生成・コミット・削除タイミング等）は
  ディレクトリの「役割説明」ではなく運用ポリシーであり、`docs-workflow.md`のドキュメント運用表・
  `git-workflow.md`の「worklogの配置・命名」に既に同等かそれ以上の詳細で記載済みのため、
  `directory-structure.md`側では単純に削除する（三重管理を避ける）。
- `index.md`冒頭の説明文に、上記の役割分担（directory-structure.mdとの関係）を一文追記する。

### 3. extract-frontmatter.sh: yq優先利用＋フォールバック

- `frontmatter_to_json`を以下のように再構成する。
  - `extract_frontmatter_block(file)`: frontmatterの中身（区切り行`---`を含まない）を標準出力へ
    返す。frontmatterが無ければ終了コード1を返す（既存の「先頭行が`---`か」の判定ロジックを流用）。
  - `frontmatter_block_to_json()`: 標準入力からブロック本文を読み、round 2で実装した自前の軽量
    パーサー（スカラー値・フロー配列・ブロック配列）でJSONへ変換する（既存`frontmatter_to_json`の
    パース部分をほぼそのまま移設。区切り行の判定・1行目スキップ処理は`extract_frontmatter_block`
    側に既に無いため削除）。
  - `frontmatter_to_json(file)`: `extract_frontmatter_block`でブロックを取得できなければ`null`を
    返す。取得できれば、`command -v yq`でyqが利用可能か確認し、利用可能なら
    `yq -o=json e '.' -`でブロックを変換する。変換結果が`jq empty`で妥当なJSONと確認できれば
    それを採用し、失敗（yq未インストール・変換エラー）した場合は`frontmatter_block_to_json`へ
    フォールバックする。
- 既存の公開関数名`frontmatter_to_json`のシグネチャ（引数・出力）は変更しないため、
  `tests/test_extract_frontmatter.sh`は無改修のまま通ることを確認する（このマシンには`yq`が
  未インストールのため、テストはフォールバック経路を検証する形になる）。
- スクリプト冒頭のコメントに、yq優先・フォールバックの設計意図を1〜2行追記する。

### 4. レビュー対応・記録

- 新規/更新の3スレッドに対応内容を返信する。
- `worklog/20260816_ember-quilted-narwhal.md`を新規作成し作業内容を記録する。
- `HANDOFF.md`の「やったこと」「未解決の内容」を実態に合わせて更新する。

## 対象外

- `.claude/rules/markdown-frontmatter.md`のkeywords件数（3〜20個）やその他フィールド定義は
  変更しない（今回は日本語バランスの記述追加のみ）。
- `yq`のインストール自体はこのタスクの範囲外（開発機に無くても動作する設計とする）。

## 検証方法

- 対象39ファイルの`keywords`配列に、既存の英語技術用語に加えて日本語の単語が最低2〜3個以上
  含まれていることを目視・`grep -P '[keywords.*[ぁ-んァ-ヶ一-龠]'`相当の正規表現で機械的に確認する。
- `directory-structure.md`のツリーから該当するディレクトリ役割コメントが削除され、ファイル単位の
  コメントは残っていることを`git diff`で確認する。ツリー直前に`index.md`へのリンクが追加されて
  いることを確認する。
- `bash -n dev-tools/src/extract-frontmatter.sh`で構文チェックし、`bash tests/test_extract_frontmatter.sh`
  が引き続き成功することを確認する。`docs/spec/`等の実ディレクトリに対して実行し、`index.jsonl`の
  各行が`jq empty`で妥当なJSONであることを再確認する。
- `command -v yq`が無い環境（このマシン）でも`frontmatter_to_json`がエラー無くフォールバック経路で
  動作することを確認する。
