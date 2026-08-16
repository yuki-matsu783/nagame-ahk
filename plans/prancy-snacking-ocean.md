---
title: issue #22 ブランチ名slugのリッチ化 対応計画
type: log
description: issue #22「ブランチ名のslugをリッチにしたい」に対する実行計画。AIエージェントが英語の意訳フレーズを生成しto_slugへ渡す方式を採用する
tags: [issue-mr-flow, slug, branch-naming]
keywords: [to_slug, new_issue_branch, 意訳, slug, ブランチ名, Provider.sh, SKILL.md]
---

# issue #22「ブランチ名のslugをリッチにしたい」対応計画

## Context

issue #22 の本文は目的・現状・期待する動作・受け入れ条件の見出しのみで中身が未記入だったため、
`start`実行時にユーザーへ意図を確認した。回答は「日本語タイトルの英訳・意訳をslugに反映したい」。

現状 `dev-tools/src/vcs/Provider.sh` の `to_slug()` は非ASCII文字を単純に除去するだけの機械的な
サニタイズ関数であり、日本語タイトルのissueでは英単語を含まない限りslugが空になり `"issue"` に
フォールバックする。この制約自体は `dev-tools/docs/spec/issue-mr-workflow.md` の「未決定事項・
懸念点」節（issue #3対応時に判明）に既に記録済みで、「より説明的なスラッグが必要になった場合は
ローマ字変換等の対応を別途検討する」と先送りされていた。本issueはこの先送り課題への対応。

`Provider.sh`（`gh`/`glab`/`jq`/git bashのみに依存する自己完結設計、`dev-tools/docs/spec/
shell-scripts.md`）に翻訳ロジックを追加するのは既存の設計方針から外れる。一方、`start`サブコマンド
を実行するAIエージェント（Claude Code自身）は既にissueタイトルを読んでおり、意訳を行う能力を
持っている。そこで「翻訳はAIエージェントが行い、bash側は引き続きサニタイズのみを担当する」設計を
採用する。

調査の過程で、slugをAI生成にすると実行のたびに異なる文言になり得る（非決定的）ため、`start`手順2
の「既にブランチがあるか」の確認を、slugまで含めた完全一致ではなくissue番号のprefixパターン一致に
変える必要があることが判明した。対応方式はユーザーに確認済み: **Provider.shに専用関数を追加せず、
SKILL.mdの手順文だけを修正する**（スコープを本issueの主題＝slugのリッチ化に近く保つため）。

## 実施内容

### 1. `.claude/skills/issue-mr-flow/SKILL.md` — `start`サブコマンド手順2の書き換え

現状（74-86行目）:
```
2. `.mrworkflow.json` の `branchPrefixTemplate` から算出されるブランチ名
   （既定 `feature-<issue番号>-<slug>`）が既にローカル/リモートに存在するか確認する。
   - 存在しなければ: `new_issue_branch <n> "<issue.Title>"` でブランチを作成・checkout・push、
     続けて `new_draft_merge_request <n> "<branch>" "<issue.Title>"` でDraft MRを作成する。
   - 既に存在すれば（セッション再開）: `sync_branch "<branch>"` でfetch・checkoutのみ行う。
```

以下へ書き換える:
- 既存ブランチの確認方法を、issue番号のprefixパターン一致に変更する
  （`.mrworkflow.json`の`branchPrefixTemplate`の`{issue}`をissue番号に置換し`{slug}`以降を`*`に
  した既定`feature-<issue番号>-*`で`git branch --list`・`git ls-remote --heads origin`を検索）。
  slugの中身は問わない、という方針を明記する。
- 新規作成の場合のみ、ブランチ作成前に「issueタイトルの意味を汲んだ英語フレーズ（3〜6語程度、
  スペース区切りでよい。kebab化・記号除去は`to_slug`側が行うため不要。直訳ではなく意訳でよい）」
  をAIエージェントが考える手順を追加する。
- `new_issue_branch <n> "<意訳フレーズ>"` でブランチ作成、続く `new_draft_merge_request` の
  タイトル引数は**従来どおり生のissueタイトル**を使う（意訳フレーズはブランチ名専用）。

### 2. `dev-tools/src/vcs/Provider.sh` — ドキュメンテーション目的の変数名・コメント更新（ロジック不変）

`new_issue_branch()`（179-194行目）の第2引数は`to_slug()`に渡す以外の用途がないため、ロジックは
一切変更しない。呼び出し側が渡す文字列の中身（生タイトル→AI生成の英語フレーズ）を変えるだけで
意図した動作になる。可読性のため以下のみ行う:
- ローカル変数名 `title` → `slug_source` にリネーム
- 関数直前のコメント（177-178行目）に、第2引数はslug化対象のテキストであり生issueタイトルで
  なくてよい旨（英語の意訳フレーズを推奨）を追記

### 3. `tests/test_vcs_provider.sh` — 回帰テスト1件追加

`to_slug`のロジック自体は変更しないため既存テストはすべて無修正で通る。「AIが生成した英語意訳
フレーズを渡す」という新しい利用契約が壊れていないことを明示するテストケースを、43-50行目の
`to_slug`ブロックに1件追加する:
```bash
assert_equal "$(to_slug 'enrich branch slug')" "enrich-branch-slug" "to_slug: スペース区切りの英語意訳フレーズはそのままkebab-caseになる（AIエージェント生成想定・issue #22）"
```

### 4. 設計反映メモ（flow-id 16で実施。このplan段階では作業しない）

`dev-tools/docs/spec/issue-mr-workflow.md`の「未決定事項・懸念点」節（627-640行目、全角文字のみ
issueタイトルのスラッグ化）を解決済みとして更新する。反映すべき骨子をworklogに書き残す:
- 採用方針（AIエージェントが意訳、Provider.shはサニタイズのみ）
- `start`手順2の既存ブランチ確認をissue番号prefixパターン一致に変更した理由（非決定性対応）
- `get_issue()`が返す未使用の`slug`フィールド（`Github.sh`/`Gitlab.sh`、機械的`to_slug(title)`）が
  実際のブランチ名slugとは一致しなくなる点は、元々死んだ出力であり実害なしという認識を残す
- 「提供関数」テーブルの`new_issue_branch`引数説明を更新

## 対象外

- `Provider.sh`側での翻訳API等の外部サービス呼び出し実装（既存の自己完結設計方針を維持するため）
- `get_existing_branch_for_issue`のような専用ヘルパー関数のProvider.sh追加（ユーザー確認によりSKILL.md
  手順文の修正のみで対応する方式を採用）
- `Github.sh`/`Gitlab.sh`の`get_issue()`が返す未使用`slug`フィールドの削除・修正
- 本issue自体のブランチ名（`feature-22-slug`）・Draft PR（#32）の遡及変更（既存ロジックで作成済み）

## 検証方法

1. `bash -n dev-tools/src/vcs/Provider.sh` で構文チェック
2. `bash tests/test_vcs_provider.sh` を実行し、既存アサーション＋追加した新規ケースが全て
   `passed=N failures=0` で通ることを確認
3. 副作用なしの手動確認: `source dev-tools/src/vcs/Provider.sh` の上で
   `to_slug "enrich branch slug"` → `enrich-branch-slug`、
   `to_slug "improve branch naming"` → `improve-branch-naming` のように複数の意訳候補で
   一貫した変換になることを確認
4. `get_issue_number_from_branch 'feature-22-enrich-branch-slug'` → `22` が返ることを確認し、
   意訳由来の多語slugでも既存のissue番号抽出ロジックが問題なく動くことを再確認
   （既存テストの`feature-42-something`パターンで既にカバーされているため念のための確認）
