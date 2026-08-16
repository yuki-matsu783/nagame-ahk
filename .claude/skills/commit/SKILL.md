---
name: commit
description: 'Generate a Japanese commit message with Conventional Commits prefix and create one or more atomic commits. Use whenever a commit needs to be made in this repository — both when the user explicitly invokes /commit AND whenever an AI agent commits autonomously as part of the issue-mr-flow (flow-id 6/12/18/22). All commits in this repo MUST go through this skill; direct git commit is blocked by a PreToolUse hook. Flow: git status → confirm with user via AskUserQuestion → filter sensitive/junk files → dev-tools/src/create-commit.sh (NO Claude footer)'
title: git commit標準化
type: skill
tags: [issue-mr-flow, workflow, skill]
keywords: [commit, コミット]
---

# /commit スキル

`/commit` が呼ばれた時、変更内容を分析して日本語のコミットメッセージを自動生成し、コミット作成までを対話的に進める。

## 呼び出しタイミング

このスキルは以下の2パターンいずれでも使う（issue #39: 「すべてのコミットがスキルを利用して
行われる」が受け入れ条件）。

- ユーザーが明示的に `/commit` と入力した場合
- AIエージェントが本リポジトリでコミットを作成する場面全般
  （`.claude/skills/issue-mr-flow/SKILL.md` の全体フローflow-id 6/12/18/22
  「commit, push してレビュー依頼を行う」等）

`git commit` の直接実行は `.claude/hooks/block-direct-git-commit.sh`（PreToolUse hook）により
機構的にブロックされる（`.claude/rules/git-workflow.md` の「コミット運用」節参照）。このスキルの
Step 5は `dev-tools/src/create-commit.sh` というラッパースクリプト経由でコミットするため、
hookの対象にならず正規に実行できる。

## 絶対ルール

- **`Co-Authored-By: Claude` などのフッターは絶対に付けない**
- **`git add .` / `git add -A` は使わない** — 必ず個別ファイル指定
- **`--no-verify` は使わない**（フックが失敗したら原因を直す）
- **`git commit --amend` は使わない**（常に新規コミット）
- **失敗時に `git reset` などで自動ロールバックしない** — 状況を報告してユーザに判断を仰ぐ
- **ステージングされていない変更（unstaged / untracked）はコミット対象に含めない** — ユーザに質問せず自動的に除外する。コミット対象は `git diff --cached` で確認できるステージング済み変更のみ

## 実行フロー

### Step 1: 現状把握

並列で以下を実行：

- `git status`（`-uall` フラグは使わない）— ステージング状態の確認用
- `git diff --cached`（**staged のみ**。unstaged は対象外なので見ない）
- `git log --oneline -10`（リポジトリのコミットスタイル参考用）

**ステージング済みの変更が1つもない場合**は「ステージング済みの変更がありません。`git add` でコミット対象をステージングしてください」と伝えて終了する。unstaged/untracked のファイルが残っていても**ユーザに質問しない**（自動的にコミット対象外として扱う）。

### Step 2: 変更内容を分析

取得した diff から以下を判定：

**(a) prefix判定** — 各変更ファイル群に対して以下から選ぶ：

| prefix | 意味 |
|---|---|
| `feat` | 新機能の追加 |
| `fix` | バグ修正 |
| `docs` | ドキュメントのみの変更 |
| `style` | コードの意味に影響しない変更（空白・フォーマット等） |
| `refactor` | バグ修正でも機能追加でもないコード変更 |
| `test` | テストの追加・修正 |
| `chore` | ビルド補助ツール・雑務（`build` 以外） |
| `perf` | パフォーマンス改善 |
| `ci` | CI設定の変更 |
| `build` | ビルドシステム・外部依存の変更 |
| `revert` | 以前のコミットの取り消し |

**(b) 論理的まとまり判定** — 内容（prefixが変わるか）+ ファイルパスの両方を見て、複数のスコープに分かれるかを判定。

### Step 3: ユーザに確認（AskUserQuestion 使用）

**単一スコープの場合：**

`AskUserQuestion` で1問：
- question: 「このコミットメッセージで作成しますか？」
- header: 「コミット確認」
- options:
  - 「OK」 — 提案通り作成
  - 「メッセージ修正」 — ユーザに自由入力させる
  - 「キャンセル」 — 中止

提案メッセージはチャット本文に表示してから質問する。除外予定のファイル（クレデンシャル系・副産物）があれば明示。

**複数prefix混在の場合：**

`AskUserQuestion` で1問：
- question: 「複数のスコープが混在しています。どうしますか？」
- header: 「分割確認」
- options:
  - 「提案通り分割」 — 複数コミットを順に作成
  - 「1コミットに統合」 — 主要prefixを使って1つにまとめる
  - 「キャンセル」 — 中止

分割案は AskUserQuestion を出す前にチャット本文に明示：
```
コミット1: feat: ○○機能を追加
  - src/feature.ts
  - src/feature.test.ts
コミット2: docs: READMEを更新
  - README.md
```

### Step 4: ファイルフィルタ

`git add` 対象から以下を**自動除外**：

**クレデンシャル系（絶対除外）**
- `.env`, `.env.*`
- `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.ppk`
- `credentials.json`, `service-account*.json`
- `id_rsa`, `id_ed25519`, `id_ecdsa`
- `.aws/credentials`, `.netrc`
- `secrets.yml`, `secrets.yaml`

**開発環境の副産物**
- `.DS_Store`, `Thumbs.db`, `desktop.ini`
- `*.swp`, `*.swo`, `*~`
- `node_modules/`, `vendor/`, `__pycache__/`
- `dist/`, `build/`, `out/`, `target/`
- `*.pyc`, `*.class`, `*.o`
- `*.log`, `logs/`
- `tmp/`, `temp/`, `*.tmp`, `*.bak`, `*.orig`

**除外したファイルがあれば**、コミット実行前にチャットに明示：
```
以下は自動除外しました（コミットには含めません）：
- .DS_Store
- node_modules/...
```

### Step 5: コミット実行

`git add` / `git commit` を直接実行せず、`dev-tools/src/create-commit.sh` を使う
（`git commit` の直接実行は `.claude/hooks/block-direct-git-commit.sh` によりブロックされる）。

```
bash dev-tools/src/create-commit.sh --message "<prefix>: <日本語サマリ>" -- <file1> [file2 ...]
```

**コミットメッセージ形式：**
- `<prefix>: <日本語サマリ>` の **1行のみ**
- 本文・フッター・Co-Authored-By など一切付けない

複数コミットの場合は順番に Step 4-5 を繰り返す。途中で失敗したら**そこで停止**して状況を報告（自動 reset しない）。

## 備考
<レビュアーが知っておくべきこと、未対応事項。なければセクション省略>
```

**条件付きで以下を追加（該当時のみセクション追加、なければ省略）：**

- **関連Issue**：コミットメッセージや diff コメントに `#123` などの参照があれば
  ```markdown
  ## 関連
  - Closes #123
  ```

- **破壊的変更**：API・公開インターフェイスの非互換変更を検知したら
  ```markdown
  ## 破壊的変更
  - <何が変わったか・移行方法>
  ```

**変更内容の列挙ルール：**
- 主要ファイルのみ列挙（大量にある場合はディレクトリ単位で要約）
- 自動除外したファイルは含めない

## エラー時の対応

- **pre-commitフック失敗** → エラーを表示し、原因を修正してから新規コミットを作る（amend禁止）
- **複数コミット中に失敗** → そこで停止、`git status` で現状を表示してユーザに判断を仰ぐ
- **コミット対象がない** → 「コミットする変更がありません」と伝えて終了

## してはいけないこと

- TodoWrite / Agent ツールの使用
- `git push` の実行（ユーザが明示的に頼まない限り）
- 機密ファイルが残っていてもユーザに警告せず除外（必ず明示する）
- ユーザ確認を飛ばして自動でコミット作成