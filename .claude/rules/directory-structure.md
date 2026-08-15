---
alwaysApply: true
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
│   └── adr/                  # 意思決定ログ（追記のみ）
├── tests/                    # 手動/自動テスト用スクリプト
├── .claude/
│   ├── rules/                 # AI向け詳細ルール（このファイルもここにある）
│   └── skills/                 # /ahk-implement などのスキル定義
├── .gitignore
├── CLAUDE.md                    # プロジェクト概要・開発実行・.claude/rules/ へのポインタ
├── PLAN.md                      # 方針メモ（設計〜実装、中期。ごく簡単なタスクを除き使用）
├── TASK.md                      # チェックリスト（設計〜実装、短期。ごく簡単なタスクを除き使用）
├── HANDOFF.md                   # セッション間の伝言板（試行錯誤の記録として履歴に残す）
└── README.md
```

## 配置の指針

- `main.ahk` にロジックは書かない。`#Include` とアプリ初期化呼び出しのみとする。
- 機能を追加するときは `features/` に1ファイル追加し、必要なホットキーは `core/Hotkeys.ahk` から呼び出す形にする。
- 複数機能で使う処理（ウィンドウ操作、ログ出力、文字列処理等）は `lib/` に切り出す。`features/` 間の直接依存は禁止し、共通処理は `lib/` 経由にする。
- 設定値・マジックナンバーは `config/Settings.ahk` に集約し、コード中に直書きしない。
