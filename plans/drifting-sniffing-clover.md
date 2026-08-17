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

### 調査結果

#### 1. SKILL.md flow-id 10・14・31への追記文言案

- flow-id 10（現在の文言: 「**調査を実施**し、結果を`plans/<plan名>.md`の「調査」章・worklogに
  記録する」）に、以下を追記する案:
  「あわせて調査結果を視覚的に分かりやすくまとめた自己完結HTML（TailwindCSS CDN方式）を
  `reports/<plan名>.html`として作成する。」
- flow-id 14（現在の文言: 「レビュー内容を取得し、調査結果を修正する。…（10〜14を合意まで
  繰り返す）」）に、調査結果を修正する際は`reports/<plan名>.html`も同期して更新する旨を追記する案:
  「対応が完了したコメントには対応内容を返信する（`reports/<plan名>.html`も調査結果と同期して
  更新する。10〜14を合意まで繰り返す）」
- flow-id 31（現在の文言: 「`plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする」）
  の削除対象に`reports/`を追加する案:
  「`plans/` `worklog/` `reports/` を削除し、`HANDOFF.md` を次タスクへリセットする」
- 上記3箇所いずれも既存の文体（体言止め・「〜する」で終える短文）を踏襲できることを確認した。

#### 2. docs-workflow.mdへの追加行案

worklog行の4列構成（対象・寿命・内容・運用）に倣い、以下の行を追加する案:

| ファイル | 対象 | 寿命 | 内容 | 運用 |
|---|---|---|---|---|
| `reports/<plan名>.html` | AI専用（人間も参照可） | push単位（worklogと同様、PR作成前の設計反映でまとめて削除） | 調査結果をmarkdownに加え、視覚的に分かりやすくまとめた自己完結HTML（TailwindCSS CDN方式） | flow-id 10で作成し、調査結果と同期して更新する。PR作成前の設計反映でworklogと一緒に削除しコミットに含める。`.gitignore`には加えない（ブランチ上のコミット履歴として残すため）。squash mergeにより、mainには残さない。 |

worklog行の「`.gitignore`には加えない」「squash mergeによりmainには残さない」という注記は、
`reports/`にもそのまま当てはまることを確認した（flow-id 31の削除対象、ライフサイクルとも同一）。

#### 3. directory-structure.mdツリーへの追加案

現行ツリーでは `plans/` `worklog/` が並んで配置されている。`reports/` は両者と役割が近い
（生成物の一時置き場）ため、`worklog/` の直後に追加する案:

```
├── plans/
├── worklog/
├── reports/                   # 調査結果をmarkdownに加え視覚的にまとめた自己完結HTML（.gitignore対象外、ブランチ単位で削除。docs-workflow.md参照）
```

#### 4. .mrworkflow.jsonへのreportsDir追加、およびProvider.sh改修の要否

- 現状`plansDir`/`worklogDir`は未使用の飾りではなく、`Provider.sh`の`get_branch_work_files`
  （250〜263行目）が実際に読んでおり、`git diff`/`git status`の対象パスとして使われている。
  この関数は`resume`サブコマンド（`issue-mr-resume`サブエージェント、
  `.claude/scripts/docs/spec/issue-mr-workflow.md`151行目）が「ブランチ固有のplan/worklogファイル
  一覧」を集計するために呼んでいる。
- **`reports/`を追加する場合、`.mrworkflow.json`に`"reportsDir": "reports"`を追加するだけでなく、
  `get_branch_work_files`の実装（`plans_dir`/`worklog_dir`を読む2行と、それに続く`git diff`/
  `git status`の対象パス）に`reports_dir`を追加しないと、resumeの「現在地サマリ」が
  `reports/<plan名>.html`の存在を検知できない。** これは設定ファイルの追加だけでは完結しない、
  Provider.sh本体（および対応するspec: `.claude/scripts/docs/spec/issue-mr-workflow.md`の
  `get_branch_work_files`の説明・`issue-mr-resume.md`エージェント定義内の文言）の改修を伴う。
  実装（コード変更）は本issueの範囲では調査結果への記録に留め、実際の変更は作業計画
  （flow-id 15）を経てflow-id 21で行う。

#### 5. markdown-frontmatter.mdの適用要否

`.claude/rules/markdown-frontmatter.md`の規約はYAML frontmatterの付与規約であり、対象は
一貫して「markdownファイル」（`type`の値一覧も`.md`ファイルのみを列挙）。`reports/*.html`は
markdownではないため、この規約は適用されない。追加の対応は不要（現状の理解通り）。

#### 6. 「reports」という名称の衝突確認

`.claude/hooks/lib/UsageTracking.sh`・`post-push-usage-report.sh`等、既存の「対応工数レポート」
機能はファイル名・コメント中に英単語として「report(s)」を含むが、ディレクトリ名としての
`reports/`は使用していない（対応工数レポートのローカル状態は`usage/`配下に保存される。
`.gitignore`の該当エントリでも`/usage/`であり`/reports/`ではない）。ディレクトリ名としての
衝突は無いことを確認した。ただし将来的な紛らわしさ回避のため、docs-workflow.mdの説明文で
「調査結果のHTML版」であることを明記し、「対応工数レポート」と紛れないようにする（案の文中に
既に反映済み）。

#### 7. TailwindCSS CDN方式の外部依存についての確認

- リポジトリ内に、Webページ的な外部CDN依存の前例は無い（本プロジェクトはAutoHotkey v2の
  デスクトップ常駐スクリプトであり、これまでHTML/CSS/JSを扱う成果物自体が存在しなかった）。
  今回が最初の外部CDN依存になる。
- `security-review`スキル・既存の`.claude/rules/`配下に、外部CDN利用を禁止・制限する明文化された
  ルールは見当たらなかった。ただし新規に外部ネットワーク依存を導入する変更であるため、
  作業計画（flow-id 15）の中で、この点を受け入れ条件・懸念点として明記し、人間のレビューで
  明示的に合意を得ることを推奨する（今回の調査計画のContextで既にトレードオフとして
  言及済みだが、作業計画でも改めて触れる）。

#### 8. reports/<plan名>.html の最小限の構成案

- `<head>`にTailwindCSS CDN（`<script src="https://cdn.tailwindcss.com"></script>`）を読み込み、
  最小限のタイトル（plan名・issue番号）を`<title>`に設定する。
- 本文構成は、対応する`plans/<plan名>.md`の「調査」章の見出し構造
  （調査の目的／調査項目／調査対象外／調査方法／調査結果）をそのままセクションとして踏襲し、
  markdown版の内容を要約・視覚化する（表・カード・強調ボックス等、調査結果の性質に応じて
  Tailwindのユーティリティクラスで表現する）。踏襲する見出し構造を固定フォーマットとして
  強制はせず、調査結果の内容に応じて柔軟に構成してよい（issueごとに調査結果の分量・性質が
  大きく異なるため。実例: 本ドキュメントの調査項目8参照）。
- ダークモード対応は必須としない（閲覧環境を問わず可読性を保てる配色を選べば十分。
  必要ならTailwindの`dark:`バリアントを使ってよいという程度の緩い指針に留める）。
- 詳細なHTML実装そのものは、各issueの調査実施時（flow-id 10）に個別に執筆する。本項の結論は
  「毎回どの程度の型に従うか」の方針レベルであり、テンプレートファイルとして固定化はしない
  （テンプレート化するかどうかは、実際に複数件運用してみてから判断する）。

## 検証方法

本issueはドキュメント・ルール変更が中心のため、コード実行によるテストは無い。以下で検証する。

- 更新後の `SKILL.md` / `docs-workflow.md` / `directory-structure.md` を通読し、既存の表・文体との
  整合性、矛盾の有無を確認する。
- 可能であれば、次回以降の実際のissue対応（別issueの調査実施フェーズ）で本フローに従い
  `reports/<plan名>.html` を1件試作し、TailwindCSS CDN方式で意図通り表示されるかブラウザで
  目視確認する（このissue自体のスコープに含めるかは作業計画で判断する）。
