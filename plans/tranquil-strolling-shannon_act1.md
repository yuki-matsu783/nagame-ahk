---
title: コミットは必ずcommitスキル経由で行うルールの追加
type: log
description: issue #39対応。commitスキルの利用を「ユーザーが/commitと明示入力した場合のみ」から「AIエージェントが自律的にコミットする場面も含め常時必須」へ広げるルール整備の計画
tags: [git-workflow, commit-skill, issue-mr-flow, rule]
keywords: [commit, コミット, スキル, git-workflow, issue-mr-flow, frontmatter]
---

# コミットは必ずcommitスキル経由で行うルールの追加（issue #39）

## Context

issue #39: 「コミットSkillを利用するようにルールを記載する」。現状、`commit`スキル
（[.claude/skills/commit/SKILL.md](../.claude/skills/commit/SKILL.md)）のfrontmatter descriptionは
「Use ONLY when the user explicitly invoked /commit」となっており、AIエージェントが
issue-mr-flowの全体フロー内で自律的にコミットする場面（flow-id 6/12/18/22「commit, push して
レビュー依頼を行う」担当:エージェント）では、このスキルを経由せず直接 `git commit` を実行して
しまう余地がある。これが「スキルが使われたり使われなかったりしている」という現状の原因。
受け入れ条件は「すべてのコミットがスキルを利用して行われる」こと。

対応方針は、コミットを行う可能性がある3箇所（スキル自身の呼び出し条件／ルール／フロー定義）で
一貫して「`commit`スキル必須」を明記し、どこから読んでも同じ結論に辿り着けるようにする。

## 変更するファイル

1. **[.claude/skills/commit/SKILL.md](../.claude/skills/commit/SKILL.md)**
   - frontmatter `description`: 「Use ONLY when the user explicitly invoked /commit」という限定を
     外し、「ユーザーが明示的に `/commit` を入力した場合・AIエージェントが本リポジトリで
     コミットを作成する場面（issue-mr-flowのflow-id 6/12/18/22等）の両方で使う」旨に広げる
     （Flow: 以降の説明文はそのまま維持）。
   - 本文冒頭（`## 絶対ルール`の前）に `## 呼び出しタイミング` 節を追加し、「本リポジトリで
     コミットを作成する際は常に本スキルを経由する。`git commit`の直接実行は行わない」ことと、
     上記の2パターン（明示`/commit`／エージェント自律コミット）を明記する。

2. **[.claude/rules/git-workflow.md](../.claude/rules/git-workflow.md)**
   - 「ブランチ運用」節の後、「worklogの配置・命名」節の前に `## コミット運用` 節を新設し、
     「コミットは常に`commit`スキル経由で作成する。ユーザーが明示的に`/commit`と入力した場合に
     限らず、AIエージェントが自律的にコミットする場面（issue-mr-flowのflow-id 6/12/18/22等）でも
     同様。`git commit`の直接実行は行わない」ことを記載し、詳細（絶対ルール・実行フロー）は
     `commit`スキル本体を参照させる。

3. **[.claude/skills/issue-mr-flow/SKILL.md](../.claude/skills/issue-mr-flow/SKILL.md)**
   - 全体フロー表のflow-id 6/12/18/22（「commit, push してレビュー依頼を行う」）のセル文言に
     「`commit`スキル経由で」を追記し、フロー定義そのものから直接わかるようにする。
   - 末尾「詳細ルールへのポインタ」の既存箇条書き
     （`ブランチ命名規則・squash mergeの方針: .claude/rules/git-workflow.md`）を
     「ブランチ命名規則・コミット運用（`commit`スキル必須使用）・squash mergeの方針」に拡張する。

## 対象外

- `docs/spec/` `docs/ddr/` への追記は行わない（今回の変更対象自体がAIアセット
  （`.claude/rules/` `.claude/skills/`）であり、アプリ機能の仕様変更ではないため）。
- `commit`スキルの実行フロー自体（AskUserQuestionによる確認等）は変更しない。呼び出し条件のみ広げる。

## 検証方法

- 3ファイルとも `type: skill` / `type: rule` frontmatterの既存キー・値を変更していないことを目視確認
  （`description`は`commit`スキルのみ、既存ルールに基づき変更対象）。
- 3ファイル間で「commitは常にスキル経由」という結論が矛盾なく一致していることを確認する
  （テストコードは無いドキュメントのみの変更のため、レビューによる確認が中心）。
