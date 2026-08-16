---
title: AIエージェント共通ルール
type: rule
description: 複数のAIコーディングエージェント（Claude Code, Gemini CLI等）が共通で従うルール・プロジェクト概要・開発実行方法
tags: [agents, rule]
keywords: [issue-mr-flow, plan-mode, autohotkey, tray, hotkey, claude-code, gemini-cli]
---

## ルール

- 開発フロー全体（issueの起票〜マージ）は `.claude/skills/issue-mr-flow/SKILL.md` を参照する
  （唯一の実装フロー定義）。ごく小さな変更を除き、全タスクはissueを起点に進める。
- いかなるタスク（調査、設計、コード作成、テスト、リファクタリングなど）も、**実作業を開始する前に必ず「計画（Plan）」を立ててユーザーに提示**する
- 計画はplansディレクトリ配下にセッション単位で保存する
- 計画がユーザーに承認（Approve）されるまで、ファイルの書き換えやコマンドの実行を行ってはいけない
- コーディング規約・ディレクトリ構成・ドキュメント運用などの詳細ルールは `.claude/rules/` 配下を参照する

## プロジェクト概要

`nagame-ahk` は AutoHotkey v2 で実装する常駐ホットキー／自動化スクリプトです。
トレイに常駐し、ホットキー入力やウィンドウイベントをトリガーに、定義された自動化処理を実行します。

## 開発・実行

- 実行: `src/main.ahk` を AutoHotkey v2（v2.0系）で実行する。
- 推奨エディタ: VSCode + AutoHotkey v2 拡張機能（構文ハイライト・デバッグ用）。
