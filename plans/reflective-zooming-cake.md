---
title: extract-frontmatter.shをgitignoreを読み取って対応するようにする（調査計画）
type: rule
description: issue #54対応。extract-frontmatter.shがfindで.gitignore対象ディレクトリまで走査してしまう問題の調査計画
tags: [extract-frontmatter, gitignore, shell-scripts, issue-mr-flow]
keywords: [find, git ls-files, git check-ignore, 参考ディレクトリ, index.jsonl, タイムアウト, frontmatter]
---

# extract-frontmatter.shをgitignoreを読み取って対応するようにする（issue #54）

## Context

`.claude/scripts/src/extract-frontmatter.sh` は指定ディレクトリ配下を `find "$target_dir" -type f
-name '*.md'` で再帰走査し、見つかった全markdownからfrontmatterを抽出して `index.jsonl` を生成する。
このfindは `.gitignore` を一切考慮しないため、`参考ディレクトリ/`（外部OSSをローカルにcloneする場所、
`.gitignore`対象）のような大量のmarkdownを含むディレクトリが存在すると、そこまで走査対象に含めて
しまう。既に `.claude/scripts/docs/spec/extract-frontmatter.md` の「未決定事項・懸念点」節に、
issue #43対応時の実機確認として「リポジトリルート（`.`）に対する一括実行が2分以上かかりタイムアウト
し、書き込み中だった`index.jsonl`が壊れた状態で残る」という既知の問題として記録されている。
issue #54はこの問題を、`.gitignore`を読み取って対応する形で解消することを求めている（issue本文の
4見出しは未記入だが、上記の既知の懸念点がそのまま該当する）。

## 調査

### 調査の目的

`find`ベースの走査を`.gitignore`対応にする具体的な実装方針を1つに絞り込み、次段階（作業計画）で
迷いなく実装に着手できる状態にする。既存のテスト方針（`main()`本体は単体テスト対象外）・出力
フォーマット（`concept_id`/`directory`のリポジトリルート基準）・既存spec/DDRとの整合性を崩さない
方針を選ぶ。

### 調査項目

1. 候補方式Aの実現可能性検証: `find`によるファイル列挙自体を`git ls-files --cached --others
   --exclude-standard -z -- "$target_dir"`（トラッキング済み + 未トラッキングだが非ignore、
   NUL区切り）に置き換える案。`.gitignore`配下のディレクトリを走査自体しないため、issue #43で
   記録された「巨大な`参考ディレクトリ/`によるタイムアウト・破損」を根本から解消できる。
   - `target_dir`に絶対パス／相対パス／`.`を指定した場合それぞれで、`find`と同等の候補ファイル
     集合が得られるか実機で比較する（一時ディレクトリにサンプルmarkdown＋`.gitignore`対象
     ディレクトリを作り、両方式の出力差分を確認）。
   - 出力される各ファイルパスの表記（cwd相対か、絶対か）が、既存の`realpath --relative-to
     "$repo_root"`によるconcept_id/directory算出ロジックとそのまま噛み合うか確認する
     （`target_dir`をそのまま`find`に渡している現状の実装と同じ表記になるかがポイント）。
2. 候補方式Bの実現可能性検証: `find`による列挙は現状のまま維持し、列挙後に`git check-ignore`で
   ignore対象を除外するフィルタ案。1ファイルずつ`git check-ignore -q`を呼ぶ方式と、
   `git check-ignore --stdin -z`で一括判定する方式の両方を検討する。ただし`find`自体は
   `参考ディレクトリ/`配下も再帰的に訪問してしまうため、issue #43のタイムアウト問題を
   根本解消できない可能性が高い点を実機で確認する。
3. 方式A・Bのどちらを採用するか、`.claude/rules/shell-script-style.md`の
   「大きなJSONを`--argjson`等へ渡さない」等の既存規約と照らして判断する（方式Bの一括判定は
   ファイル一覧をstdin経由で渡す設計にすれば同種の問題を回避できるはずだが、念のため確認する）。
4. 採用方式が、`tests/test_extract_frontmatter.sh`が検証する既存関数（`frontmatter_to_json`,
   `resolve_repo_root`, concept_id/directory算出ロジック）に影響しないか確認する（`main()`内の
   走査ロジックのみの変更で完結するか）。
5. 採用方式が、gitリポジトリ外や`.git`が無い環境で実行された場合にどう振る舞うか確認する
   （現状も`resolve_repo_root`がgit依存のため、git必須という前提自体は変わらない想定だが、
   エラーメッセージの分かりやすさを確認する）。
6. `.claude/scripts/docs/spec/extract-frontmatter.md`の「未決定事項・懸念点」節にある
   `参考ディレクトリ/`関連の記述をどう更新するか（解消した懸念として書き換えるか、
   changelogとして別途追記するか）を、`.claude/rules/docs-workflow.md`のchangelog運用
   （過去issueのchangelogは書き換えない）と照らして整理する。
7. 本件が`.claude/scripts/docs/ddr/0008-frontmatter抽出スクリプトの設計判断.md`に新たな決定として
   追記すべき内容か（既存DDRは「出力単位」「concept_id基準」「YAML解析方式」の3点のみを扱っており、
   走査方式は対象外）を判断する。

### 調査対象外

- `yq`導入の是非（DDR 0008で既に却下済み、本issueのスコープ外）。
- `index.jsonl`の出力フォーマット自体の変更（`concept_id`/`directory`/`frontmatter`/`mtime`の
  構造は変更しない）。
- 他のdev-tools/scriptsスクリプトへの同種対応（本issueは`extract-frontmatter.sh`のみを対象とする）。
- WSL/Linux実機での動作検証（既存の未決定事項のまま。git bash前提を維持する）。

### 調査方法

- 項目1・2は、スクラッチパッド配下に`.git`初期化済みの一時ディレクトリを作り、markdownファイルと
  `.gitignore`対象ディレクトリ（`参考ディレクトリ/`相当）を用意したうえで、`find`・
  `git ls-files`・`git check-ignore`それぞれの出力を実機比較する。
- 項目3〜7は該当ファイル（`shell-script-style.md`, `test_extract_frontmatter.sh`,
  `extract-frontmatter.md`, `docs-workflow.md`, DDR 0008）を読み、方式Aまたは方式Bとの整合性を
  文書化する。

### 調査結果

スクラッチパッド配下に`.git`初期化済みの一時リポジトリ（`README.md`・`docs/a.md`をトラッキング、
`.gitignore`で`/usage/`・`/参考ディレクトリ/`を除外し、それぞれにmarkdownを配置）を作り、
現状の`extract-frontmatter.sh`と、走査部分のみ`git ls-files`へ置き換えたパッチ版を実機比較した。

1. **方式Aの実現可能性（結論: 採用）**: `find "$target_dir" -type f -name '*.md' -print0 | sort -z`
   を`git ls-files --cached --others --exclude-standard -z -- "$target_dir" | grep -z '\.md$' |
   sort -z`に置き換えたところ、`.gitignore`対象（`usage/ignored.md`,
   `参考ディレクトリ/gaidoc.md`, `参考ディレクトリ/subdir/nested.md`）が候補集合から完全に除外され、
   トラッキング対象の`README.md`・`docs/a.md`のみが残った。`target_dir`に`.`・サブディレクトリ
   （`docs`）・絶対パスのいずれを指定しても同じ結果になることを確認した。生成された`index.jsonl`の
   `concept_id`/`directory`/`frontmatter`/`mtime`は、現状版で生成された内容とバイト単位で完全一致
   した（`realpath --relative-to`ベースのconcept_id算出ロジックは無変更のまま噛み合う。
   `git ls-files`が返すパスに`find`のような`./`接頭辞が付かない差異はあるが、`realpath`はcwd基準で
   絶対パス化するため結果に影響しない）。また`target_dir`に`参考ディレクトリ`（ignore対象
   ディレクトリそのもの）を直接指定した場合は、候補ファイル0件・`index.jsonl`生成無し・エラー無しで
   正常終了することを確認した（「完全にignore対象なら何も出力しない」という直感的な挙動）。
2. **方式Bの実現可能性（結論: 不採用）**: `find`はそのまま維持し、列挙後に
   `git check-ignore --stdin -z -v`で事後フィルタする方式も実機で動作させた。ignore対象の
   3ファイルを正しく検出できたが、**`find`自体は`参考ディレクトリ/`配下を含め全ファイルを
   再帰的に訪問してしまう**ことを確認した（`find . -type f -name '*.md'`の出力に、ignore対象の
   3ファイルがそのまま含まれる＝訪問済みであることが根拠）。事後フィルタでは「`参考ディレクトリ/`の
   走査自体を避けたい」というissue #43由来の根本課題（大量ファイルによるタイムアウト・
   `index.jsonl`破損）を解消できない。
3. **性能面の裏付け**: `参考ディレクトリ/`配下に3,000件のダミーmarkdownを追加した状態で
   `find . -type f -name '*.md' -print0`と`git ls-files --cached --others --exclude-standard -z --
   .`を単純比較したところ、後者はignore対象を最初から走査しないため候補ファイル数が2件（前者は
   3,005件）に留まり、所要時間も短かった（実測: find 0.94秒 vs git ls-files 0.54秒。この程度の
   件数では体感差は小さいが、既存の懸念点が指摘する「巨大な外部OSSクローン」規模ではこの差が
   支配的になる）。加えて、現状版は各候補ファイルごとに`frontmatter_to_json`（`jq`のプロセス
   起動を複数回伴う）を実行するため、候補ファイル数そのものを減らせる方式Aの効果は件数差以上に
   大きいと考えられる。
4. **規約適合性**: 方式Aは`git ls-files`の引数に渡すのは`$target_dir`という短い文字列のみで、
   ファイル一覧自体はパイプ（ストリーム）で受け渡すため、`.claude/rules/shell-script-style.md`が
   禁じる「大きなJSONを`--argjson`/`--arg`等のコマンドライン引数として渡す」パターンに該当しない。
5. **既存テストへの影響**: `tests/test_extract_frontmatter.sh`は`frontmatter_to_json`・
   `resolve_repo_root`・concept_id/directory算出ロジックのみを検証しており、`main()`内の
   走査行（`find`または`git ls-files`）はテスト対象外。今回の変更は`main()`内の1行の置き換えのみで
   完結し、既存テストへの影響は無い。
6. **git依存の前提**: 変更後も`resolve_repo_root`が既に`git rev-parse --show-toplevel`に依存して
   いるため、「gitリポジトリ内での実行が前提」という制約は変わらない。`git ls-files`もgitリポジトリ
   外で実行すればエラーになるが、これは走査ロジック変更前から存在する制約の範囲内。
7. **spec/DDRへの反映方針**: `.claude/scripts/docs/spec/extract-frontmatter.md`の「未決定事項・
   懸念点」にある`参考ディレクトリ/`関連の記述は、issue #54の実装完了後（作業計画・実装フェーズ、
   flow-id 26の設計反映）で「解消済み」として仕様節（「実行方法」または新設の「走査方式」節）へ
   書き換える。当該記述はchangelog（影響範囲節のような点在記録）ではなく現在の仕様を説明する節の
   一部と判断したため、`.claude/rules/docs-workflow.md`の「過去issueのchangelogは書き換えない」
   制約には抵触しない。あわせて、走査方式という新しい設計判断のため
   `.claude/scripts/docs/ddr/0008-frontmatter抽出スクリプトの設計判断.md`（既にマージ済みで追記
   不可）とは別に、新規DDR（採用: 方式A、却下: 方式B）を作業計画で追加する。

**結論**: 方式A（`git ls-files --cached --others --exclude-standard`ベースへの置き換え）を採用する。

## 検証方法

調査結果は`plans/reflective-zooming-cake.md`の「調査」章に追記し、`worklog/`にも実機確認の
ログを残す。調査結果の可視化は表形式で十分（本issueは単一スクリプトの走査方式という単一トピックが
主題で、複数要素間の関連・依存関係を扱うものではないため、`reports/<plan名>.html`は
`.claude/skills/canvas-report/SKILL.md`のcanvas形式ではなく通常のTailwindCSS CDN方式で作成する）。
