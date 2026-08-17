---
alwaysApply: true
title: ディレクトリ構成
type: rule
description: リポジトリのディレクトリ構成と配置方針を定めたルール
tags: [directory-structure, rule]
keywords: [ディレクトリ構成, src, features, lib, dev-tools, 配置方針, plans, worklog, 設定値集約, always-apply]
---

# ディレクトリ構成

各ディレクトリの役割説明は [index.md](../../index.md)（Repository Map）を正とする。本ファイルは
ツリー構造・配置ルールと、個別ファイル（後述のツリー内でコメント付きのもの）の役割を扱う
（ディレクトリの役割説明を重複記載しない）。

```
nagame-ahk/
├── src/
│   ├── main.ahk             # エントリーポイント。#Include の集約と起動呼び出しのみを行う
│   ├── config/
│   │   └── Settings.ahk     # 定数・ユーザー設定値
│   ├── core/
│   │   ├── App.ahk          # 起動処理などアプリのライフサイクル管理
│   │   ├── Hotkeys.ahk      # ホットキー登録の集約（実処理は features/ に委譲）
│   │   └── TrayMenu.ahk     # トレイアイコン・右クリックメニュー
│   ├── features/
│   └── lib/
├── assets/
│   └── icons/
├── docs/
│   ├── README.md             # docs配下の目次
│   ├── spec/
│   └── ddr/
├── dev-tools/                 # 人間専用の開発補助ツール（exe配布ビルド関連のみ）
│   ├── src/
│   └── docs/
│       ├── README.md         # dev-tools配下の目次
│       ├── spec/
│       └── ddr/
├── build/
├── tests/
├── usage/                    # 対応工数レポート機能のローカル作業状態（.gitignore対象、コミットしない）
│   ├── session-logs/          #   push検知のたびにコピーするtranscriptのローカルスナップショット
│   └── state/                 #   ブランチ別の累計状態・セッション横断カーソル（session-cursors/）
├── .claude/
│   ├── rules/
│   ├── skills/
│   ├── scripts/               # AIエージェント専用スクリプト一式（issue #24）
│   │   ├── src/
│   │   │   └── vcs/
│   │   └── docs/
│   │       ├── README.md     # .claude/scripts配下の目次
│   │       ├── spec/
│   │       └── ddr/
│   └── hooks/
│       └── lib/
├── plans/
├── worklog/
├── .gitignore
├── CLAUDE.md                 # プロジェクト概要・開発実行・.claude/rules/ へのポインタ
├── HANDOFF.md                # セッション間・作業者間の軽量な引継ぎメモ（ブランチの現在地・次回やること等。詳細な試行錯誤はworklog/へ）
└── README.md
```

## 配置の指針

- `main.ahk` にロジックは書かない。`#Include` とアプリ初期化呼び出しのみとする。
- 機能を追加するときは `features/` に1ファイル追加し、必要なホットキーは `core/Hotkeys.ahk` から呼び出す形にする。
- 複数機能で使う処理（ウィンドウ操作、ログ出力、文字列処理等）は `lib/` に切り出す。`features/` 間の直接依存は禁止し、共通処理は `lib/` 経由にする。
- 設定値・マジックナンバーは `config/Settings.ahk` に集約し、コード中に直書きしない。
- 開発補助ツール一式はアプリ本体の機能と混在させず、**利用者（誰が実行するか）で置き場所を分ける**
  （issue #24）。
  - **人間のみが手動実行するツール**（ビルド・配布スクリプト等）は `dev-tools/` 配下に置く。
    `dev-tools/src/` にスクリプト本体、`dev-tools/docs/` に関連ドキュメントを置く。
  - **AIエージェントが`.claude/skills/*`経由で能動的に実行するスクリプト**は `.claude/scripts/`
    配下に置く。`.claude/scripts/src/` にスクリプト本体、`.claude/scripts/docs/` に関連
    ドキュメント（`spec/`・`ddr/`）を置く。Claude Codeのplugin配布は`.claude/`配下一式を
    パッケージ化する想定のため、AIが実行時に必要とするスクリプト・設計書は`.claude/`の外に
    置かない。
  - ドキュメント運用（`docs-workflow.md`）は `dev-tools/docs/`・`.claude/scripts/docs/` の
    いずれにも同様に適用する。
  - 人間が手動実行するがAI可読データを生成するなど、両方の性質を併せ持つスクリプトは、
    実行主体（人間が能動的に実行するか、AIがskill経由で実行するか）を基準に判断する
    （実行主体を変えずに置き場所だけ`.claude/scripts/`へ寄せることも許容する。実例:
    `extract-frontmatter.sh`は人間が手動実行する運用のまま`.claude/scripts/src/`に置いている）。
- `.claude/hooks/` 配下のスクリプトは現在すべてbash（`.sh`）。新規`.ps1`を作成する場合のみ
  **BOM付きUTF-8で保存する**こと（BOM無しだとWindows PowerShell 5.1でパースエラーになる。詳細:
  `.claude/rules/powershell-encoding.md`）。`.sh`はBOM無しUTF-8・LF改行で保存する
  （詳細: `.claude/rules/shell-script-style.md`）。複数hookスクリプトで使い回すロジックは
  `.claude/hooks/lib/` に切り出す。
- 開発補助スクリプト（`dev-tools/src/`, `.claude/scripts/src/`, `.claude/hooks/`, `tests/`配下の
  シェルスクリプト等）は git bash経由で実行可能な範囲でbash（`.sh`）を使う。bash化できない場合のみ
  PowerShell（`.ps1`）とする。bashスクリプトは`jq`（JSON操作）を前提とする。詳細な判断基準・規約は
  `.claude/scripts/docs/spec/shell-scripts.md`, `.claude/rules/shell-script-style.md` を参照。
- `参考ディレクトリ/`（リポジトリ直下、`.gitignore`対象）: 設計・実装の参考にするため作業者が
  ローカルへcloneした外部OSS等を置く場所（issue #28対応時に導入）。リポジトリ本体には含めない
  ため、上記ツリーには登場しない。存在する場合、中身の調査は問題ないが、その配下のファイルを
  コミット対象に含めたり、そのリポジトリ自体の構成をnagame-ahk側へ流用したりしないこと
  （あくまで参照専用）。
