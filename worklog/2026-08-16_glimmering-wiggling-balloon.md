---
title: issue作成スクリプト・スキルの追加 worklog
type: log
description: issue #25対応。plans/glimmering-wiggling-balloon.mdの実行ログ
tags: [issue-25, vcs, provider, skill, automation]
keywords: [create-issue.sh, issue-create, build_issue_body, new_issue]
---

# worklog: issue作成スクリプト・スキルの追加（issue #25）

対応するplan: `plans/glimmering-wiggling-balloon.md`

## 2026-08-16

- issue #25を取得、ブランチ `feature-25-create-issue-script-skill` と Draft PR #36 を作成。
- Planモードで実装方針を検討。ユーザーへの確認事項:
  - スキル配置: 独立した新規スキル（`.claude/skills/issue-create/`）を選択（issue-mr-flowへの
    サブコマンド追加ではなく）。
  - GitLab対応: GitHub/GitLab両方実装する方針（GitLab側は既存の`gitlab_*`関数群と同様「未検証」）。
  - Plan承認済み。次は実装（flow-id 11）に着手する。

## 2026-08-17

- 実装完了（flow-id 11）:
  - `dev-tools/src/vcs/Provider.sh`: `build_issue_body`（純粋関数）、`new_issue`（ディスパッチ）を追加。
  - `dev-tools/src/vcs/Github.sh`: `github_new_issue`を追加（`gh issue create`実行→出力URLから
    issue番号を`grep -oE '[0-9]+$'`で抽出→`github_get_issue`で正規化）。
  - `dev-tools/src/vcs/Gitlab.sh`: `gitlab_new_issue`を追加（同様のパターン、既存関数群と同じく
    【未検証】注記付き）。
  - `dev-tools/src/create-issue.sh`（新規CLI）: `--title/--purpose/--current/--expected/--acceptance`
    の5フラグを解析し、`build_issue_body`→`test_issue_sections`（安全網）→`new_issue`で作成。
  - `.claude/skills/issue-create/SKILL.md`（新規スキル）: AIが依頼内容から4見出しを埋め、ユーザー
    確認を経てから`create-issue.sh`を呼び出す手順を定義。
  - `.claude/skills/issue-mr-flow/SKILL.md`: flow-id 1担当セルに `issue-create` スキルへの
    導線を追記。
  - `tests/test_vcs_provider.sh`: `build_issue_body`のテストケースを追加（4見出し欠落なし・
    各セクションの内容が本文に含まれることを検証）。
- 検証:
  - `bash -n` で新規`.sh`（`create-issue.sh`）を含む変更ファイルの構文チェック済み。
  - `bash tests/test_vcs_provider.sh` で14件全てpass。
  - 実機テスト: `create-issue.sh`を実際に実行し、issue #38を作成→4見出し構成で正しく作成されて
    いることを確認→検証用のため即クローズ。GitHub側は問題なく動作した。GitLab側（`glab`）は
    このリポジトリのremoteがGitHubのみのため実機確認できていない（既存の他gitlab_*関数群と同じ
    制約）。
