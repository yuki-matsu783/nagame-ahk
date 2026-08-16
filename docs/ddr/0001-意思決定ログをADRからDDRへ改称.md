---
title: 0001. 意思決定ログのディレクトリ・呼称をADRからDDR（Design Decision Record）へ改称する
type: ddr
description: 意思決定ログのディレクトリ・呼称をADRからDDRへ改称した経緯を記録したDDR
tags: [ddr, docs, naming]
keywords: [adr, ddr, design-decision-record, rename, docs-readme, issue-12]
---

# 0001. 意思決定ログのディレクトリ・呼称をADRからDDR（Design Decision Record）へ改称する

## 背景

`docs/adr/` `dev-tools/docs/adr/` はADR（Architecture Decision Record）という一般的な命名慣習に
沿っていたが、実際にはアーキテクチャに限らない意思決定（開発フローの運用ルールの決定等。例:
`dev-tools/docs/ddr/0002-issue-mr-flowへの実装フロー統合.md`,
`dev-tools/docs/ddr/0003-レビュースレッド解決は自動化しない.md`）も記録しており、名前と実態が
合っていなかった（issue #12）。

## 決定

**「ADR」という呼称・ディレクトリ名を廃止し、「DDR（Design Decision Record）」に統一する。**

- `docs/adr/` → `docs/ddr/`、`dev-tools/docs/adr/` → `dev-tools/docs/ddr/` にリネーム（`git mv`で
  履歴を保持）。
- ルール・スキル・spec等、文章上で `adr`/`ADR` を参照していた箇所をすべて `ddr`/`DDR` に置換する
  （`.claude/rules/`, `.claude/skills/`, `.claude/agents/`, `.mrworkflow.json`,
  `dev-tools/src/vcs/Provider.ps1` の設定キー `adrDirs`→`ddrDirs` を含む）。
- 既にマージ済みの過去レコード本文中の「ADR」という語句（`dev-tools/docs/ddr/0002`,`0004`）も、
  用語統一のため書き換える。ADR/DDRの「一度マージしたら追記のみ（変更不可）」ルールは、記録された
  意思決定の内容そのものを後から書き換えないことを目的としたものであり、プロジェクト全体の呼称
  変更まで禁じる趣旨ではないと解釈した。
- これまでADR/DDRの英語正式名称（Architecture/Design Decision Record）を説明した文章はプロジェクト
  内のどこにも無く、単に「意思決定ログ」とだけ説明されていた。今回`docs/README.md` /
  `dev-tools/docs/README.md` に「DDRはADRの考え方を拡張し、architectureに限らない意思決定も
  対象とする」という一文を追記した。

## 副次的な修正

`docs/README.md` / `DEVELOPERS.md` / `dev-tools/docs/spec/distribution.md` が
`docs/adr/0001-ahk2exeビルドの環境依存対応.md` にリンクしていたが、当該ファイルの実体は
`dev-tools/docs/adr/`（現 `dev-tools/docs/ddr/`）側にのみ存在し、`docs/adr/`（現 `docs/ddr/`）側には
一度も存在しなかった（本改称とは無関係の既存の壊れたリンク）。改称作業と合わせてリンク先を
`dev-tools/docs/ddr/0001-...` に修正した。

## 却下した案

- **ディレクトリ名のみリネームし、既存レコード本文の「ADR」表記は変更しない案**: 追記のみ・変更不可
  ルールをより厳格に解釈する案。実装コストは低いが、リネーム後もレコード本文中に廃止したはずの
  旧呼称が残り続け、一貫性を欠く。今回は用語統一を優先し、不採用とした。
