---
title: PR #23レビュー対応（timestamp廃止・keywords追加・index.md・frontmatter抽出スクリプト）
type: guide
description: issue #7 PR #23の実装レビューで指摘された3件の修正と、追加要望2件（Repository Map・frontmatter抽出jsonlスクリプト）の実装計画
tags: [markdown, frontmatter, dev-tools]
keywords: [okf, frontmatter, timestamp, keywords, index, jsonl, extract-frontmatter, repository-map]
---

# plan: PR #23レビュー対応（round 2）

## Context

issue #7・PR #23（flow-id 11〜13完了済み、38ファイル+新規ルールへのOKF風frontmatter追加）に対し、
実装レビュー（flow-id 14相当）で以下5件の指摘・要望が付いた。本plan（`plans/immutable-painting-kitten.md`
とは別ファイル。同ファイルは承認済みスナップショットのため上書きしない）はその対応内容を定める。

- レビュースレッド（`.claude/rules/markdown-frontmatter.md`対象、未解決3件）
  1. `timestamp`キー削除（OKF v0.2で廃止されたとの指摘。ルール本体＋既存対象ファイル全部から削除）
  2. `keyword`フィールド新規追加（本文の頻出・特徴語を3〜20個、平均10個程度、検索用途）
  3. キー定義表の「説明」列をOKF標準文書に沿ってもっと丁寧に記載
- 通常コメント（このPRに含めることをユーザーに確認済み）
  4. リポジトリルートに、各ディレクトリへの相対リンクと簡単な説明を載せた`index.md`（Repository Map）を作成
  5. 指定ディレクトリ配下のmarkdownからfrontmatterを抽出しjsonlで出力するスクリプトを作成

OKF公式spec（https://okf.md/spec/ , v0.1時点）を確認したところ、`timestamp`は現行specにも
「推奨フィールド」として残っており廃止の記載は見当たらなかったが、レビュアーの明示的な削除指示
（「全ファイルからも削除して」）は仕様の細部解釈より優先し、額面通りに削除する。

## 実施内容

### 1. `.claude/rules/markdown-frontmatter.md` の修正

- キー定義表から`timestamp`行を削除し、フォーマット例（新規ファイル作成時のyamlブロック）からも
  `timestamp:`行を削除する。
- `keywords`行を追加する（**フィールド名は複数形`keywords`を採用**。理由: 値はリストであり、
  本ルールが既に`tag`→`tags`で確立した「リスト値は複数形」の命名規則
  （`plans/immutable-painting-kitten.md`参照）と揃えるため。レビューコメントの表記は単数形
  「keyword」だったが、ここは呼称の揺れとみなし複数形に統一する。承認時にご確認ください）。
  説明文: 「本文中の頻出語・特徴的な語を検索用途で3〜20個（文章量に応じて増減、平均的な長さの
  文章なら10個前後）リスト形式で記載する。OKF標準の必須/推奨フィールドではない拡張フィールド」。
- 各フィールドの「説明」列を、OKF spec（https://okf.md/spec/）の文言に沿って書き直す
  （`type`＝「コンセプトのタイプを特定する短い文字列。ルーティング・フィルタリングに使用。
  中央登録は無くプロデューサーが自由に定義」、`title`＝「人間が読みやすい名前」、
  `description`＝「1文でコンセプトを要約する。インデックス生成に使用」、
  `resource`＝「資産を一意に識別するURI。抽象的な概念には不要」、
  `tags`＝「横断的カテゴリ分類用の文字列リスト」）。
- 冒頭の自身のfrontmatterからも`timestamp`を削除し`keywords`を追加する（自己適用）。
- 「typeの値」表の`guide`行に`index.md`を追加する（新規type区分は作らない。README.md等と同じ
  ナビゲーション用途のため）。

### 2. 既存対象ファイル（39件）への一括反映

対象は`grep -rl '^timestamp:' --include='*.md' .`で確認した39ファイル（フロー対象の38ファイル＋
ルール自身）。`plans/immutable-painting-kitten.md`内の`timestamp: <...>`はフォーマット例文の
一部（誤検出）であり対象外。

- **timestamp削除**: `sed -i '/^timestamp:/d' <39ファイル>`で一括削除する（元々の追加時と同じ
  「sedによるコマンド一括処理」の手法を踏襲）。
- **keywords追加**: ファイルごとに内容が異なるため機械的な一括処理はできない。各ファイルを読み、
  本文の頻出語・特徴的な語を3〜20個（目安10個）抽出して`tags:`行の直後に`keywords: [...]`を
  Editツールで追記する（既存キーの値・順序は変更しない）。
- 処理後、`grep -c '^keywords:'`が39件、`grep -rl '^timestamp:'`が0件（plans内の誤検出を除く）に
  なることを確認する。

### 3. `index.md`（Repository Map）の新規作成

リポジトリルートに作成する。内容は`git ls-files`で実在確認した追跡対象ディレクトリと、
`.claude/rules/directory-structure.md`に既にある説明文を流用して構成する（新規の解釈を持ち込まない）。
ファイル単位の記載はせず、ディレクトリのみを対象とする（ユーザー提示のフォーマット例に準拠）。

含めるディレクトリ（代表例。full listは実装時に`git ls-files`ベースで再確認する）:
`src/`（`config/` `core/` `features/` `lib/`）、`assets/icons/`、`docs/`（`spec/` `ddr/`）、
`dev-tools/`（`src/` `docs/spec/` `docs/ddr/`）、`tests/`（`lib/`）、`.claude/`（`rules/` `skills/`
`agents/` `hooks/` `hooks/lib/`）、`plans/`、`worklog/`、`.github/ISSUE_TEMPLATE/`、
`.gitlab/issue_templates/`、`.gemini/`。`build/`は`.gitignore`対象のビルド出力先だが
`directory-structure.md`に明記されているため注記付きで掲載する。
（`.agents/` `.claude/docs/` `.claude/scripts/` `.claude/usage-state/` `tests/docs/`は`git ls-files`で
追跡ファイルが0件の空ディレクトリのため掲載しない）

frontmatterは本リポジトリの規約に従い付与する（`title`/`type: guide`/`description`/`tags`/`keywords`。
`timestamp`は付与しない）。

### 4. frontmatter抽出スクリプトの新規作成

`dev-tools/src/extract-frontmatter.sh <directory>` として作成する（VCS非依存の汎用dev-toolのため
`vcs/`配下ではなく`dev-tools/src/`直下、`build.sh`と同階層）。

- 指定ディレクトリ配下の`*.md`を再帰的に走査し、各ファイルについて
  `{"concept_id": <指定ディレクトリからの相対パスから.mdを除いたもの>, "directory": <相対ディレクトリ>,
  "frontmatter": <キー定義済みの場合はJSONオブジェクト、frontmatterが無いファイルはnull>,
  "mtime": <ファイル更新日時、既存frontmatterの`timestamp`形式に合わせたISO 8601文字列>}`
  を1行1JSONで`<指定ディレクトリ>/index.jsonl`へ出力する（実行のたびに上書き）。
- frontmatterのYAML→JSON変換は、本リポジトリのfrontmatterが単純なスカラー値とフロー形式配列
  `[a, b, c]`のみで構成される前提の**自前の軽量パーサー**（awk/sedで`key: value`行と`[...]`配列を
  認識するのみ）で行う。`yq`は開発機に未インストールであり、フルYAML文法対応の外部依存を
  新規に増やすほどの必要性が無いため導入しない（`jq`はJSON組み立てに継続利用）。
- `set -euo pipefail`・BOM無しUTF-8・LF改行など`.claude/rules/shell-script-style.md`の規約に従う。
- 純粋ロジック部分（concept_id導出、`key: value`/配列のYAML→JSON変換）は`tests/test_vcs_provider.sh`
  と同様の形で`tests/test_extract_frontmatter.sh`に単体テストを作成する。

### 5. レビュー対応

- 3件の未解決レビュースレッドに、上記1・2の対応内容を`reply`サブコマンドで返信する。
- worklog（`worklog/20260816_purrfect-churning-oasis.md`を新規作成、命名規則は本plan名に合わせる）に
  作業内容を記録する。
- HANDOFF.mdの「未解決の内容」を実態に合わせて更新し、flow-id 14を完了、15を対応中として記録する。

## 対象外

- issue #7本来のスコープに厳密には含まれない`index.md`・抽出スクリプトの実装は、今回ユーザー承認の
  上でこのPRに含めるが、それ以上の機能追加（抽出スクリプトへの追加オプション等）は行わない。
- 39ファイル以外（`.github/ISSUE_TEMPLATE/task.md`等、元々frontmatter対象外のファイル）への変更は行わない。
- `dev-tools/docs/spec/`への抽出スクリプトの正史仕様反映は、既存フロー通りflow-id 16（設計反映）で
  worklog内容をもとに行う。今回は実装のみ。

## 検証方法

- `grep -rl '^timestamp:' --include='*.md' .`が空（`plans/immutable-painting-kitten.md`の誤検出のみ
  残る場合はそれが例文由来であることを確認）になることを確認する。
- `grep -rc '^keywords:' --include='*.md' .`で39ファイル分カウントされることを確認する。
- 変更対象ファイルの`git diff`で、`timestamp`削除・`keywords`追加以外の既存キー（`name`/`alwaysApply`/
  `paths`等）が変更されていないことを確認する（数ファイルを抽出してdiff内容を目視）。
- `index.md`内の全リンク先ディレクトリが実在することを`test -d`で機械的に確認する。
- `bash -n dev-tools/src/extract-frontmatter.sh`で構文チェックし、`docs/spec/`など実在ディレクトリに
  対して実行して`index.jsonl`の各行が`jq empty`でパース可能なJSONであることを確認する。
  frontmatterの無いファイルを含むディレクトリでも`frontmatter: null`として扱われることを確認する。
- `bash tests/test_extract_frontmatter.sh`で単体テストが通ることを確認する。
- `comments all`で対応済みスレッドへの返信が反映されていることを確認する。
