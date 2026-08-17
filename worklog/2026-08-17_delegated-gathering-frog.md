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

## 作業計画レビュー対応（flow-id 19）

- 人間からチャットで「スコープ外としたものについても今回の対応で作業して」との指示を受けた。
  「調査結果」7番・「作業計画」スコープ外節で除外していた3件のうち、以下2件をスコープに追加した。
  - `.claude/agents/issue-mr-resume.md`の全面書き直し（旧PowerShell版`Provider.ps1`・PascalCase
    関数を、現行bash版`Provider.sh`のsnake_case関数へ1対1で置き換える。frontmatterの`tools:`から
    `PowerShell`も削除）
  - `DEVELOPERS.md`の`build.ps1`記載修正（`bash dev-tools/src/build.sh`へ）
  - `.claude/rules/powershell-encoding.md`の整理（精読の結果、単なるパス表記の古さではなく、
    「Provider.ps1をdot-sourceしていれば自動的に安全」節が指す仕組み自体が既に存在しないと判明。
    同節を削除し、他の古い実例（`session-start.ps1`, `build.ps1`）への言及も整理する）
- `build.sh`・`extract-frontmatter.sh`の実行主体（人間の手動実行という運用）を変更する話は
  出ていないため、これは引き続きスコープ外のまま維持した。
- `plans/delegated-gathering-frog.md`の「作業計画」章に7〜9番として追記し、「スコープ外」節を
  縮小した。「検証方法」にも2点（issue-mr-resume.mdの動作確認、powershell-encoding.mdのリンク切れ
  確認）を追加した。

## 実装（flow-id 21）

- `git mv`でAI専用ファイル（`.sh` 7本、`.claude/scripts/docs/spec/` 3本、DDR 11本）を
  `.claude/scripts/`配下へ移動した。
- **ハマった点**: パス参照の一括置換を`sed`で機械的に行った結果、移動した`.claude/scripts/docs/spec/`
  配下2ファイル（`issue-mr-workflow.md`, `shell-scripts.md`）の「## 影響範囲」節（過去issueごとの
  changelog、歴史的記録）まで新パスへ書き換えてしまい、当時存在しなかった`.claude/scripts/...`パスが
  過去のエントリに紛れ込む形で歴史を破壊した。`git checkout --`で該当ファイルをsed適用前の状態へ
  戻し、「## 仕様」等の**現在の状態を説明する節のみ**を手動で個別修正する方針に切り替えた
  （「## 影響範囲」等の過去changelogは書き換えず、issue #24用の新規エントリを追記する形にした）。
  DDR（`.claude/scripts/docs/ddr/*.md`）は不変の意思決定記録のため、`git mv`のみでsedによる
  本文書き換えは一切行わなかった（内部の相互リンクは同じディレクトリツリーごと移動したため
  相対パスとして引き続き有効）。
- パス参照が現在有効な箇所（skills, hooks, rules, tests, index.md）は`sed`で一括更新し、grepで
  更新漏れが無いことを確認した。
- `dev-tools/docs/README.md`を`distribution.md`/DDR`0001`のみの目次に縮小し、新規
  `.claude/scripts/docs/README.md`を作成した。
- `.claude/rules/directory-structure.md`のツリー図・配置の指針を、AI専用/人間専用の区分が
  明確になるよう書き換えた。`.claude/rules/markdown-frontmatter.md`のtype表、`index.md`
  （Repository Map）も同様に更新した。
- `.mrworkflow.json`・`Provider.sh`内の`get_workflow_config`デフォルト値の`specDirs`/`ddrDirs`に
  `.claude/scripts/docs/{spec,ddr}`を追加した。
- `.claude/agents/issue-mr-resume.md`を全面書き直し（旧PowerShell版`Provider.ps1`・PascalCase関数を
  bash版`Provider.sh`のsnake_case関数へ変換、`tools:`から`PowerShell`を削除）。
- `DEVELOPERS.md`の`build.ps1`記載を`bash dev-tools/src/build.sh`に修正。
- `.claude/rules/powershell-encoding.md`を整理（既に存在しない`Provider.ps1`の仕組みを説明していた
  節を削除し、将来`.ps1`を書く場合の一般的な注意事項に書き改めた）。
- リポジトリルートで`.claude/scripts/src/extract-frontmatter.sh .`を実行し、影響を受けた全
  `index.jsonl`を再生成した。
- 検証: 移動した`.sh`7本すべて`bash -n`で構文OK。`test_vcs_provider.sh`（14件）・
  `test_archive_reentrant_plan.sh`（19件）・`test_extract_frontmatter.sh`（15件）すべてpassed。
  grepで`dev-tools/src`・移動した`dev-tools/docs/spec/*`・`dev-tools/docs/ddr/000[2-9]|001[0-2]`の
  残存参照を確認し、意図的に残した箇所（DDRの歴史的記録、影響範囲changelogの過去エントリ、
  `dev-tools/`に残った`build.sh`関連）以外に更新漏れが無いことを確認した。

## 設計反映（flow-id 26）

- 人間から実装内容へのレビュー完了連絡を受け、`comments all`で未解決スレッドが無いことを確認した。
- 実装（flow-id 21）の時点で、移動した`.claude/scripts/docs/spec/*.md`（issue-mr-workflow.md,
  shell-scripts.md, extract-frontmatter.md）の「## 影響範囲」節へissue #24の変更内容を新規
  changelogエントリとして追記済みだったため、これらは既に設計反映済み。
- 未反映だった`dev-tools/docs/spec/distribution.md`の「## 影響範囲」にも、issue #24による
  参照パス変更・README分割の変更点を追記した。
- 新規DDR `.claude/scripts/docs/ddr/0013-dev-toolsをAI専用_人間専用に分離する.md`を作成し、
  以下を記録した:
  - 決定: 利用者（誰が実行するか）を軸に`dev-tools/`を物理分離する方針、`extract-frontmatter.sh`等
    「実行主体は人間だがAI専用群と一体」なものを移行対象に含める判断基準
  - 決定: 既存の歴史的記録（DDR本文・spec「影響範囲」changelog）は書き換えず、新規エントリの
    追記のみで対応する方針（実装中に一度sedで書き換えてしまい復旧した教訓を反映）
  - 却下案: シンボリックリンク方式、dev-tools全体を.claude/scriptsへ統合する案、
    過去パス参照の機械的一括置換
  - `.claude/agents/issue-mr-resume.md`を全面書き直すに至った経緯（調査時の想定との差分）
- `.claude/scripts/docs/README.md`にDDR 0013へのリンクを追加した。
- `.claude/scripts/src/extract-frontmatter.sh .`を再実行し、新規DDRを含むindex.jsonlを再生成した。

## 想定外の並行変更への対応

- flow-id 27作業中、`git status`で以下3ファイルが未コミットの変更を持っていることに気づいた。
  自分がこのセッションで編集した覚えが無い内容だったため、詳細を確認した。
  - `.claude/rules/git-workflow.md`: worklogの命名を`日付_<planファイル名>.md`から
    `日付_<planファイル名>_push<N>.md`へ変更
  - `.claude/skills/commit/SKILL.md`: 「`git add` / `git commit` を直接実行せず」から
    `git add`の言及を削除
  - `worklog/TEMPLATE.md`: 同様の`_push<N>`命名への変更、`push回数: N`行の追加
  - 直近のコミット（`e6f5fdc`, 00:33作成）より後、00:36〜00:50の間に変更されていた（自分の
    このセッションの作業時間帯と重なる）。sedによる一括置換の対象にもしていたが、置換パターンには
    `_push<N>`や`git add`関連の文字列は一切含まれていないため、自分の操作による副作用ではないと
    判断した。
  - 折しも自分は同じタイミングで、`docs-workflow.md`のworklog命名規則を「`_push<N>`という記述が
    残っているが実際には一度も使われたことがない」という理由で**逆方向**（`_push<N>`を削除する
    方向）に修正しており、矛盾する2方向の変更が同時に発生していた。
  - 作業を中断し、ユーザーに「他セッションでの意図的な変更か」を確認する形で報告した。
    「意図した変更なので一緒に取り込んでOK」との回答を得たため、3ファイルの変更はそのまま
    取り込み、`docs-workflow.md`側は`_push<N>`方式に合わせて修正し直した。
  - 本ブランチの既存worklogファイル（累積1ファイル方式で運用中）は新方針への遡及的な分割は
    行わず、新方針は今後のworklog作成から適用される想定とした（本タスクのスコープ外の構造変更を
    避けるため）。
