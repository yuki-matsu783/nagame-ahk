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
