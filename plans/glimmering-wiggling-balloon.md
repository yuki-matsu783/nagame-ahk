---
title: issue作成スクリプト・スキルの追加
type: log
description: issue #25対応。標準4見出しに沿ったissueをスクリプト実行・AIスキル経由で作成できるようにする計画
tags: [issue-25, vcs, provider, skill, automation]
keywords: [create-issue.sh, issue-create, build_issue_body, new_issue, gh issue create, glab issue create]
---

# issue作成スクリプト・スキルの追加（issue #25）

## Context

現状issueはGitHubのUIからしか作成できず、`.github/ISSUE_TEMPLATE/task.md` /
`.gitlab/issue_templates/task.md` の標準4見出し（目的・現状・期待する動作・受け入れ条件）に沿った
issueを、スクリプト実行やAIエージェント（skill）経由で作成する手段がない。issue #25は以下2点を
受け入れ条件とする。

- スクリプトを実行してissueが作成できる
- skillを利用してAIがissueを作成できる

`dev-tools/src/vcs/Provider.sh` には既に `get_issue`（プロバイダ非依存ディスパッチ）と
`REQUIRED_ISSUE_SECTIONS` / `test_issue_sections`（4見出しの過不足チェック）があり、対称的な
「作成」操作を同じ構造で追加するのが最も自然。スキルは独立スキル（`.claude/skills/issue-create/`）
として新設する方針（ユーザー確認済み）。GitHub/GitLab両方実装する（ユーザー確認済み。GitLab側は
既存の`gitlab_*`関数群と同様「未検証」注記を付ける）。

## 実施内容

### 1. `dev-tools/src/vcs/Provider.sh` に追加

- `build_issue_body(purpose, current, expected, acceptance)`: 標準4見出しでissue本文を組み立てる
  純粋関数（外部コマンド呼び出しなし、テスト可能）。
- `new_issue(title, body)`: `get_provider` の判定で `github_new_issue`/`gitlab_new_issue` へ
  ディスパッチする（既存の `new_draft_merge_request` 等と同じパターン）。

### 2. `dev-tools/src/vcs/Github.sh` に追加

- `github_new_issue(title, body)`: `gh issue create --title ... --body ...` を実行し、出力される
  issue URLから番号を抽出、`github_get_issue` を呼んで既存と同じ形（number/title/body/url/slug）の
  JSONを返す。番号抽出に失敗した場合はエラーメッセージを出して`return 1`。

### 3. `dev-tools/src/vcs/Gitlab.sh` に追加

- `gitlab_new_issue(title, body)`: `glab issue create --title ... --description ... --yes` を実行し、
  同様にURLから番号抽出→`gitlab_get_issue`で正規化。ファイル冒頭の既存「未検証」注記の対象に含める
  （関数コメントにも一言添える）。

### 4. `dev-tools/src/create-issue.sh`（新規、`dev-tools/src/`直下）

- `Provider.sh` をsourceし、`--title` `--purpose` `--current` `--expected` `--acceptance` の
  5つの必須フラグを解析。
- `build_issue_body` で本文組み立て→`test_issue_sections` で欠落チェック（安全網）→`new_issue`
  で作成→結果JSONをstdoutへ出力。
- 引数不足時はusageを表示して`exit 1`。
- これが受け入れ条件1「スクリプトを実行してissueが作成できる」を満たす（人間が直接実行してもよい）。

### 5. `.claude/skills/issue-create/SKILL.md`（新規スキル）

- frontmatter: `name: issue-create`, `type: skill`, `description`に「いつ使うか」
  （issue-mr-flowのflow-id 1＝人間による起票をAIが代行したいときに使う）を明記。
- 実行フロー:
  1. ユーザーの依頼内容から目的・現状・期待する動作・受け入れ条件・タイトルを埋められるか確認し、
     不足があれば質問で補う（内容を勝手に創作しない）。
  2. 組み立てた内容（タイトル＋4項目）をユーザーに提示し、issue作成の実行可否を確認する
     （GitHub/GitLab上に公開される操作のため、他のissue-mr-flow同様に人間の明示的な合図を待つ）。
  3. 承認後、`dev-tools/src/create-issue.sh` を該当フラグ付きで実行する。
  4. 結果（issue番号・URL）を提示し、続けて `issue-mr-flow start <issue番号>` で着手するか
     ユーザーの意向を確認する。
- これが受け入れ条件2「skillを利用してAIがissueを作成できる」を満たす。

### 6. `.claude/skills/issue-mr-flow/SKILL.md` への軽微な追記

flow-id 1の担当セルに「（AIが代行する場合は `issue-create` スキル）」を一言添え、唯一の実装フロー
定義から新スキルへの導線を作る（内容の再定義はしない、参照のみ）。

### 7. テスト: `tests/test_vcs_provider.sh` に追記

`build_issue_body` の出力に対して `test_issue_sections` を通し、欠落なしになることを検証するケースを
既存の `to_slug` / `test_issue_sections` セクションと同じ形式（`assert_equal`/`assert_true`）で追加する。
`new_issue`/`github_new_issue`/`gitlab_new_issue`（`gh`/`glab`呼び出しを伴う）はこのファイルの既存方針
どおりテスト対象外とする。

## 対象外

- `docs/spec/` への反映はflow-id 16（設計反映）で別途行う（このplanの対象は実装のみ）。
- `gh issue create` のその他オプション（label/assignee/milestone等）はissueの受け入れ条件に無いため
  対象外。
- GitLab側の実機動作確認（`glab` 未インストール環境のため、既存の他GitLab関数群と同様に未検証のまま
  実装のみ行う）。

## 検証方法

- `bash -n` で新規`.sh`ファイルの構文チェック。
- `bash tests/test_vcs_provider.sh` で `build_issue_body` を含む既存テストがpassすることを確認。
- `bash dev-tools/src/create-issue.sh --title "..." --purpose "..." --current "..." --expected "..." --acceptance "..."` を実機（このリポジトリのGitHub remote）で実行し、実際にissueが作成されること・
  作成されたissueが4見出し構成になっていることを確認（副作用のある操作のため、実行前にユーザーへ
  一言確認する）。
- `.claude/skills/issue-create/SKILL.md` をAIエージェント自身が読み、想定通りの手順で
  `create-issue.sh` を呼び出せる内容になっているかをレビューする（実際のスキル起動テストは
  次セッション以降の利用時に兼ねる）。
