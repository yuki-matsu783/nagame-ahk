---
title: "worklog: PR #23レビュー対応（round 3）"
type: guide
description: PR #23レビューで指摘されたkeywordsの日本語バランス・index.mdとdirectory-structure.mdの記載重複・extract-frontmatter.shでのyq優先利用への対応ログ
tags: [markdown, frontmatter, dev-tools]
keywords: [okf, keywords, 日本語, index, directory-structure, yq, jq, 重複解消]
---

# worklog: PR #23レビュー対応（round 3）

対象: issue #7・PR #23の実装レビュー対応round 3（2026-08-16）。
plan: `plans/ember-quilted-narwhal.md`

## 試したこと

- `comments all`でPR #23の最新状態を取得。round 2で返信した3スレッドのうち「説明列の改善」は
  resolved、残り2件（timestamp削除・keywords追加）はunresolvedのまま、加えて新規スレッド2件
  （index.mdとdirectory-structure.mdの記載重複、extract-frontmatter.shでのyq利用可否）を確認。
- round 2のplanファイル（`plans/purrfect-churning-oasis.md`）は承認済みスナップショットのため
  上書きせず、round 3用に新規plan（`plans/ember-quilted-narwhal.md`）を作成。Planモード再突入時、
  ハーネスが追跡する「今回のplanファイル」が`purrfect-churning-oasis.md`のパスに固定されていたため、
  `ExitPlanMode`がround 3の内容を正しく読めるよう一時的に同ファイルへround 3の内容を書き込み、
  承認後に`git checkout`でround 2時点のコミット済み内容へ復元した（`.claude/rules/plan-mode-safety.md`
  「計画ごとに新しいplanファイル名を使う」を、ハーネスの1re-entry=1ファイル固定という制約の中でも
  満たすための対応）。
- keywordsの日本語バランス: 対象39ファイル全ての`keywords`配列を見直し、既存の英語kebab-case技術
  用語に加えて本文中の日本語の名詞・フレーズを追加（概ね半々を目安）。`.claude/rules/markdown-frontmatter.md`
  のkeywords説明にも「日本語で書かれたファイルでは、英語の技術用語のみに偏らず日本語の単語も
  バランスよく含める」を追記。
- index.md / directory-structure.mdの責務分離: index.mdを「各ディレクトリの役割説明」の正とし、
  directory-structure.mdのツリーからディレクトリ単位の役割コメントを削除（ファイル単位のコメントは
  維持）。ツリー直前に「各ディレクトリの役割はindex.mdを参照」の一文を追加し、index.md側にも
  逆方向の参照（directory-structure.mdとの役割分担）を追記した。
- extract-frontmatter.sh: `frontmatter_to_json`を`extract_frontmatter_block`
  （区切り行を含まないブロック本文を返す）と`frontmatter_block_to_json`（自前パーサー本体）に分割し、
  `frontmatter_to_json`本体では`command -v yq`でyqの有無を確認、あれば`yq -o=json e '.' -`を優先的に
  使い、無い・失敗した場合は自前パーサーへフォールバックする構成に変更。

## うまくいったこと

- `extract_frontmatter_block`/`frontmatter_block_to_json`への分割はほぼ機械的なリファクタで、
  公開関数`frontmatter_to_json`のシグネチャ（引数・出力）を変えずに済んだため、
  `tests/test_extract_frontmatter.sh`は無改修のまま12アサーション全て成功した（このマシンには`yq`が
  未インストールのため、テストはフォールバック経路を検証している）。
- keywordsへの日本語追加後、`rg '^keywords:.*[ぁ-んァ-ヶ一-龥]'`で対象39ファイル全てにマッチする
  ことを確認できた（ripgrepはロケールに依存せずUnicode文字クラスを扱えるため、git bashの
  `grep -P`がロケールエラーで使えなかった代わりに利用した）。

## ダメだったこと

- 特になし。

## 次の一歩

- 特になし（完了）。新規/更新スレッド3件に返信済み。commit・push・PR description更新後、
  人間の再レビュー待ち。
