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
- `build.sh`（人間専用と判定。exe配布ビルド専用でAI・移行対象ファイルのいずれとも無関係なため）を
  `.claude/` 配下へ移すかどうかの是非（`dev-tools/`に残す前提で調査する）。
  **`extract-frontmatter.sh`は当初「人間専用のため対象外」としていたが、人間からの指示
  （下記「調査結果」8番）により移行対象に含めることとした。**

### 調査方法

Exploreサブエージェントによる `dev-tools/`・`.claude/` 配下のgrep・読み込み調査、および関連する
`.claude/rules/*.md`・`dev-tools/docs/spec/*.md` の内容確認。調査結果は本ファイルの「調査」章に
追記し、`worklog/` に詳細な調査ログを記録する。

### 調査結果

#### 1. `dev-tools/` 配下ファイルの分類

**`dev-tools/src/`**

| ファイル | 分類 | 根拠 |
|---|---|---|
| `vcs/Provider.sh` | AI専用 | `.claude/skills/issue-mr-flow/SKILL.md`が`source`して使う中核。`.claude/hooks/session-start.sh`・`post-push-usage-report.sh`・`post-push-compact-prompt.sh`からも`source`される |
| `vcs/Github.sh` / `vcs/Gitlab.sh` | AI専用 | `Provider.sh`経由でのみ使う設計（ファイル冒頭コメントで明記）。単体では呼ばれない |
| `create-commit.sh` | AI専用 | `.claude/skills/commit/SKILL.md`から呼び出される、`commit`スキル専用ラッパー。`block-direct-git-commit.sh`フックを迂回する機構的理由で存在 |
| `create-issue.sh` | AI専用（人間も直接実行可） | `.claude/skills/issue-create/SKILL.md`から呼び出される。スクリプト自身に「人間が直接実行してもよい」と明記されているが主用途はAI |
| `archive-reentrant-plan.sh` | AI専用 | `.claude/rules/plan-mode-safety.md`（`alwaysApply: true`）がPlanモードre-entry時の対処として実行を指示。人間向け導線なし |
| `build.sh` | 人間専用 | `.claude/`配下のどこからも呼び出されない。`DEVELOPERS.md`が唯一の実行手順記載箇所（開発者の手動実行） |
| `extract-frontmatter.sh` | 人間専用（現状）→**移行対象に含める**（8番参照） | `.claude/`配下のskill/hookから自動呼び出しされない。`dev-tools/docs/spec/extract-frontmatter.md`に「手動で再実行」と明記。出力（`index.jsonl`）はAI可読だが実行主体は人間 |

**`dev-tools/docs/spec/`**

| ファイル | 分類 | 根拠 |
|---|---|---|
| `issue-mr-workflow.md` | AI専用スクリプトの設計書 | `issue-mr-flow/SKILL.md`が「本ファイルは`issue-mr-workflow.md`の実装」と明言。`Provider.sh`等AI専用スクリプト群の正史仕様 |
| `shell-scripts.md` | 判断が分かれる→**移行対象に含める**（8番参照。`build.sh`向け参照の維持方法は作業計画で検討） | bashスクリプト共通規約。対象スクリプトの大半（`vcs/*`, `create-commit.sh`, `create-issue.sh`, `archive-reentrant-plan.sh`, `.claude/hooks/*.sh`）はAI専用だが、`build.sh`（人間専用）も同じ規約に従う。`.claude/rules/shell-script-style.md`（AI専用ルール）が本docを「設計方針・経緯」として参照している関係がある |
| `extract-frontmatter.md` | 判断が分かれる→**移行対象に含める**（8番参照） | スクリプト自体は人間専用だが、生成物はAI可読frontmatterインデックス基盤という位置づけ |
| `distribution.md` | 人間専用の設計書 | `build.sh`（exe配布ビルド）の仕様。AIの実装フローには登場しない |

**`dev-tools/docs/ddr/`**

| ファイル | 分類 |
|---|---|
| `0001`（ahk2exeビルド） | 人間専用（`build.sh`関連） |
| `0002`〜`0007`, `0009`〜`0012` | AI専用（issue-mr-flow統合・レビュー返信・DraftPR自動リトライ・Planモードre-entry対処・ブランチslug生成・commitスキル強制など、いずれもAIワークフロー関連） |
| `0008`（frontmatter抽出設計） | 判断が分かれる→**移行対象に含める**（8番参照。実行主体は人間だがAI可読データ生成が目的） |

#### 2. `dev-tools/src/` へのパス参照箇所（リポジトリ全体grep結果）

- **AI側からの参照（移行時に書き換え必須）**: `.claude/skills/issue-mr-flow/SKILL.md`,
  `.claude/skills/issue-create/SKILL.md`, `.claude/skills/commit/SKILL.md`,
  `.claude/hooks/session-start.sh`, `.claude/hooks/post-push-usage-report.sh`,
  `.claude/hooks/post-push-compact-prompt.sh`, `.claude/hooks/block-direct-git-commit.sh`
  （エラーメッセージ文中の案内パス）, `.claude/rules/git-workflow.md`,
  `.claude/rules/plan-mode-safety.md`, `.claude/rules/shell-script-style.md`,
  `.claude/rules/directory-structure.md`
- **テスト**: `tests/test_vcs_provider.sh`, `tests/test_archive_reentrant_plan.sh`,
  `tests/test_extract_frontmatter.sh`（`source "${REPO_ROOT}/dev-tools/src/..."`）, `tests/README.md`
- **ドキュメント**: `index.md`（Repository Map）, `docs/ddr/0001-意思決定ログをADRからDDRへ改称.md`
- **設定**: `.mrworkflow.json`は`dev-tools/src`への直接参照は無いが、`specDirs`/`ddrDirs`が
  `dev-tools/docs/spec`・`dev-tools/docs/ddr`を指定しており、spec/ddrの一部を移動する場合は
  このキーの値も更新が必要
- **`.claude/settings.json`**: hookの`command`は`.claude/hooks/*.sh`自身のパスのみを指定しており
  `dev-tools/src`への直接参照は無い（書き換え不要）
- **既にstale（今回のスコープ外だが移行時に気づいた不整合）**:
  `.claude/rules/powershell-encoding.md`（旧`.ps1`版への言及）、
  `.claude/agents/issue-mr-resume.md:22`（`. dev-tools\src\vcs\Provider.ps1` — bash化後も
  未追従。関数名もPowerShell時代のPascalCaseのまま）、
  `DEVELOPERS.md:63`（`powershell -File dev-tools\src\build.ps1` — `build.sh`への追従漏れ）

#### 3. `.claude/hooks/` と `dev-tools/src/` の役割分担

重複はしていない。両者は役割が異なる。

- **`.claude/hooks/`**: `.claude/settings.json`の`hooks`セクション（`SessionStart`/`PreToolUse`/
  `PostToolUse`）に登録され、Claude Codeハーネスがイベント発火時に**自動起動**するインフラ。
- **`dev-tools/src/`（AI専用と判定したもの）**: AIエージェントがskillの手順に従って**能動的に**
  Bashツールで`source`・実行するスクリプト群。

ただし`session-start.sh`・`post-push-*.sh`は「hookでありながら`dev-tools/src/vcs/Provider.sh`に
処理委譲する」という依存関係を持つため、`Provider.sh`を`.claude/`配下へ移す場合はこの`source`元
パスの書き換えが必要になる（#2に記載済み）。

#### 4. プラグイン配布に関する既存記述

リポジトリ全体を`プラグイン`/`plugin`で再grepした結果、**該当箇所は0件**（今回作成した
`plans/`・`worklog/`ファイル自身を除く）。issue #24本文の「プラグインとして配布するときなどに
困る」という文脈は、issue本文にのみ存在し、リポジトリ内に対応する設計文書・議論の痕跡はない。
今回の移行が、この観点での最初の対応になる。

#### 5. `.claude/rules/directory-structure.md` の `dev-tools/` 記載

- ツリー図: `dev-tools/`配下は`src/`と`docs/`とだけ記載され、AI/人間の区別が無い。
- 本文（配置の指針の項）: 「開発者向けツール（ビルド・配布スクリプト等）はアプリ本体の機能と
  混在させず、`dev-tools/`配下に置く」— 「開発者向けツール」という表現で人間向けを前提とした
  説明になっているが、実態はAI専用スクリプトが大半を占めており記述と実態が乖離している。
- 別の箇所で「開発補助スクリプト（`dev-tools/src/`, `.claude/hooks/`, `tests/`配下の
  シェルスクリプト等）」とAI専用の`.claude/hooks/`を並列に扱っており、両者を区別しない書き方に
  なっている。今回の移行に合わせて、この節の記述を更新する必要がある。

対比として`.claude/rules/docs-workflow.md`は既に`CLAUDE.md`/`.claude/rules/*.md`を「AI専用」、
`docs/spec/*.md`等を「人間＋AI」と明示的にラベル付けしており、今回の区分の先例として参照できる。

#### 6. 移行先ディレクトリ構成案

issue本文の「AIが利用するものは`.claude`のscripts配下に入れる」（期待する動作）と
「スクリプトが`scripts/src`配下」「設計書が`scripts/docs`配下」（受け入れ条件）を素直に合わせると、
移行先は次の形になる。

```
.claude/
├── scripts/
│   ├── src/          # dev-tools/src/ のうちAI専用＋extract-frontmatter.sh（8番参照）
│   │   └── vcs/
│   └── docs/
│       ├── spec/      # dev-tools/docs/spec/ のうちAI専用＋shell-scripts.md・extract-frontmatter.md
│       └── ddr/        # dev-tools/docs/ddr/ のうちAI関連＋0008
├── rules/
├── skills/
└── hooks/
```

既存の`.claude/`配下の構成（`rules/`, `skills/`, `hooks/`）と並列に`scripts/`を追加する形になり、
命名・階層は既存構成と整合する。8番の追記により、`dev-tools/`に残るのは`build.sh`・
`distribution.md`・DDR `0001`のみとなる見込み。

#### 7. スコープ外だが記録した既知のstale参照

`.claude/agents/issue-mr-resume.md`が旧PowerShell版のパス・関数名のまま（bash化に未追従）、
`DEVELOPERS.md`が`build.ps1`のまま（`build.sh`への追従漏れ）の2点を確認した。いずれも本issueの
受け入れ条件（AI専用スクリプトの分離）には直接関係しないため、作業計画のスコープには含めない
方針とする（`issue-mr-resume.md`の移行対象パス表記だけは、今回の移行対象であるため作業計画で
併せて修正する）。

#### 8. 調査結果の追記（人間からの指示によるスコープ変更）

調査結果レビュー時、人間から「`extract-frontmatter.sh`と判断が分かれる部分も移行して」との
指示を受けた。これを受け、以下のとおり移行対象を変更する。

- `extract-frontmatter.sh`: 当初「人間専用（現状）」としていたが、移行対象に含める
  （`.claude/scripts/src/`へ移動）。実行主体は依然として人間の手動実行だが、移行先を分ける
  意味が薄い（`.claude/`配下に置いてもAIが自動実行するわけではなく、人間が手動実行する運用は
  変わらない）ため、移行そのものは可能と判断する。
- 「判断が分かれる」としていた設計書も移行対象に含める:
  - `dev-tools/docs/spec/extract-frontmatter.md` → `.claude/scripts/docs/spec/`へ
  - `dev-tools/docs/ddr/0008-frontmatter抽出スクリプトの設計判断.md` → `.claude/scripts/docs/ddr/`へ
  - `dev-tools/docs/spec/shell-scripts.md` → `.claude/scripts/docs/spec/`へ。ただし本docは
    `build.sh`（人間専用・`dev-tools/src/`に残留）のbash規約も対象に含んでいるため、移行後も
    `build.sh`から参照可能な状態を保つ必要がある（`dev-tools/`側から`.claude/scripts/docs/`への
    参照リンクで足りるか、記述を分割すべきかは作業計画で検討する）。

この結果、`dev-tools/`に残るのは `build.sh`・`distribution.md`・DDR `0001`（いずれも
exe配布ビルド専用）のみとなる見込み。
