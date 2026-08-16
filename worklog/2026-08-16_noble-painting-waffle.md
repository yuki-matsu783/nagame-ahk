---
title: worklog issue #28 対応工数レポート修正
type: log
description: issue #28（対応工数レポートの日本語修正・経過時間記録追加）の作業ログ
tags: [usage-report, issue-28, worklog]
keywords: [対応工数, 経過時間, transcript, timestamp, usage-tracking, mystery-diff]
---

# worklog: 2026-08-16_noble-painting-waffle

## 経緯・気づいたこと

- `feature-28-issue` ブランチを `origin/main`（6ba2730）から作成し、Draft PR #29 を作成した直後、
  作業ツリーに**自分では作成していない未コミット差分**が7ファイル存在しているのを発見した。
  - `git show HEAD:.gitignore` と作業ツリーの内容を比較し、コミット履歴のどの時点にも存在しない
    内容であることを確認済み（フック（session-start.sh / post-push-usage-report.sh）の処理内容を
    確認したが、いずれもこの種のドキュメント文言を書き換えるロジックは持たない）。
  - 内容はissue #28の要求（「セッション使用量レポート」→「対応工数レポート」への文言統一）と
    完全に一致していた。
  - ユーザーに確認したところ、「このまま活かして作業を進める」との回答を得た。
  - さらに、この差分には**マージ済みDDR（`docs/ddr/0006-...md`）自体のタイトル/本文の書き換え**も
    含まれていたため、`docs-workflow.md`の「DDRは一度マージしたら追記のみ（変更不可）」との整合性を
    別途確認したところ、「この種の書き換えは過去に承認済みの対応」との回答を得たため、そのまま
    活かす方針で確定した。
- なお `HANDOFF.md`（`origin/main`にマージ済みの内容）に、issue #26セッション由来の別の「未解決の
  内容」記載（`.claude/rules/markdown-frontmatter.md`・`worklog/TEMPLATE.md`の出所不明差分）が
  残っていたが、該当2ファイルは現在の作業ツリーで無変更（`git diff`差分なし）であることを確認した。
  issue #28とは無関係かつ現状再現しないため、本ブランチのHANDOFF更新時にこの記載は解消済みとして
  整理した。

## Plan

`plans/noble-painting-waffle.md` 参照。要点: 既存の文言統一差分（出所不明・活用確定）に加えて、
`.claude/hooks/lib/UsageTracking.sh` に経過時間（`elapsedSeconds`）の集計ロジックを追加し、
`post-push-usage-report.sh` のレポートに「対応工数（目安）」として表示する。ドキュメント
（`dev-tools/docs/spec/issue-mr-workflow.md`）とテスト（`tests/test_usage_tracking.sh`新設）も
合わせて対応する。

## 次にやること

- 人間によるPlanレビュー完了後、flow-id 11から実装に着手する。
