---
title: canvas形式の調査結果HTML生成スキル（起票）
type: rule
description: 調査結果報告のreports/<plan名>.htmlで、関連・依存関係を主題とする内容にcanvas（ノード・エッジ）形式を使うか判断し生成するスキルを新設するための、新規issue起票・ブランチ作成の計画
tags: [issue-mr-flow, skill-creator, reports, html, canvas]
keywords: [canvas, TailwindCSS, ノード, エッジ, 依存関係, 関連図, issue起票]
---

# canvas形式の調査結果HTML生成スキル（新規issue起票）

## Context

issue #48（調査結果HTMLのTailwindCSS CDN方式確立）に関する対話の中で、通常の一覧・表形式では
表現しづらい「複数要素間の関連・依存関係」を主題とする調査結果向けに、codecanvas.app的な
ノード・エッジのcanvas形式（パン・ズーム・ノードホバーでの関連ハイライトに対応）が有効である
ことを、比較試作（TailwindCSS CDN通常版・自前ミニマムCSSハイブリッド版・リッチ演出版・canvas版の
4種）を通じて確認した。

このスキルを`.claude/skills/`配下に追加したいが、issue #48はHANDOFF.md上すでに flow-id 22
（commit・push）以降の完了間近の状態にあり、「今回の対象は調査結果のHTML化のみ」と明示的に
スコープ外事項が記録されている。ユーザーとの確認の結果、issue #48は現状のまま完了させ、
canvas形式スキルの作成は新規issueとして起票し、`issue-mr-flow`に沿って別ブランチで進めることに
決定した（issue #48を中断・拡張しない）。

## 実施内容

1. `issue-create`スキルの手順に沿って、以下の内容で新規issueを起票する。
   - 目的: 調査結果報告のHTML化（`reports/<plan名>.html`）において、内容が複数要素間の関連・
     依存関係を主題とする場合に、一覧・表形式ではなくcanvas（ノード・エッジ）形式を使うべきかを
     判断し、適切な場合はcanvas形式のHTMLを生成するスキルを新設する。
   - 現状: issue #48で`reports/<plan名>.html`の生成方式（TailwindCSS CDN方式）は確定したが、
     一覧・表形式を前提とした標準パターンのみで、関連性・依存関係を主題とする調査結果向けの
     指針・テンプレートは存在しない。
   - 期待する動作: `.claude/skills/`配下に、canvas形式が適切かどうかの判断基準と、パン・ズーム・
     ノードホバーでの関連ハイライトに対応したTailwindCSS CDNベースの自己完結HTMLテンプレートを
     提供する新スキルを追加する。
   - 受け入れ条件（案。issue起票時に`issue-create`のフォーマットに合わせて微調整）:
     - `.claude/skills/<name>/SKILL.md`に、canvas形式を選ぶべき判断基準が明文化されている
     - ノード・エッジを差し替えるだけで使えるTailwindCSS CDNベースの自己完結HTMLテンプレートが
       同スキルに含まれている
     - `.claude/skills/issue-mr-flow/SKILL.md`のflow-id 10（`reports/<plan名>.html`作成）から
       このスキルの存在が分かるよう参照が追加されている
     - 実サンプルデータでの動作確認（ブラウザ表示・ズーム/パン/ホバーハイライトの目視確認）を行う
2. `start <issue番号>`で featureブランチ・Draft PRを作成する。
3. 以降（Planモードでの調査計画作成〜）は、新ブランチのセッションで`issue-mr-flow`のflow-id 4
   から通常どおり進める（本計画のスコープはここまで）。

## 対象外

- issue #48自体の内容・スコープの変更（完了間近のため中断・拡張しない）。
- 検証の重さは「軽めのvibe check」とする方針（ユーザー確認済み）。skill-creatorが提示する
  本格的な評価ループ（with-skill/baselineのサブエージェント並列実行・ブラウザeval viewerでの
  比較）は行わず、実施内容の1〜3完了後、新ブランチ側の調査・作業計画の中で、この場で1〜2個の
  テストプロンプトを自分で実行し会話ベースでユーザーと確認する形にとどめる。
- skill本体の詳細設計（判断基準の文言、テンプレートの具体的なノード/エッジ構成等）は、新issue
  起票後の調査計画・作業計画（新ブランチ側のflow-id 4以降）で詰める。本計画では扱わない。

## 検証方法

- 起票されたissueの本文（目的・現状・期待する動作・受け入れ条件）をユーザーに提示し、内容が
  意図と一致するか確認する。
- `start`実行後、featureブランチ名・Draft PR URLが正しく作成されたことを確認する。
