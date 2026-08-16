---
title: 同一セッション内でのPlanモード複数回re-entry対応（issue #26）
type: plan
description: ExitPlanModeが常に同じplanファイルパスを提示し続ける制約に対し、git checkout復元に代えてcp/mvによるアーカイブ方式へ切り替える計画
tags: [plan-mode, claude-code, dev-tools, rule]
keywords: [exitplanmode, plan-mode-safety, archive-reentrant-plan, cp, mv, act1, worklog, issue-26]
---

# 同一セッション内でのPlanモード複数回re-entry対応（issue #26）

## Context

`.claude/rules/plan-mode-safety.md` の規則6は、「同一セッション内でPlanモードへ2回目以降
re-entryすると、ハーネスは1回目と同じplanファイルパスを提示し続ける」という制約（issue #7で判明）
への対処として、以下の手順を定めていた。

1. `plans/<新しい名前>.md` を別途作成し、そちらへ本当の計画内容を書く。
2. ハーネス提示パス（1回目のplanファイル、既にgit管理下でcommit済み）へ同じ内容を一時的に書き込む。
3. `ExitPlanMode` を呼ぶ（ハーネスはこのパスからしか読まないため）。
4. 承認後、`git checkout -- <ハーネス提示パス>` で直前のcommit内容へ復元する。

issue #26は、この「一時的に上書き→git checkoutで復元」という手順自体が挙動として不自然で、
復元忘れ・タイミングミスが起きると1回目のplan内容が破壊されるリスクを持つ、と指摘している。
実際、`git log --diff-filter=A -- 'plans/*.md'` で過去のcommitを調べると、1セッション内で
複数回re-entryした事例（例: `plans/pr4-review-followup2.md`）では、ハーネス提示パス側のファイルは
一切diffに現れておらず（＝一時上書き分はcommitされず消えている）、この手順が機能はしていたものの、
git履歴上は「一時的に存在した内容」が全く残らない、事故と隣り合わせの運用になっていたことが確認できる。

今回、`EnterPlanMode` を実際に呼び出して確認したところ、ハーネスは `plans/groovy-twirling-puffin.md`
のような**ランダムな英単語3語の名前**を提示する仕様であることを確認した（過去の大半のplanファイルも
同様の命名）。この事実を踏まえ、「一時上書き→復元」ではなく、**re-entry時に一つ前の計画内容を
`_actN` 付きの別名へcp/mvで退避してから、ハーネス提示パスへ直接新しい計画を書く**方式に切り替える。
これにより退避した旧内容もgit管理下に残り、"変な挙動"だった一時上書き＋復元の手順自体が不要になる。

## 実施内容

### 1. 新規スクリプト `dev-tools/src/archive-reentrant-plan.sh`

`shell-script-style.md` の規約（`set -euo pipefail`、BOM無しUTF-8・LF、JSON文字列をstdout出力、
`extract-frontmatter.sh` と同じ「sourceされたらmainを実行しない」ガード）に従う。

- 引数: `<plan_file_path>`（ハーネスがEnterPlanMode時に提示するパス。例 `plans/groovy-twirling-puffin.md`）、
  省略可の第2引数 `<worklog_dir>`（既定 `worklog`）。
- `plan_file_path` が存在しない（セッション最初のre-entryで、まだ何も書かれていない）場合は
  何もせず `{"archived": false, "reason": "plan file does not exist yet"}` を出力して終了する。
- 存在する場合（2回目以降のre-entryで、1つ前の計画が既に書き込み/commit済み）:
  1. `base`＝拡張子を除いたファイル名（例 `groovy-twirling-puffin`）。
  2. `plans/${base}_act${N}.md` が存在しない最小の`N`（1から開始）を探す。
  3. `cp` で `plan_file_path` → `plans/${base}_act${N}.md`（元のパスはそのまま残し、後続の
     `ExitPlanMode` 呼び出し時にハーネスが直接上書きできるようにする）。
  4. `worklog_dir` 配下で `*_${base}.md` に一致するファイルを探す（0件・複数件はエラーにせず
     警告扱いで続行。`shell-script-style.md`の「失敗しても継続したい処理はサブシェル経由」パターンに従う）。
     1件見つかれば `mv` で `<該当worklog>` → `<拡張子除いた名前>_act${N}.md`（同じ`worklog_dir`内）。
     これは新しいplanが同じ`base`を再利用してworklogファイル名（`worklog/日付_<plan名>.md`）が
     衝突するのを避けるため（cpではなくmvで元の名前を明け渡す）。
  5. 結果をJSONで出力（例:
     `{"archived": true, "suffix": 1, "planArchivedTo": "plans/groovy-twirling-puffin_act1.md", "worklogArchivedTo": "worklog/20260815_groovy-twirling-puffin_act1.md"}`。
     worklogが見つからなければ `"worklogArchivedTo": null`）。
- git操作（add/commit）は行わない。ファイル操作のみとし、commitは通常のフロー手順（flow-id 6/12）に委ねる。

### 2. テスト `tests/test_archive_reentrant_plan.sh`

`test_extract_frontmatter.sh` と同じ形式（`mktemp -d`で作業ディレクトリを作り、sourceしてmainガードで
関数のみ呼ぶ、`passed=N failures=N`を出力し失敗があれば`exit 1`）。検証観点:

- planファイルが存在しない場合は`archived: false`を返し、何も作成しない。
- 1回目のre-entry相当（`_act1`が無い状態）→ `_act1`で退避され、元のplanファイルは残る。
- 2回目のre-entry相当（`_act1`が既にある状態）→ `_act2`が使われる（番号の自動採番）。
- 対応するworklogファイルがある場合はmvで退避され、元の名前が空くこと。
- 対応するworklogファイルが無い場合でもエラー終了せず`worklogArchivedTo: null`になること。

作成後 `bash -n` で構文チェックし、`bash tests/test_archive_reentrant_plan.sh` を実行して
`failures=0` を確認する。

### 3. `.claude/rules/plan-mode-safety.md` の規則6を全面改訂

「背景」節（2026-08-15の事故の記録）はそのまま残す。規則6の本文を、上記スクリプトを使う手順へ
書き換える。

- 見出しは「同一セッション内でPlanモードへ複数回re-entryする場合の対処」のまま、末尾に
  「（issue #26でスクリプト化）」を追記。
- 手順:
  1. `EnterPlanMode` 実行後、ハーネスが提示するplanファイルパスを確認する。
  2. `bash dev-tools/src/archive-reentrant-plan.sh "<提示されたパス>"` を実行する
     （1回目のre-entryではno-opになるため、re-entry回数を問わず毎回実行してよい）。
  3. 出力された`planArchivedTo`（archivedがtrueの場合）を確認し、直前の計画が失われていないことを
     確かめる。
  4. ハーネス提示パスへ**直接**新しい計画本文を書く（従来のような別名ファイルの作成や
     `git checkout`による復元は不要）。
- 「一時的に上書きしてgit checkoutで復元する」手順（旧手順の2〜4）は削除する。
- frontmatterの`description`/`keywords`は値を更新する（キー自体は追加しない。
  `markdown-frontmatter.md`の「既存キーは変更せず不足キーのみ追記」は"キーの構成"に関する規定であり、
  内容更新を妨げるものではないと判断）。

## 対象外（やらないこと）

- `EnterPlanMode`前後にスクリプトを自動実行するhookの追加は行わない（ハーネス提示パスはツール実行後
  にしか分からず、PreToolUse/PostToolUseフックで確実に取得できる保証がないため）。規則6は引き続き
  「エージェントが手順として読んで実行する」運用とする。
- `docs/spec/` `docs/ddr/` への反映は、通常のフロー通りflow-id 16（設計反映）で行う。本Planでは
  対応方針（DDR化する）を決めるに留める。
- `.mrworkflow.json`へのworklogDir設定連携は行わない（スクリプトは`worklog`固定を既定値とし、
  第2引数で上書き可能にするに留める）。

## 検証方法

1. `bash -n dev-tools/src/archive-reentrant-plan.sh` / `bash -n tests/test_archive_reentrant_plan.sh`
   で構文チェック。
2. `bash tests/test_archive_reentrant_plan.sh` を実行し `passed=N failures=0` を確認する。
3. `.claude/rules/plan-mode-safety.md` を読み、規則6が新手順に置き換わっていること、
   「背景」節は変更されていないことを目視確認する。
