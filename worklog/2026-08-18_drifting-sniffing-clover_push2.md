---
title: 調査ドキュメントをmarkdownとhtmlで作る（worklog push2）
type: log
description: issue #48対応、調査実施フェーズ（flow-id 10）の作業ログ
tags: [issue-mr-flow, reports, html, worklog]
keywords: [調査結果, reports, TailwindCSS, get_branch_work_files, Provider.sh]
---

# 調査ドキュメントはmarkdownとhtmlで作る（issue #48）— push2

## 調査実施フェーズ（flow-id 10）

`plans/drifting-sniffing-clover.md` の調査項目1〜8をすべて実施し、「調査結果」章に記録した。
要点のみここに残す（詳細はplanファイル本体を参照）。

- 1〜3: SKILL.md flow-id 10/14/31、docs-workflow.mdのドキュメント運用表、
  directory-structure.mdのツリー図それぞれへの具体的な追記文言案を確定した。
  いずれも既存の記法（体言止め・4列表・簡潔なツリーコメント）を踏襲できる。
- 4（重要な発見）: `.mrworkflow.json`の`plansDir`/`worklogDir`は未使用の飾りではなく、
  `Provider.sh`の`get_branch_work_files`（250〜263行目）が`resume`サブコマンドの
  「現在地サマリ」生成のために実際に読んでいた。`reportsDir`を追加するだけでは不十分で、
  `get_branch_work_files`本体の改修（`reports_dir`を`git diff`/`git status`の対象パスに追加）が
  伴わないと、`resume`が`reports/<plan名>.html`の存在を検知できないままになる。この改修は
  作業計画（flow-id 15）でスコープに含め、flow-id 21で実施する。
- 5: markdown-frontmatter.mdの規約は`.md`専用であり、`reports/*.html`には非該当。対応不要。
- 6: `reports/`というディレクトリ名は、既存の「対応工数レポート」機能（`usage/`配下）と
  ディレクトリ名としては衝突しないことを確認した。
- 7: リポジトリ内に外部CDN依存の前例は無く、今回が最初。明文化された禁止ルールも無いが、
  新規の外部ネットワーク依存であるため、作業計画で懸念点として明記し人間の合意を得ることを
  推奨する結論とした。
- 8: `reports/<plan名>.html`の構成方針（TailwindCSS CDN読み込み、plans/*.mdの調査章の見出しを
  踏襲した本文構成、ダークモード対応は必須でない、テンプレート化はしない）を整理した。

## 次にやること

- 調査結果のレビュー完了後、flow-id 15として作業計画を作成する。作業計画には少なくとも
  以下を implementation スコープとして含める見込み:
  - SKILL.md flow-id 10/14/31の文言更新
  - docs-workflow.md・directory-structure.mdへの反映
  - `.mrworkflow.json`への`reportsDir`追加
  - `Provider.sh`の`get_branch_work_files`改修（`reports_dir`対応）
  - 対応する`.claude/scripts/docs/spec/issue-mr-workflow.md`・`issue-mr-resume.md`の記述更新
