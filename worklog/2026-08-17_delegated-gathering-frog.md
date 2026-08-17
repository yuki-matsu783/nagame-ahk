---
title: dev-toolsをAI専用/人間専用に分ける作業ログ
type: log
description: issue #24対応の調査・作業ログ
tags: [dev-tools, directory-structure, plugin-distribution]
keywords: [dev-tools, scripts, AI専用, 人間専用, プラグイン配布]
---

# issue #24 作業ログ

## 調査計画フェーズ（flow-id 4）

- Exploreサブエージェントで `dev-tools/` 配下の全ファイル・参照元を事前調査し、その結果を踏まえて
  `plans/delegated-gathering-frog.md` に調査計画を作成した。
- 事前調査で判明した主な事実（flow-id 10の調査実施フェーズで正式に記録する予定の下書き）:
  - AI専用と判定: `vcs/Provider.sh`, `vcs/Github.sh`, `vcs/Gitlab.sh`, `create-commit.sh`,
    `create-issue.sh`, `archive-reentrant-plan.sh`、および設計書 `issue-mr-workflow.md`。
  - 人間専用と判定: `build.sh`, `extract-frontmatter.sh`、設計書 `distribution.md`。
  - 判断が分かれる: `shell-scripts.md`（AI専用スクリプトと人間専用の`build.sh`両方を対象とする
    bash規約）、`extract-frontmatter.md`/DDR 0008（実行主体は人間だが出力はAI可読データ）。
  - `dev-tools/src` への参照箇所は skills（issue-mr-flow, issue-create, commit）、hooks
    （session-start.sh, post-push-usage-report.sh, post-push-compact-prompt.sh,
    block-direct-git-commit.sh メッセージ文言）、rules（git-workflow.md, plan-mode-safety.md,
    shell-script-style.md, directory-structure.md, powershell-encoding.md(stale)）、
    tests（test_vcs_provider.sh 等3本）、`DEVELOPERS.md`（stale）、`index.md` に及ぶ。
  - `.mrworkflow.json` の `specDirs`/`ddrDirs` は dev-tools/docs/spec, dev-tools/docs/ddr を
    指しており、spec/ddrを分割移動する場合は要更新。
  - リポジトリ内に「プラグイン配布」に関する既存記述は0件（issue本文のみ）。
  - `.claude/rules/directory-structure.md` は `dev-tools/` を「開発者向けツール」前提で説明して
    おり、実態（AI専用スクリプトが大半）と乖離している。
  - 既知のstale参照（`.claude/agents/issue-mr-resume.md`が旧PowerShell関数名のまま、
    `DEVELOPERS.md`が`build.ps1`のまま）は本issueのスコープ外だが記録した。

## 調査実施フェーズ（flow-id 10）

- PR #55への人間レビュー完了の合図を受け、`comments all`で未解決スレッドが無いことを確認した
  （自動投稿の対応工数レポートコメントのみで、レビュースレッドは無し）。
- 上記の下書きを、`plans/delegated-gathering-frog.md`の「調査」章に「調査結果」として正式に
  追記した。追記にあたり、以下を追加でリポジトリへ直接grepし、Explore結果の裏取りを行った。
  - `プラグイン`/`plugin`のリポジトリ全体grep → 自作の`plans/`/`worklog/`以外に該当箇所0件を再確認
  - `dev-tools/src`参照箇所の再grep → Explore結果と一致
  - `.claude/agents/issue-mr-resume.md`・`DEVELOPERS.md`のstale参照を個別grepで再確認
- 調査結果のポイント:
  - AI専用: `vcs/Provider.sh`, `vcs/Github.sh`, `vcs/Gitlab.sh`, `create-commit.sh`,
    `create-issue.sh`, `archive-reentrant-plan.sh`, 設計書`issue-mr-workflow.md`,
    DDR `0002`〜`0007`,`0009`〜`0012`
  - 人間専用: `build.sh`, `extract-frontmatter.sh`, 設計書`distribution.md`, DDR `0001`
  - 判断が分かれる: `shell-scripts.md`, `extract-frontmatter.md`, DDR `0008`
  - 移行先叩き台: `.claude/scripts/src/`・`.claude/scripts/docs/{spec,ddr}/`
  - プラグイン配布に関する既存記述は0件（今回が最初の対応）
  - `.claude/rules/directory-structure.md`の`dev-tools/`記載は実態と乖離しており更新が必要
- 次は結果レビュー待ち（flow-id 13〜14）。完了後、調査結果をもとに作業計画（flow-id 15）を
  Planモードで作成する。

## 調査結果レビュー対応（flow-id 14）

- 人間からチャット上で「`extract-frontmatter.sh`と判断が分かれる部分も移行して」との指摘を受けた。
  PRコメントではなくチャットでの直接指摘だったため、`plans/delegated-gathering-frog.md`の
  「調査結果」に8番として追記する形で反映し、影響する既存の表（1番の分類表・6番の移行先構成図・
  調査対象外）にも参照注記を追加した。
- 反映内容: `extract-frontmatter.sh`・`extract-frontmatter.md`・`shell-scripts.md`・DDR`0008`を
  移行対象に含める。結果、`dev-tools/`に残るのは`build.sh`・`distribution.md`・DDR`0001`のみ
  （いずれもexe配布ビルド専用）という見込みに変わった。
  `shell-scripts.md`は`build.sh`の規約も含むため、移行後の参照維持方法は作業計画で検討する
  課題として明記した。

## 作業計画フェーズ（flow-id 15）

- 調査結果をもとに、Planモードで作業計画を作成した。`plans/delegated-gathering-frog.md`に
  「作業計画」章を追記（既存の「調査」章は保持。plan-mode-safety.mdの規則6に沿い、Planモード
  再突入時にハーネスが同じplanファイルパスを提示したため、Editツールで追記する形にし
  archive不要と判断した：今回は「別タスク」ではなく同一タスクの継続のため）。
- 作業計画作成にあたり`.claude/agents/issue-mr-resume.md`を精読した結果、当初「移行対象パスの
  書き換えのみ」で足りると想定していたが、同ファイル全体が旧PowerShell版`Provider.ps1`・
  PascalCase関数を前提とした記述であり、単純なパス書き換えでは済まない全面的な作り直しが
  必要と判明した。dev-tools分離とは独立した既存バグと判断し、本issueのスコープからは除外、
  別issue化を推奨する方針に変更した（調査結果7番の想定から変更）。
- 作業計画の主な内容: `.claude/scripts/{src,docs/{spec,ddr}}/`へのファイル移動（`git mv`）、
  `dev-tools/docs/README.md`⇔新規`.claude/scripts/docs/README.md`の分割、パス参照の一括更新
  （skills/hooks/rules/tests/index.md/.mrworkflow.jsonデフォルト値）、
  `directory-structure.md`・`markdown-frontmatter.md`の更新、`index.jsonl`再生成。
- 人間の承認を得た。次はcommit・push・レビュー依頼（flow-id 17）。
