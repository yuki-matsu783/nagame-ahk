# 操作状態表示（ActivityStatus）

## 背景・目的

マウス・キーボードを実際に操作しているか（アクティブ）、一定時間操作していないか（非アクティブ）を、
カーソル付近のツールチップでリアルタイムに確認できるようにする。

## 仕様

- 判定方法: `A_TimeIdlePhysical`（直近の物理入力からの経過時間）を使用する。`Send` 等による合成入力には反応しない。
- 非アクティブ判定閾値: `Settings.IdleThresholdMs`（既定 3000ms）以上、物理入力が無ければ「非アクティブ」。
- 表示更新間隔: `Settings.ActivityCheckIntervalMs`（既定 200ms）。
- 表示位置: マウスカーソル位置 + (16px, 16px) オフセット。
- 表示文言: 「アクティブ」/「非アクティブ」。
- 状態が変化した時のみ `Logger.Info` でログを残す（変化が無い間はログを出さずタイマーだけ回す）。

## 操作方法

- アプリ起動時に自動的に表示を開始する（`App.Start()` から `ActivityStatus.Start()` を呼び出し）。
- `Ctrl+Alt+A` ホットキーで表示のON/OFFを切り替え可能（`core/Hotkeys.ahk`）。
- トレイメニュー「操作状態表示」からも同様にON/OFF可能。チェック状態は `ActivityStatus.Enabled` と同期する（`TrayMenu.SyncActivityStatusCheck`）。

## 影響範囲

- 追加: `src/features/ActivityStatus.ahk`
- 変更: `src/config/Settings.ahk`（`IdleThresholdMs`, `ActivityCheckIntervalMs` 追加）
- 変更: `src/core/Hotkeys.ahk`（`Ctrl+Alt+A` 追加）
- 変更: `src/core/TrayMenu.ahk`（メニュー項目・チェック同期メソッド追加）
- 変更: `src/core/App.ahk`（起動時に `ActivityStatus.Start()` 呼び出し）
- 変更: `src/main.ahk`（`#Include features\ActivityStatus.ahk` 追加）

## 設定項目

| 設定値 | 既定値 | 説明 |
|---|---|---|
| `Settings.IdleThresholdMs` | `3000` | 非アクティブと判定するまでの無操作時間(ms) |
| `Settings.ActivityCheckIntervalMs` | `200` | 状態判定・ツールチップ更新の間隔(ms) |

## 未決定事項・懸念点

- ツールチップがマウスカーソルのすぐ近くに出るため、クリック操作の邪魔になる可能性がある（オフセット量は今後調整の余地あり）。
- マルチモニタ環境での表示位置の検証は未実施。
