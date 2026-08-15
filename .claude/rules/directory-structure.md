---
alwaysApply: true
title: ディレクトリ構成
type: rule
description: リポジトリのディレクトリ構成と配置方針を定めたルール
tags: [directory-structure, rule]
timestamp: "2026-08-16T05:31:36"
---

# ディレクトリ構成

```
nagame-ahk/
├── src/
│   ├── main.ahk            # エントリーポイント。#Include の集約と起動呼び出しのみを行う
│   ├── config/
│   │   └── Settings.ahk    # 定数・ユーザー設定値
│   ├── core/
│   │   ├── App.ahk         # 起動処理などアプリのライフサイクル管理
│   │   ├── Hotkeys.ahk     # ホットキー登録の集約（実処理は features/ に委譲）
│   │   └── TrayMenu.ahk    # トレイアイコン・右クリックメニュー
│   ├── features/           # 機能単位の自動化ロジック（1機能 = 1ファイル目安）
│   └── lib/                # 汎用ユーティリティ（複数機能から使い回す部品）
├── assets/
│   └── icons/               # トレイアイコンなど
├── docs/
│   ├── README.md            # docs配下の目次
│   ├── spec/                 # 機能ごとの正史仕様（docs/spec/機能名.md）
│   └── ddr/                  # 意思決定ログ（DDR: Design Decision Record。追記のみ）
├── dev-tools/                # 開発者向けツール一式。アプリ本体（src/, docs/）とは分離管理
│   ├── src/                   # ビルドスクリプト等（例: build.sh）
│   └── docs/
│       ├── README.md          # dev-tools配下の目次
│       └── spec/               # dev-tools機能ごとの正史仕様（構成・運用はdocs/spec/に準ずる）
├── build/                    # Ahk2Exeビルド成果物の出力先（.gitignore対象。コミットしない）
├── tests/                    # 手動/自動テスト用スクリプト
├── .claude/
│   ├── rules/                 # AI向け詳細ルール（このファイルもここにある）
│   ├── skills/                 # /issue-mr-flow（唯一の実装フロー定義）・/ahk-implement などのスキル定義
│   └── hooks/                  # Claude Codeのhookスクリプト（SessionStart/Stop/PostToolUse等）。
│       └── lib/                 # 複数hookスクリプトで使い回す共通ロジック（例: UsageTracking.ps1）
├── plans/                    # AIエージェントのplanモードが出力する計画ファイル。タスクごとに新規生成し、そのままコミットして履歴として残す
├── worklog/                  # 実装中の詳細な試行錯誤ログ（日付_<planファイル名>.md）。PR作成前の設計反映でspec/ddrへ反映し削除する（.claude/skills/issue-mr-flow/SKILL.md参照）
├── .gitignore
├── CLAUDE.md                    # プロジェクト概要・開発実行・.claude/rules/ へのポインタ
├── HANDOFF.md                   # セッション間・作業者間の軽量な引継ぎメモ（ブランチの現在地・次回やること等。詳細な試行錯誤はworklog/へ）
└── README.md
```

## 配置の指針

- `main.ahk` にロジックは書かない。`#Include` とアプリ初期化呼び出しのみとする。
- 機能を追加するときは `features/` に1ファイル追加し、必要なホットキーは `core/Hotkeys.ahk` から呼び出す形にする。
- 複数機能で使う処理（ウィンドウ操作、ログ出力、文字列処理等）は `lib/` に切り出す。`features/` 間の直接依存は禁止し、共通処理は `lib/` 経由にする。
- 設定値・マジックナンバーは `config/Settings.ahk` に集約し、コード中に直書きしない。
- 開発者向けツール（ビルド・配布スクリプト等）はアプリ本体の機能と混在させず、`dev-tools/` 配下に置く。`dev-tools/src/` にスクリプト本体、`dev-tools/docs/` に関連ドキュメントを置き、ドキュメント運用（`docs-workflow.md`）は `dev-tools/docs/` にも同様に適用する。
- `.claude/hooks/` 配下のスクリプトは現在すべてbash（`.sh`）。新規`.ps1`を作成する場合のみ
  **BOM付きUTF-8で保存する**こと（BOM無しだとWindows PowerShell 5.1でパースエラーになる。詳細:
  `.claude/rules/powershell-encoding.md`）。`.sh`はBOM無しUTF-8・LF改行で保存する
  （詳細: `.claude/rules/shell-script-style.md`）。複数hookスクリプトで使い回すロジックは
  `.claude/hooks/lib/` に切り出す。
- 開発補助スクリプト（`dev-tools/src/`, `.claude/hooks/`, `tests/`配下のシェルスクリプト等）は
  git bash経由で実行可能な範囲でbash（`.sh`）を使う。bash化できない場合のみPowerShell（`.ps1`）と
  する。bashスクリプトは`jq`（JSON操作）を前提とする。詳細な判断基準・規約は
  `dev-tools/docs/spec/shell-scripts.md`, `.claude/rules/shell-script-style.md` を参照。
