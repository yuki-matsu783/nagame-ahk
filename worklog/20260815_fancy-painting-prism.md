# worklog: fancy-painting-prism

対象: README.md / DEVELOPERS.md の書き分け（2026-08-15）。
plan: `plans/fancy-painting-prism.md`

## 試したこと

- 現ソースコード（`src/core/App.ahk` / `TrayMenu.ahk` / `Hotkeys.ahk` / `config/Settings.ahk`）と
  各 `docs/spec/*.md` の「操作方法」節を確認し、README.mdをexeユーザー向け（配布exeの入手方法・
  トレイメニュー・ホットキー・常駐3機能・外部コマンド受付の紹介・ログ・終了方法）に全面書き直しした。
- DEVELOPERS.mdは既存の「exeのビルド」「リリース時の手順」「未整備・今後整理する点」節をそのまま残し、
  冒頭に開発の始め方（動作環境・ソース実行方法・ディレクトリ構成へのリンク・機能一覧
  （`docs/spec/*.md` 6件）・実装フロー・テスト）を追加した。
- plans/fancy-painting-prism.md にplanを出力し承認を得てから実施。相対パスのリンク切れが無いことを
  `test -f` で確認済み。

## うまくいったこと

- 既存の詳細ドキュメント（`.claude/rules/*.md`, `docs/spec/*.md`, `tests/README.md`,
  `dev-tools/docs/*.md`）の内容を書き写さずリンクでまとめる方針で、重複無く整理できた。

## ダメだったこと

- 特になし。

## 次の一歩

- 特になし（ドキュメント整理のみで完了）。

---

（注: このworklogは開発フロー整理タスク（`docs/dev-workflow-rules`ブランチ）にあわせて、旧
`HANDOFF.md`の内容をそのまま移設したもの。README/DEVELOPERS分割タスク自体は当時mainへ直接
コミットする運用だったため、本来のreflect→削除のタイミングを経ていない。）
