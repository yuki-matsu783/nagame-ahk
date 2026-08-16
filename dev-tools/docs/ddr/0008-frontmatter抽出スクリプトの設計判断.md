---
title: 0008. frontmatter抽出スクリプトの設計判断（出力単位・concept_id基準・YAML解析方式）
type: ddr
description: extract-frontmatter.shの出力単位・concept_id基準・YAML解析方式に関する設計判断を記録したDDR
tags: [extract-frontmatter, jsonl, ddr]
keywords: [concept-id, repo-root, realpath, yq, jsonl, ディレクトリ分散]
---

# 0008. frontmatter抽出スクリプトの設計判断（出力単位・concept_id基準・YAML解析方式）

## 背景

issue #7 PR #23のレビューで追加要望を受けて`dev-tools/src/extract-frontmatter.sh`を新規実装する
過程で、実装とレビューの往復により以下3点の設計が変遷した。

## 決定

### 1. 出力はmarkdownが直下に存在するディレクトリ毎に分散させる

当初の実装は「指定ディレクトリ配下を再帰走査し、指定ディレクトリ直下に1つの`index.jsonl`へ
全件を集約する」方式だった。レビューで以下の指摘を受けた。

> プロジェクトルートで実施したら、markdownが存在する各ディレクトリごとにindex.jsonlが作成され、
> その中身のconcept_idはプロジェクトルートからの相対パスから.md拡張子を除いたものになるイメージ。
> プロジェクトルート以外のディレクトリで実施した場合も、その配下の子ディレクトリを再帰的に走査し、
> markdownが存在する各ディレクトリ毎にindex.jsonlが作成され、その中身のconcept_idはプロジェクト
> ルートからの相対パスから.md拡張子を除いたものになるイメージ

**markdownファイルが直下に存在するディレクトリ毎に、そのディレクトリ自身へ`index.jsonl`を
出力する方式へ変更した。** 出力先は`$(dirname "$file")/index.jsonl`とし、連想配列で
「そのディレクトリのindex.jsonlを既に切り詰めたか」を管理して複数ファイルへの追記に対応する。

### 2. `concept_id`/`directory`は常にgitリポジトリのルート基準にする

実行時に指定したディレクトリ（`target_dir`）ではなく、**gitリポジトリのルート**からの相対パスを
`concept_id`/`directory`の基準にする。これにより、リポジトリルートで実行しても`docs/`だけを
指定して実行しても、`docs/spec/activity-status.md`の`concept_id`は常に`docs/spec/activity-status`
になり、実行時の指定ディレクトリに依存しない一貫したID体系になる。

### 3. YAML→JSON変換は`yq`優先＋自前パーサーのフォールバックにする

当初は「本リポジトリのfrontmatterスキーマ（単純なスカラー値・フロー配列のみ）に絞った自前の
軽量パーサーのみ」で実装した（`yq`が開発機に未インストールで、フルYAML文法対応の外部依存を
新規に増やすほどの必要性が無いと判断したため）。レビューで「yq, jqがあればインストールされて
いればそれを利用した方が良いか？」との指摘を受け、`command -v yq`でyqの有無を確認し、
**あれば`yq -o=json e '.' -`で優先的に変換し、無い（または変換に失敗した）場合のみ自前パーサーへ
フォールバックする方式**に変更した。`yq`自体を新規の必須外部依存にはしていない
（開発機に`yq`が無いため、このリポジトリでは常にフォールバック経路が使われる）。

## 却下した案

- **単一ファイルへの集約を維持する案**: 実装コストは低いが、レビューで明示的に却下された。
  「各ディレクトリごとにindex.jsonlを持つ」という要求は、ディレクトリ単位でのインデックス
  参照・更新を想定しているためと考えられる。
- **`concept_id`を実行時の指定ディレクトリ基準にする案（当初の実装）**: 実行するディレクトリに
  よって同じファイルの`concept_id`が変わってしまい、一意な識別子として使えないという問題が
  あるため却下。
- **`yq`を新規の必須外部依存にする案**: フルYAML文法への対応力は上がるが、`.claude/rules/shell-script-style.md`
  が前提とする外部依存（git bash + `jq` + `gh`/`glab`）に新たな必須ツールが増える。開発機に
  未インストールの状態でスクリプトが動作しなくなることを避けるため、優先利用＋フォールバックの
  ハイブリッド方式を採用した。
- **自前パーサーのみを維持する案**: レビュー指摘に対して具体的な改善を示せないため不採用。

## 技術的な補足: `git rev-parse --show-toplevel`と`realpath`のパス表記差異

`concept_id`/`directory`をリポジトリルート基準にする実装で、`realpath --relative-to`の基準として
`git rev-parse --show-toplevel`の出力をそのまま使ったところ、正しく相対パスが計算できない問題に
実機で遭遇した。

- `git rev-parse --show-toplevel`はWindowsドライブレター形式（例: `C:/Users/.../nagame-ahk`）で
  パスを返す。
- `realpath`（MSYS/git bash付属）は同じ場所を指していても`/c/Users/.../nagame-ahk`という
  MSYS形式で返す。
- この表記の不一致により、`realpath --relative-to="$(git rev-parse --show-toplevel)" <file>`は
  プレフィックスが一致せず、相対パスではなく絶対パスをそのまま返してしまう。

`cd`コマンドはどちらの表記も受け付けて実際のディレクトリへ移動できるため、
`(cd "$start_dir" && cd "$(git rev-parse --show-toplevel)" && pwd)`という手順（`resolve_repo_root`
関数）で、`git rev-parse`の出力を一度`cd`で経由させてから`pwd`を取ることで、常に`realpath`と
表記が一致するMSYS形式のリポジトリルートを得られることを実機確認した。
