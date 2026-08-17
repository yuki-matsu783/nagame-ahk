---
title: 調査ドキュメントをmarkdownとhtmlで作る（worklog push1）
type: log
description: issue #48対応、調査計画フェーズ（flow-id 4）の作業ログ
tags: [issue-mr-flow, reports, html, worklog]
keywords: [調査計画, TailwindCSS, reports, worklog, plans, Explore]
---

# 調査ドキュメントはmarkdownとhtmlで作る（issue #48）— push1

## 調査計画フェーズ（flow-id 4）

### issue #48の準備（本フロー着手前）

- issue #48は当初タイトルが「調査ドキュメントは**readme**とhtmlで作る」、本文が全項目未記入の
  テンプレート状態だった。ユーザーから「本当にやりたいのはmarkdown」との指摘を受け、着手前に
  タイトルを「調査ドキュメントは**markdown**とhtmlで作る」に修正し、本文4項目
  （目的・現状・期待する動作・受け入れ条件）を、ユーザーへの2問のAskUserQuestion
  （対象は調査結果のみ／目的はインフォグラフィックとしての視認性向上）で得た回答をもとに埋めた。

### `start 48`

- `get_issue 48` でissue取得、`test_issue_sections` で4見出しの過不足なしを確認。
- 既存ブランチ・PRは無かったため新規作成。ブランチslugは意訳フレーズ
  `add html version of investigation docs` を使用（`get_issue`が返す機械的な`slug`フィールド
  （`markdown-html`、日本語タイトルから非ASCII文字を除去しただけの値）はSKILL.md 3aの
  「意訳フレーズ」の要件を満たさないため使わず、別途考えた）。
- `feature-48-add-html-version-of-investigation-docs` ブランチ・Draft PR #57を作成。
  PR作成は1回目`gh pr create`が「No commits between main and ...」で失敗し、
  `add_empty_commit_for_draft_mr`による空コミット追加後のリトライで成功（Provider.shの既知の挙動）。

### Explore調査（プラン設計前の事前調査）

Exploreエージェント1体を使い、以下を確認（詳細はエージェントの報告そのまま。要点のみ記録）:

- `.claude/skills/issue-mr-flow/SKILL.md` の flow-id 4/9/10-14/15/26/31 の役割を確認。
  flow-id 31で`plans/``worklog/`が**削除**される（=どちらもmainには残らず、ブランチ/PRの
  コミット履歴にのみ残る）ことを確認。`docs-workflow.md`の「plansは永続」という記述は
  「mainの現在のツリーに残る」ではなく「ブランチ・PRのコミット履歴として残る」という意味だと
  解釈した（現行`plans/`ディレクトリが空でindex.jsonlのみなのも裏付け）。
- `.claude/rules/docs-workflow.md`のドキュメント運用表、`directory-structure.md`のツリー構成、
  `markdown-frontmatter.md`のtype一覧（`plans/*.md`に対応するtype値が実は定義されていない、
  という既存の不整合も判明。今回のissueとは直接関係ないため深追いせず記録に留める）を確認。
- リポジトリ全体を「Artifact」「markdown→html変換」で検索した結果、**既存の仕組みは一切無い**
  ことを確認（ゼロから設計する）。
- `dev-tools/`配下にもmd→html変換系のスクリプトは無い。
- `.mrworkflow.json`は`plansDir`/`worklogDir`等のパス設定のみで、出力フォーマットに関する
  設定キーは存在しない。
- `HANDOFF.md`は空テンプレート状態（このissueに関する記載なし）。

### 主要な設計判断（ユーザーとのAskUserQuestion）

1. **生成方式**: Claude Code組み込みのArtifact機能（claude.aiへの外部公開）ではなく、
   「自己完結HTMLをリポジトリにコミット」を選択。理由: issue-mr-flowは`AGENTS.md`
   （エージェント共通ルール）配下の仕組みであり、Claude Code以外のAIツールでも実行できる
   必要がある。Claude Code固有のArtifact機能に依存すると、他ツールでの再現性が失われる。
2. **保存場所・命名**: 当初`plans/<plan名>.html`案を提示したが、ユーザーの回答は
   「`/reports`配下に置く。ライフサイクルはブランチ単位で削除されるのでplanやworklogと同じ」。
   flow-id 31の解読（上記）により、plansもworklogも実際にはブランチ単位で削除される
   （mainには残らない）ことが分かっているため、`reports/<plan名>.html`はworklogと同じ
   ライフサイクル（flow-id 10で作成、10〜14で調査結果と同期更新、flow-id 31で削除、
   `.gitignore`には加えない）として計画に落とし込んだ。
3. **スタイリング**: ユーザーから会話の途中で「HTMLはtailwindcssで書くのが良いかも。
   それ以上にoutputトークンの量と表現力のバランスが良いものがあればそれを採用しても良い」
   との追加インプットあり。TailwindCSS（CDN経由）を第一候補とし、閲覧時にインターネット接続が
   必要になる点はトレードオフとして許容する方針とした（GitHub PRレビュー自体が既に
   インターネット接続前提のため実害は小さいと判断）。

### 調査計画の内容

`plans/drifting-sniffing-clover.md`に、上記3つの確定方針をContext節の「既に確定した前提」として
明記した上で、残る確認事項（SKILL.md/docs-workflow.md/directory-structure.md/.mrworkflow.jsonへの
具体的な反映文言、`reports`という語の`usage/`対応工数レポート機能との衝突有無、TailwindCSS CDNの
外部依存についてのセキュリティ上の懸念有無等）を「調査項目」として整理した。調査結果の記録は
本計画の合意後、flow-id 10（調査実施）で追記する。

## 判断に迷った点

- flow-id 31の「`plans/` `worklog/` を削除」という文言と、docs-workflow.mdの
  「plansは生成時点のスナップショットとして永続」という記述が一見矛盾するように見えた。
  「PRがflow-id 31実施前にマージされてしまった場合の対処」節の記述（worklogは
  squash mergeの対象からflow-id 31で除外されmainに残らない設計）と突き合わせ、
  「ブランチ・PRのコミット履歴には残るが、main上のツリーには残らない」という解釈で
  整合させた。この解釈が正しいかは、flow-id 10以降の実際の運用（過去のマージ済みPRの
  コミット履歴を実際に辿れるか等）で裏取りの余地がある。

## 次にやること（push2以降）

- 調査計画のレビュー完了後、flow-id 10として調査項目1〜8を実施し、`plans/drifting-sniffing-clover.md`
  の「調査結果」章に記録する。
