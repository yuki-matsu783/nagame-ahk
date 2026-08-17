---
title: dev-toolsをAI専用と人間専用に分ける（調査計画）
type: rule
description: dev-tools配下のスクリプト・設計書のうちAIエージェントが利用するものを.claude配下へ分離するための調査計画
tags: [dev-tools, directory-structure, plugin-distribution]
keywords: [dev-tools, scripts, AI専用, 人間専用, プラグイン配布, Provider.sh, issue-mr-workflow]
---

# dev-toolsをAI・人間が利用するものと人間のみが利用するもので分ける（issue #24）

## Context

issue #24: 現在 `dev-tools/` 配下には、AIエージェント（Claude Code）が `.claude/skills/*` 経由で
能動的に呼び出すスクリプト（`vcs/Provider.sh` 等）と、人間が手動実行する開発補助スクリプト
（`build.sh` 等）が混在している。issue本文によれば、この混在が「プラグインとして配布するときに
困る」という問題を引き起こす。Claude Codeのplugin配布は `.claude/` 配下一式をパッケージ化する
想定のため、AI専用スクリプト・設計書が `dev-tools/`（`.claude/`の外）に置かれていると、配布物に
含まれない、または配布の境界が曖昧になる。

期待する動作は「AIが利用するものは`.claude`のscripts配下に入れる」、受け入れ条件は
「AIが利用するスクリプトが`scripts/src`配下」「設計書が`scripts/docs`配下」に置かれること。
両者を合わせると、移行先は `.claude/scripts/src/`・`.claude/scripts/docs/` と解釈できる。

このセッションの事前調査（Exploreエージェント）で、`dev-tools/` 配下の構成・参照元は概ね把握できて
いるが、flow定義（`.claude/skills/issue-mr-flow/SKILL.md`）に従い、まず調査計画として調査の目的・
範囲・方法を提示し、合意を得た上で調査結果を正式に記録する。

## 調査

### 調査の目的

`dev-tools/` 配下の各ファイル（スクリプト・spec・DDR）について、AI専用／人間専用／両方のいずれかを
判定し、移行対象・移行先・更新が必要な参照箇所を確定するための材料を揃える。ここで確定した事実を
もとに、次段階（flow-id 15の作業計画）で具体的な移行方針・ディレクトリ構成を決定する。

### 調査項目

1. `dev-tools/src/`・`dev-tools/docs/`（`spec/`・`ddr/`）配下の全ファイルを列挙し、各ファイルを
   以下のいずれかに分類する。
   - AI専用: `.claude/skills/*/SKILL.md`・`.claude/rules/*.md`・`.claude/hooks/*.sh` から
     `source`・実行呼び出しされているもの、およびその設計書
   - 人間専用: 上記から呼ばれておらず、`DEVELOPERS.md` 等に人間の手動実行手順として書かれているもの
   - 両方／判断が分かれるもの（例: 出力はAI可読だが実行主体は人間、等）
2. `dev-tools/src/` へのパス参照を持つ全箇所（skill・hook・rule・テスト・`DEVELOPERS.md`・
   `index.md`・`.mrworkflow.json` 等）を洗い出し、移行時にパス書き換えが必要な箇所をリスト化する。
3. `.claude/hooks/` と `dev-tools/src/` の役割分担を整理する（hookはハーネスが自動起動する
   インフラ、`dev-tools/src/` はskillの手順としてAIが能動的に実行する処理本体、という区別が
   成立するか確認する）。
4. `dev-tools/docs/spec/`・`dev-tools/docs/ddr/` の各ファイルについて、AI専用スクリプトの
   設計書・意思決定record かどうかを判定する。特に以下は複数のスクリプト・複数の利用者にまたがる
   ため、単純にAI専用／人間専用と分類できるか個別に確認する。
   - `shell-scripts.md`（AI専用スクリプトと`build.sh`（人間専用）の両方を対象とするbash規約）
   - 既にマージ済みのDDR（`0001`〜`0012`）を移動対象に含めるか、移動する場合`git mv`で履歴を
     保持できるか
5. issue本文の「プラグインとして配布するときに困る」という文脈について、リポジトリ内に
   plugin配布に関する既存の設計文書・記述がないか確認する（無ければ、今回の移行がそのための
   最初の対応になる旨を記録する）。
6. `.claude/rules/directory-structure.md` における `dev-tools/` の記載内容（現状は「開発者向け
   ツール」という前提の説明になっている）を確認し、更新が必要な箇所を特定する。
7. 移行先ディレクトリ構成の叩き台（`.claude/scripts/src/`・`.claude/scripts/docs/{spec,ddr}/`）を
   既存の `.claude/` 配下構成（`rules/`・`skills/`・`hooks/`）と対比し、命名・階層の整合性を確認する。
8. 今回のスコープ外だが移行時に気づいた既知のstale参照（`.claude/agents/issue-mr-resume.md`が
   旧PowerShell版関数名のまま、`DEVELOPERS.md`が`build.ps1`のままなど）を記録し、別issue化するか
   本issueのついでに直すかの判断材料として残す。

### 調査対象外

- 実際のファイル移動・パス書き換え作業自体（flow-id 15以降の作業計画・実施フェーズで行う）。
- `build.sh`・`extract-frontmatter.sh`（人間専用と判定見込み）を `.claude/` 配下へ移すかどうかの
  是非（issue #24の受け入れ条件はAIが利用するものの移行が主眼のため、人間専用スクリプトは
  現状の`dev-tools/`に residual として残す前提で調査する。必要なら作業計画時に扱いを明記する）。

### 調査方法

Exploreサブエージェントによる `dev-tools/`・`.claude/` 配下のgrep・読み込み調査、および関連する
`.claude/rules/*.md`・`dev-tools/docs/spec/*.md` の内容確認。調査結果は本ファイルの「調査」章に
追記し、`worklog/` に詳細な調査ログを記録する。
