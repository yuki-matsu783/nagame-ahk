---
title: 調査ドキュメントをmarkdownとhtmlで作る（worklog push3）
type: log
description: issue #48対応、実装フェーズ（flow-id 21）と設計反映（flow-id 26）の作業ログ
tags: [issue-mr-flow, reports, html, worklog]
keywords: [get_branch_work_files, Provider.sh, SKILL.md, docs-workflow, DDR, reportsDir]
---

# 調査ドキュメントはmarkdownとhtmlで作る（issue #48）— push3

## 実装フェーズ（flow-id 21）

作業計画（`plans/drifting-sniffing-clover.md`「作業計画」章）の1〜7をすべて実施した。

1. `.claude/skills/issue-mr-flow/SKILL.md`: flow-id 10/14/31、および「PRがflow-id 31実施前に
   マージされてしまった場合の対処」節に`reports/`を反映した（作業計画には明記していなかったが、
   flow-id 31変更と一体の箇所のため合わせて更新）。
2. `.claude/rules/docs-workflow.md`: worklog行に倣い`reports/<plan名>.html`行を追加。
3. `.claude/rules/directory-structure.md`: ツリー図の`worklog/`直後に`reports/`を追加。
4. `.mrworkflow.json`: `reportsDir: "reports"`を追加。
5. `.claude/scripts/src/vcs/Provider.sh`: `get_workflow_config`の既定値（ファイル無い場合の
   フォールバック）にも`reportsDir`を追加（作業計画に明記は無かったが、既定値とファイル値の
   整合を保つため）。`get_branch_work_files`に`reports_dir`を追加し、`plans_dir`/`worklog_dir`と
   完全対称に実装した。
6. `.claude/scripts/docs/spec/issue-mr-workflow.md`: 「提供関数」表・「途中引き継ぎ対応」節・
   「## 仕様」節のSKILL.md概要文・「## 設定項目」を更新し、「## 影響範囲」に新規changelog
   エントリを追加した（過去のissue #24・#43エントリは変更していない）。
7. `.claude/agents/issue-mr-resume.md`: 手順6・手順8のラベル、およびfrontmatter description・
   keywordsに`reports`を反映した。

## 検証（作業計画の検証方法どおり）

- `bash -n .claude/scripts/src/vcs/Provider.sh` → 構文OK。
- `bash tests/test_vcs_provider.sh` → `passed=14 failures=0`（既存テストが壊れていないことを確認）。
- `reports/`配下に一時ファイルを1つ置いた状態で`get_branch_work_files`を手動実行し、
  出力に`reports/`が含まれることを確認した（新規未追跡ディレクトリのため`git status --porcelain`は
  個別ファイルではなく`reports/`という行を返す。これは`plans/`/`worklog/`が完全新規ディレクトリ
  だった場合と同じgitの標準的な挙動であり、今回の実装固有の不具合ではない）。確認後、
  テスト用ファイルは削除した。

## 設計反映（flow-id 26相当）

本issueが対象とする機能はissue-mr-flow自体（`.claude/`配下）であり、既存の「正史仕様」は
`docs/spec/`ではなく`.claude/scripts/docs/spec/issue-mr-workflow.md`が担っている。上記6で
この仕様書自体を最新化し、「## 影響範囲」changelogへ新規エントリを追加したため、実質的に
flow-id 26（plans/worklogの内容をdocs/spec/docs/ddrへ反映する）に相当する作業は完了している。

加えて、「Claude Code組み込みのArtifact機能ではなく自己完結HTMLコミット方式を採用した」という
意思決定は、却下した代替案（Artifact機能・pandoc変換・TailwindCSSビルド同梱・
固定テンプレート化）を伴う設計判断のため、DDRとして記録する価値があると判断し、
`.claude/scripts/docs/ddr/0014-調査結果のhtml版は自己完結htmlのコミットで作る.md`を新規作成した
（`.claude/scripts/docs/README.md`のDDR一覧にもリンクを追加）。

## 次にやること

- flow-id 22: `commit`スキルでcommitし、push する。
- flow-id 23: `describe`でMR description更新。
- flow-id 24〜30: ユーザーから「flow-id 32まで承認なしで進めてよい」と指示されているため、
  レビュー待ちをスキップして進める（未解決コメントの機械的な再確認は都度行う）。
- flow-id 31: `plans/` `worklog/` `reports/`を削除し、`HANDOFF.md`をリセットする
  （このissueでは`reports/<plan名>.html`の実ファイルは作成していないため、実質`plans/`・
  `worklog/`の削除のみになる見込み）。
- flow-id 32: commit・push・Draft解除。
