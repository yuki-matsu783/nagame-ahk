---
title: 調査ドキュメントをmarkdownとhtmlで作る（調査計画）
type: rule
description: issue-mr-flowの調査結果をmarkdownに加え自己完結HTML（reports/配下）でも生成する仕組みの調査計画
tags: [issue-mr-flow, docs-workflow, reports, html]
keywords: [調査結果, reports, TailwindCSS, worklog, plans, docs-workflow, SKILL.md, 自己完結HTML]
---

# 調査ドキュメントはmarkdownとhtmlで作る（issue #48）

## Context

issue #48: issue-mr-flowの「調査を実施」ステップ（SKILL.md flow-id 10〜14）で作成する調査結果は、
現状 `plans/<plan名>.md` の「調査」章と `worklog/` にmarkdownのみで記録されている。markdownは
構造化された記録として優れるが、表現力に限界があり、視覚的な理解を促す表現（図解・強調・
インフォグラフィック的な見せ方）がしづらい。issueの目的は、調査結果をmarkdownに加えて表現の
拡張性が高いHTMLでも残すことで、視認性・理解を促進すること。対象は「調査結果」のみ（調査計画・
作業計画は対象外）。

このセッションで実施したExploreエージェントによる事前調査、および人間との対話により、以下の
主要な設計判断は既に確定している。今回の調査計画は、この前提のもとで残りの確認事項（既存の
命名・記法との整合、具体的な反映箇所の特定）を対象とする。

**既に確定した前提**

- 生成方式: Claude Code組み込みのArtifact機能（claude.ai外部公開）は使わず、外部リソース非依存の
  自己完結HTMLをエージェント自身が執筆し、リポジトリへ直接コミットする。issue-mr-flowは
  `AGENTS.md`（エージェント共通ルール）の対象であり、Claude Code以外のAIツールでも実行できる
  必要があるため、Claude Code固有機能への依存は避ける。
- 保存場所・命名: `reports/<plan名>.html`（`plans/<plan名>.md`と同じ名前・拡張子のみhtml）。
- ライフサイクル: `worklog/` と同じ扱い（flow-id 10で作成、10〜14のレビュー往復で
  調査結果と同期して更新、flow-id 31でworklogと一緒に削除。squash mergeによりmainには残らず、
  ブランチ／PRのコミット履歴にのみ残る）。`.gitignore`には加えない。
- スタイリング: TailwindCSS（CDN経由 `<script src="https://cdn.tailwindcss.com">`）を第一候補とする。
  ビルドステップ無しでユーティリティクラスによる整形ができ、出力トークン量と表現力のバランスが
  良いため。閲覧時にインターネット接続が必要になる点はトレードオフとして許容する
  （GitHub上でのPRレビュー自体が既にインターネット接続を前提とするため実害は小さいと判断）。
  他により良いバランスの手法が見つかった場合はそちらを採用してよい。

## 調査

### 調査の目的

上記の確定方針を、実際のドキュメント（SKILL.md・docs-workflow.md・directory-structure.md・
.mrworkflow.json等）へどう反映するか、既存の記法・表構成・命名規則との整合性を確認したうえで、
具体的な反映箇所・文言案を確定する。これにより、次段階（flow-id 15の作業計画）で迷いなく
編集に着手できる状態にする。

### 調査項目

1. `.claude/skills/issue-mr-flow/SKILL.md` のflow-id 10（調査実施）・14（レビュー反映ループ）・
   31（plans/worklog削除）の該当行を確認し、`reports/<plan名>.html`の生成・更新・削除を
   どの文言で追記するか、既存の文体（「〜する」体言止め等）に合わせて案を作る。
2. `.claude/rules/docs-workflow.md`「ドキュメント運用」表に、`reports/<plan名>.html`の行を
   worklog行の記法（対象・寿命・内容・運用の4列）にならって追加する。worklog行の
   「`.gitignore`には加えない」「squash mergeによりmainには残さない」という注記が
   reportsにもそのまま当てはまるか再確認する。
3. `.claude/rules/directory-structure.md` のツリー図に `reports/` を追加する位置・コメント文言を、
   既存の `worklog/` `plans/` の並び・簡潔なコメントスタイルに合わせて検討する。
4. `.mrworkflow.json` に `plansDir` / `worklogDir` と並ぶ形で `reportsDir` キーを追加すべきか
   （現状`Provider.sh`側でこの設定値を読んでいる箇所が無いため、追加する場合は将来の
   自動化拡張に備えた設定値追加に留まる。追加の要否と、追加する場合の値`"reports"`を確認する）。
5. `reports/*.html` に `.claude/rules/markdown-frontmatter.md` のfrontmatter規約が適用されるか
   確認する（対象はmarkdownファイルのみのため非該当と見込まれるが、念のため規約本文を再確認する）。
6. `reports/` というディレクトリ名が、既存の「対応工数レポート」機能（`usage/`配下、
   `.claude/hooks/lib/UsageTracking.sh`等）の用語・ディレクトリと混同されないか確認する
   （grep調査は本セッションで実施済みで衝突なしを確認済みだが、念のため`usage/`関連ドキュメントの
   文言に「reports」という語が使われていないか再確認する）。
7. TailwindCSS CDN方式について、CDNのURLが外部リソースとしてリポジトリのセキュリティ方針
   （`security-review`関連の既存ルール等）に抵触しないか、他に類似の外部CDN依存の前例が
   リポジトリ内にあるか確認する。
8. `reports/<plan名>.html` の最小限の構成案（見出し構造・調査結果markdownとの対応関係、
   ダークモード対応要否等）をたたき台として整理する。ただし詳細なHTML実装そのものは
   flow-id 15の作業計画・flow-id 10以降の調査実施時に個別issueごとに執筆するものであり、
   ここでは「毎回どの程度の型に従うか」の方針レベルに留める。

### 調査対象外

- `docs/spec/`・`docs/ddr/` へのissue #48自体の反映（flow-id 26で実施するため、今回の調査計画の
  スコープ外）。
- 「調査計画」「作業計画」章のHTML化（issueの要望は「調査結果のみ」と明示されているため対象外）。
- `usage/`配下の対応工数レポート機能自体の変更（名称の衝突有無だけを確認し、実装には触れない）。
- `describe`サブコマンド（MR description生成）へのreportsリンク追加（有用ではあるが、issueの
  受け入れ条件には含まれておらず、必要なら別issueとして起票する）。
- TailwindCSS以外のスタイリング手法の網羅的な比較検証（明らかに優れる代替がその場で見つかった
  場合のみ乗り換えを検討し、体系的な比較調査は行わない）。

### 調査方法

- 上記1〜4は該当ファイルをReadし、既存の記法・表構成を確認したうえで、具体的な追記文言の案を
  `plans/drifting-sniffing-clover.md`の「調査結果」（本計画合意後、flow-id 10で追記）にまとめる。
- 5〜6はGrepで対象キーワード（`reports`, `frontmatter`対象type一覧, `対応工数`等）を確認する。
- 7はリポジトリ内の既存の外部リソース利用例（あれば）をGrepで探し、無ければ「前例なし、今回が
  最初の外部CDN依存」である旨を記録する。
- 8は前提として確定済みの方針（TailwindCSS・reports/配下）をもとに、簡潔な構成案を文章でまとめる
  （実際のHTMLファイルは作成しない。あくまで方針メモ）。

## 検証方法

本issueはドキュメント・ルール変更が中心のため、コード実行によるテストは無い。以下で検証する。

- 更新後の `SKILL.md` / `docs-workflow.md` / `directory-structure.md` を通読し、既存の表・文体との
  整合性、矛盾の有無を確認する。
- 可能であれば、次回以降の実際のissue対応（別issueの調査実施フェーズ）で本フローに従い
  `reports/<plan名>.html` を1件試作し、TailwindCSS CDN方式で意図通り表示されるかブラウザで
  目視確認する（このissue自体のスコープに含めるかは作業計画で判断する）。
