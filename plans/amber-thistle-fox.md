---
title: 設計反映・AIアセット改善（flow-id 16〜17）
type: guide
description: issue #7 PR #23のレビュー完了を受けた設計反映（extract-frontmatter.shの正史仕様・DDR）とAIアセット改善（plan-mode-safety・shell-script-style）の計画
tags: [issue-mr-flow, docs-workflow, dev-tools]
keywords: [設計反映, ddr, extract-frontmatter, plan-mode-safety, shell-script-style, aiアセット改善]
---

# plan: 設計反映・AIアセット改善（flow-id 16〜17）

## Context

PR #23（issue #7）の実装レビュー（14〜15ループ、3ラウンド）が完了し、`comments all`で
未解決レビュースレッド0件を確認済み。`.claude/skills/issue-mr-flow/SKILL.md`の全体フローに従い、
flow-id 16（設計反映: `plans/`/`worklog/`の内容を`docs/spec/`/`docs/ddr/`へ反映）・
flow-id 17（AIアセット改善）を実施する。

各roundのplan/worklogが「対象外」節で明示的に先送りしていた項目（`dev-tools/src/extract-frontmatter.sh`
の正史仕様反映）と、作業中に発覚した非自明な環境依存の落とし穴（git bashでのパス表記差異、Windows版
jqバイナリのCR混入）・Planモード運用上の制約（1 re-entry = 1追跡ファイル）を、既存のDDR/ルールの
粒度・文体に合わせて反映する。

## 実施内容

### 1. 設計反映: `dev-tools/docs/spec/extract-frontmatter.md`（新規）

既存の`dev-tools/docs/spec/distribution.md`・`shell-scripts.md`と同じ章立て
（背景・目的／仕様／影響範囲／設定項目／未決定事項・懸念点）で、`extract-frontmatter.sh`の
最終仕様（round2〜round4の変遷を経た最終形）を記載する。

- 仕様: ディレクトリ分散出力（markdownが直下に存在するディレクトリ毎に`index.jsonl`）、
  concept_id/directoryはgitリポジトリルート基準、frontmatter抽出は`yq`優先＋自前パーサー
  フォールバック、mtimeはISO 8601（タイムゾーン省略）。
- 影響範囲: `dev-tools/src/extract-frontmatter.sh`（新規）、`tests/test_extract_frontmatter.sh`
  （新規）、既存16ディレクトリの`index.jsonl`（新規・git管理下）。
- 未決定事項: 生成物`index.jsonl`の自動再生成の仕組みは未導入（手動での再実行が必要）、
  `yq`の動作検証はこのマシンでは未実施（未インストールのためフォールバック経路のみ確認済み）。
- `dev-tools/docs/README.md`の「spec（機能仕様）」一覧に本ドキュメントへのリンクを追記する。

### 2. 設計反映: `dev-tools/docs/ddr/0008-frontmatter抽出スクリプトの設計判断.md`（新規）

既存DDR（0001等）と同じ「背景／決定／却下した案」の構成で、レビューとのやり取りを通じて変遷した
3つの非自明な決定をまとめて記録する。

- **出力をディレクトリ分散にした理由**: 当初「指定ディレクトリ1箇所に集約」で実装したが、
  レビューで「markdownが存在する各ディレクトリごとにindex.jsonlを作成し、concept_idは常に
  リポジトリルート基準にすべき」との指摘を受け、現行設計に修正した経緯（却下案: 単一ファイル集約）。
- **`git rev-parse --show-toplevel`と`realpath`のパス表記差異への対処**: 前者がWindowsドライブ
  レター形式（`C:/...`）、後者がMSYS形式（`/c/...`）を返すため、`realpath --relative-to`が
  正しく機能しなかった実機確認結果と、`cd`経由でMSYS形式に統一する`resolve_repo_root`関数での
  解決方法。
- **YAML→JSON変換を`yq`優先＋自前パーサーのフォールバックにした理由**: 当初は自前パーサーのみ
  だったが、レビューで「yqがあれば優先利用すべきでは」との指摘を受けて変更した経緯（却下案:
  yqを新規の必須外部依存にする案、自前パーサーのみを維持する案）。

### 3. AIアセット改善: `.claude/rules/plan-mode-safety.md`

Planモードへの複数回の再突入時、ハーネスが「今回のplanファイル」を前回re-entry時のパスに固定して
追跡する（`ExitPlanMode`はその固定パスからしか読まない）仕様のため、「計画ごとに新しいplanファイル
名を使う」ルールと、ハーネス側のこの制約が単純には両立しないことが今回のセッションで判明した。
以下の対処手順を新しい節として追記する。

- 承認を得たい内容を、まずハーネスが提示する既存のplanファイルパスへ一時的に書き込み、
  `ExitPlanMode`を呼ぶ（ハーネスが正しく最新内容を読めるようにするため）。
- 承認後、`git checkout -- <そのplanファイル>`で直前にコミット済みだった内容へ復元し、
  今回の計画の正式な記録は新規ファイルへ書き込む（実装・commitはこちらを参照する）。
- 今回のセッションで3回（round3・round4・round5相当）この手順を実施し、問題なく機能することを
  確認済み（`plans/ember-quilted-narwhal.md`, `plans/gilded-tundra-sparrow.md`,
  `plans/velvet-copper-lynx.md`が実例）。

### 4. AIアセット改善: `.claude/rules/shell-script-style.md`

「文字コード」節に、今回`dev-tools/src/extract-frontmatter.sh`の実装で発覚した実機事象を追記する。

- Windows版のnative `jq`バイナリ（`C:\Program Files\jq\jq.exe`、MSYS版ではない）は、標準出力を
  ファイルへリダイレクトする際に行末へCRを付与することがある（git bashの`core.autocrlf=input`設定
  下ではコミット時に自動でLFへ変換されるため実害は限定的だが、コミット前のワーキングツリー上では
  CRLFが混入する）。jqの出力を直接ファイルへ書き出す箇所は`tr -d '\r'`でLF改行に統一する
  （実例: `dev-tools/src/extract-frontmatter.sh`の`main()`）。

## 対象外

- `.claude/rules/markdown-frontmatter.md`・`.claude/rules/directory-structure.md`・`index.md`は
  各roundで既にその都度最新化済みのため、追加の設計反映は不要。
- worklog 4件（`immutable-painting-kitten`を除く。同ファイルはこのブランチでは未作成）の削除は
  flow-id 21（次タスクへのリセット）で行う。今回は反映のみ。

## 検証方法

- `dev-tools/docs/spec/extract-frontmatter.md`の章立てが既存spec文書と一致していることを目視確認する。
- `dev-tools/docs/ddr/0008-...`が既存DDRと同じ構成（背景／決定／却下した案）になっていることを
  確認する。
- `dev-tools/docs/README.md`の新規リンクが実際のファイルパスと一致することを確認する。
- 追記した`.claude/rules/plan-mode-safety.md`・`.claude/rules/shell-script-style.md`が、既存の
  `alwaysApply: true`等の既存キーを変更せず末尾に追記する形になっていることを`git diff`で確認する。
