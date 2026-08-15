# worklog: issue #12 adr→ddr改称

plan: `plans/smooth-pondering-wozniak.md`

## 経緯

- issue #12より着手。`start`サブコマンドで`feature-12-adr-ddr-design-decision-record`ブランチ・
  Draft PR #13を作成（新規ブランチのため main との差分が無く `gh pr create` が失敗 →
  過去issue #5と同じ「空コミット」で回避）。
- スコープ調査（`rg -i adr`）で影響ファイルを洗い出し、以下2点をユーザーに確認して方針決定:
  - 既存マージ済みADRレコード本文中の「ADR」表記も書き換える（追記のみ・変更不可ルールは決定内容の
    改変を禁じる趣旨であり、用語統一には適用しないという解釈）。
  - 改称の決定自体を新規DDRレコード（`docs/ddr/0001-...`）として記録する。
- Plan提示時、ユーザーから「壊れたリンク（`docs/adr/0001-ahk2exeビルドの環境依存対応.md`。実体は
  `dev-tools/docs/adr/`側にのみ存在）は今回まとめて直してほしい」と指摘を受け、当初「対象外」
  としていた項目をplanに追加して修正した。

## 実装ログ

- `git mv docs/adr docs/ddr`、`git mv dev-tools/docs/adr dev-tools/docs/ddr` でディレクトリ移動。
- planに列挙した各ファイルの `adr`/`ADR` 表記を `ddr`/`DDR` に置換。
- `docs/README.md` / `dev-tools/docs/README.md` の `## ddr` 節に「DDRはADRの考え方を拡張し
  architectureに限らない意思決定も対象とする」旨の一文を追加。
- `docs/ddr/0001-意思決定ログをADRからDDRへ改称.md` を新規作成し、改称の背景・決定・却下した案を記録。
  `docs/README.md` の一覧に追加。
- 壊れたリンク（`docs/adr/0001-ahk2exeビルドの環境依存対応.md`。実体は`dev-tools/docs/adr/`側にのみ
  存在）を修正:
  - `docs/README.md`: 実体の無いこのエントリを一覧から削除（新規0001との番号衝突回避）。
  - `DEVELOPERS.md` / `dev-tools/docs/spec/distribution.md`: リンク先を
    `dev-tools/docs/ddr/0001-...` に訂正。
- `rg -i adr` で全体を再確認。残存する `adr` は以下のみで、いずれも意図した残存
  （変更不要と判断）:
  - `Add-MrThreadReply`/`ReplyBody` 系の偶然の部分一致（`Provider.ps1`, `Github.ps1`, `Gitlab.ps1`,
    `dev-tools/docs/spec/issue-mr-workflow.md`, `dev-tools/docs/ddr/0003`）。
  - `RecentDocsWatcher.ahk` の `_ReadRecentFileNames` の偶然の部分一致。
  - `plans/smooth-pondering-wozniak.md`（計画時点のスナップショットとして不変。docs-workflow.mdの
    運用方針通り編集しない）。
  - `HANDOFF.md`（issueタイトルの引用、ブランチ名 `feature-12-adr-ddr-design-decision-record` の
    参照。ブランチ名自体は改称対象外）。
  - `docs/ddr/0001` 本文・`docs/README.md`・`dev-tools/docs/README.md` 内の「ADR」は、DDRとの
    対比説明として意図的に残した表記。
  - `dev-tools/docs/ddr/0004` の「本DDR（旧ADR）」は、当時の呼称を残しつつ現在の呼称も併記した
    意図的な表記。
- `.mrworkflow.json` のJSON構文を検証（`json.load`相当で valid を確認）。
