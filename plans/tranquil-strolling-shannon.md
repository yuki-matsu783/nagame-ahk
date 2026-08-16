---
title: commitスキルの確認ステップ廃止・複数prefix自動分割
type: log
description: issue #45対応。commitスキルのStep 3（AskUserQuestionによるコミット前確認）を廃止し、単一スコープ・複数prefix混在いずれの場合も確認なしでコミットを実行する（複数prefixは自動分割）よう書き換える計画
tags: [commit-skill, issue-mr-flow, skill]
keywords: [commit, コミット, スキル, askuserquestion, 確認, 分割, prefix]
---

# commitスキルの確認ステップ廃止・複数prefix自動分割（issue #45）

## Context

issue #45: 現在の `commit` スキル（`.claude/skills/commit/SKILL.md`）は、Step 3で
`AskUserQuestion` を使い、コミットメッセージ案をユーザーに提示して承認を得てから
コミットを実行している（単一スコープ／複数prefix混在の両パターンとも）。ユーザーから、
この確認ステップを廃止し、生成したコミットメッセージでそのままコミットしてよい、
複数prefix混在時も確認せず自動的に分割してコミットする、という要望を受けた。

このスキルは直近のissue #39（PR #40、マージ済み）で「AIエージェントが自律的にコミットする
場面（issue-mr-flowのflow-id 6/12/18/22）でも必ずこのスキル経由でコミットする」という
運用に変わったばかりであり、`main`には既にその内容（`dev-tools/src/create-commit.sh`
ラッパー経由のStep 5、`## 呼び出しタイミング`節）が反映済み。本issueはその上に
「確認ステップの廃止」のみを追加で変更する。

## 実装前の準備

`feature-45-commit-skill-skip-confirmation` ブランチは、PR #40（issue #39）マージ前の古い`main`から
作成したため、issue #39の内容（wrapperスクリプト経由のStep 5等）を含んでいない。承認後の実装着手時に
まず `git fetch origin main` → 当ブランチを最新の`origin/main`へ rebase（またはリセットして作り直し）
してから、本計画の変更を加える。

## 変更するファイル

**`.claude/skills/commit/SKILL.md`（既存編集、これのみ）**

1. **frontmatter `description`**: 「confirm with user via AskUserQuestion →」の記述を削除し、
   実際のフロー（現状把握→分析→フィルタ→コミット実行、確認なし）に合わせて書き換える。
2. **Step 3「ユーザに確認（AskUserQuestion 使用）」を削除**。単一スコープ・複数prefix混在
   いずれの分岐もこのステップごと無くす。
3. **ステップ番号を振り直す**: 現Step 4（ファイルフィルタ）→Step 3、現Step 5（コミット実行）
   →Step 4。
4. **新Step 4（コミット実行）に、複数prefix混在時の扱いを明記**: Step 2(b)の「論理的まとまり
   判定」で複数スコープと判定した場合、確認を挟まず prefixごとに複数コミットへ自動分割して
   順次実行する（現在の「分割案をチャット本文に明示してから質問する」という提示自体は、
   透明性のため残す。「質問する」だけを取り除き、「提示してそのまま実行する」に変える）。
   単一スコープの場合も同様に、提案メッセージをチャット本文に表示したうえでそのまま実行する
   （表示自体は残し、承認待ちを無くす）。
5. **「してはいけないこと」節から「ユーザ確認を飛ばして自動でコミット作成」を削除**
   （旧ルールの逆が新しい正式な挙動になるため）。
6. 「キャンセル」選択肢は無くなる（確認自体が無くなるため）。ユーザーが止めたい場合は
   通常のツール実行中断（Esc等）で対応する想定とし、スキル側に特別な記載は追加しない。

## 対象外

- `.claude/rules/git-workflow.md` / `.claude/skills/issue-mr-flow/SKILL.md` 等、他ファイルは
  commitスキルのStep 3に関する記述を持たないため変更不要（grep済み・確認済み）。
- Step 4のファイルフィルタ（クレデンシャル・副産物の自動除外）ロジック自体は変更しない。
- コミットメッセージ生成ロジック（prefix判定・論理的まとまり判定）自体は変更しない。

## 検証方法

- 変更後の `.claude/skills/commit/SKILL.md` を通読し、Step番号の整合性・
  「AskUserQuestion」「確認」という語がフロー本文に残っていないことを確認する。
- 本issue自身のコミット（flow-id 6）を、変更後のSKILL.mdの手順どおり
  （確認を挟まず `dev-tools/src/create-commit.sh` を実行）に実施し、
  想定通り動くことをエンドツーエンドで確認する。
