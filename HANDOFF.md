# HANDOFF

<!--
AI⇔AI/AI⇔人間の状況引継ぎメモ。常に「このブランチの現状」を表現する
-->

## フロー進捗状況

| 進捗 | flow-id | ステップ | 担当 |
|----|---|---|---|
| [x] | 1 | issueを起票する（`.github/ISSUE_TEMPLATE/task.md` / `.gitlab/issue_templates/task.md` で目的・現状・期待する動作・受け入れ条件を記載） | 人間 |
| [x] | 2 | issueの内容を取得する | `start <issue番号>` |
| [x] | 3 | featureブランチ（`feature-<issue番号>-<slug>`）とDraft MRを作成する（既にあれば `sync` のみ） | `start` |
| [x] | 4 | Planモードで実行手順を作成する（`plans/` へ出力・コミット。このタイミングで `worklog/日付_<plan名>.md` を作成） | エージェント |
| [x] | 5 | Planに合意する | 人間 |
| [x] | 6 | commit, push してレビュー依頼を行う | エージェント |
| [] | 7 | MRで再度planについてレビュー・コメントする | 人間 |
| [] | 8 | レビュー内容を取得し、planを修正する。対応が完了したコメントには対応内容を返信する（7〜8を合意まで繰り返す） | `comments` / `reply` |
| [x] | 9 | planをもとにMR descriptionを更新する | `describe` |
| [] | 10 | コンテキスト削減のためにセッションをcompactする | 人間 |
| [x][] | 11 | planをもとに作業を進める、作業内容はworklogに更新する | エージェント |
| [x][] | 12 | commit, push してレビュー依頼を行う | エージェント |
| [x][] | 13 | 作業内容をもとにMR descriptionを更新する | `describe` |
| [][] | 14 | MRでレビュー・コメントする | 人間 |
| [][] | 15 | レビュー内容を取得し、実装・ドキュメントを修正する。対応が完了したコメントには対応内容を返信する（11〜15の作業ループを合意まで繰り返す） | `comments` / `reply` |
| [x][] | 16 | 設計反映: `plans/` `worklog/` の内容を `docs/spec/` `docs/ddr/` へ反映する | エージェント |
| [x][] | 17 | AIアセット改善: 作業中に気づいたルール・スキルの不備があれば `.claude/rules/` `.claude/skills/` `CLAUDE.md` `AGENTS.md` に反映する | エージェント |
| [][] | 18 | commit, push してレビュー依頼を行う | エージェント |
| [][] | 19 | MRでレビュー・コメントする | 人間 |
| [][] | 20 | レビュー内容を取得し、設計反映・AIアセットの内容を修正する。対応が完了したコメントには対応内容を返信する（16〜20を合意まで繰り返す） | `comments` / `reply` |
| [] | 21 | `plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする | エージェント |
| [] | 22 | commit, push して Draftを解除する | エージェント |
| [] | 23 | マージする（squash merge。ブランチは削除してよい） | 人間 |

補足: 本ブランチはplanのみの個別レビュー往復（7〜10）を経ず、Plan承認（5）後に実装まで
一気に進めた（実機テストで都度検証しながら進めたため）。そのため6/9/11/12/13/16/17を
まとめて1回のpushで満たす形になっている。

## やったこと

issue #6（開発補助スクリプトのbash化）対応。リポジトリ内の全PowerShellスクリプト
（VCS抽象化層Provider/Github/Gitlab、build.ps1、Claude Code hook2種+共通lib、結合テストスクリプト）
をbash化し、`.ps1`ファイルを1件も残さず削除した。全スクリプトを実機で動作確認済み
（issue #6自体の取得・PR #18とのやり取り、実ビルド、実AutoHotkeyプロセスとのTCP通信含む）。
設計書`dev-tools/docs/spec/shell-scripts.md`とAIアセット`.claude/rules/shell-script-style.md`を
新規作成し、関連spec/rules/SKILL.mdを更新した。詳細は`worklog/20260816_shimmying-wibbling-simon.md`
参照。

## 次にやること

commit・push・`describe`でMR description更新済み。人間によるMRレビュー待ち
（レビューが来たら`comments`→修正→`reply`のループ、完了後は設計反映済みのため
plans/worklog削除・Draft解除へ進める）。

## 判断を迷った内容

- Hookのbash化をスコープに含めるかはユーザーに確認済み（含める、を選択）。
- `.claude/settings.json`のhook `command`はgit bash本体のフルパス
  （`C:\Program Files\Git\bin\bash.exe`）を直書きしている。単一開発者運用を前提にした判断で、
  別マシンでは書き換えが必要（`shell-scripts.md`の未決定事項に記載）。

## 未解決の内容

（特になし）

## 守るべき条件・触ってはいけない範囲

- `src/`（AHK本体）のロジックは変更していない。
- `Gitlab.sh`は実機未検証のままPowerShell版と同じ構造で移植した（GitLab remoteが無いため）。
