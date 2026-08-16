---
title: worklog issue #26 同一セッション内Planモード複数回re-entry対応
type: log
description: issue #26対応（Planモードre-entry時のarchiveスクリプト化）の作業ログ
tags: [worklog, plan-mode, dev-tools]
keywords: [exitplanmode, plan-mode-safety, archive-reentrant-plan, act1, issue-26]
---

# worklog: groovy-twirling-puffin

対象: issue #26 同一セッション内でPlanモードへ複数回re-entryしたときの挙動修正（2026-08-16）。
plan: `plans/groovy-twirling-puffin.md`

## 試したこと

- `git log --all --diff-filter=A --name-only -- 'plans/*.md'` で過去のplanファイル名を調査し、
  ほぼ全て harness提示のランダム英単語3語名（例: `amber-thistle-fox.md`）がそのまま使われている
  ことを確認した。手動命名は `planmode-safety-rule.md` `pr4-review-followup2.md` の2件のみ。
- `git show 3c75b50 --stat` で、2回目re-entry時に旧手順（一時上書き→`git checkout`復元）を使った
  commitを確認したところ、harness提示パス側のファイルはdiffに一切現れておらず、一時上書き分は
  git履歴に全く残らない運用になっていたことを確認した。
- `EnterPlanMode` を実際に呼び出し、本セッションでのharness提示パスが `plans/groovy-twirling-puffin.md`
  であることを確認した（過去事例と同じ命名規則）。

## うまくいったこと

- 「一時上書き→git checkout復元」をやめ、「re-entry時に前回のplan/worklogを`_actN`付きの別名へ
  cp/mvで退避してから、harness提示パスへ直接新しい計画を書く」方式に切り替える設計で合意。
- `dev-tools/src/archive-reentrant-plan.sh` を実装（`extract-frontmatter.sh`と同じ
  「sourceされたらmainを実行しない」ガード形式）。planファイルはcp（元は残す）、対応する
  worklogファイルはmv（元の名前を明け渡す）、`_actN`は既存ファイルを避けて自動採番。
- `tests/test_archive_reentrant_plan.sh` を実装し全19アサーション成功（`passed=19 failures=0`）。
  1回目は`_act1`、既に`_act1`がある状態で呼ぶと`_act2`になることを確認。
- `.claude/rules/plan-mode-safety.md` 規則6を全面改訂。旧手順（一時上書き→`git checkout`復元）を
  廃止し、スクリプトによる退避方式に置き換えた。規則2「計画ごとに新しいplanファイル名を使う」との
  見かけ上の矛盾（ファイル名自体は使い回す）についても、規則2の趣旨（内容を失わないこと）は
  `_actN`退避で満たされる旨を追記した。
- テスト実装中、絶対パス（`mktemp -d`）を使うとネイティブ`jq.exe`経由でMSYSのパス自動変換が
  発生し、JSON中のパス文字列がWindows形式に化けることを確認した（`shell-script-style.md`の
  「git bashのパス変換の落とし穴」と同種の事象）。実運用では相対パス（例: `plans/xxx.md`）で
  呼ばれるため影響しないことを手動確認（`plans/demo-plan.md`での動作確認）済み。テスト側は
  該当アサーションをbasename比較に変更して回避した。
- ユーザー指摘を受け、規則2「計画ごとに新しいplanファイル名を使う」を「既存の承認済み計画の
  内容を失わない」に改題し、規則6の退避手順が例外として矛盾しないことを規則2側にも明記した。

## ダメだったこと

- `EnterPlanMode`/`ExitPlanMode`をhookで自動的にフックしてarchiveスクリプトを自動実行する案は
  見送った。harness提示パスはツール実行後にしか分からず、PreToolUse/PostToolUseフックで確実に
  値を取得できる保証がないため（対象外として計画に明記）。

## 次の一歩

- flow-id 16（設計反映）で `docs/ddr/` にDDRを追加する。
- MRでのレビュー依頼（flow-id 12〜）。

---
