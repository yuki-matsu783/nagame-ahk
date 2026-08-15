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
| [] | 11 | planをもとに作業を進める、作業内容はworklogに更新する | エージェント |
| [] | 12 | commit, push してレビュー依頼を行う | エージェント |
| [] | 13 | 作業内容をもとにMR descriptionを更新する | `describe` |
| [] | 14 | MRでレビュー・コメントする | 人間 |
| [] | 15 | レビュー内容を取得し、実装・ドキュメントを修正する。対応が完了したコメントには対応内容を返信する（11〜15の作業ループを合意まで繰り返す） | `comments` / `reply` |
| [] | 16 | 設計反映: `plans/` `worklog/` の内容を `docs/spec/` `docs/ddr/` へ反映する | エージェント |
| [] | 17 | AIアセット改善: 作業中に気づいたルール・スキルの不備があれば `.claude/rules/` `.claude/skills/` `CLAUDE.md` `AGENTS.md` に反映する | エージェント |
| [] | 18 | commit, push してレビュー依頼を行う | エージェント |
| [] | 19 | MRでレビュー・コメントする | 人間 |
| [] | 20 | レビュー内容を取得し、設計反映・AIアセットの内容を修正する。対応が完了したコメントには対応内容を返信する（16〜20を合意まで繰り返す） | `comments` / `reply` |
| [] | 21 | `plans/` `worklog/` を削除し、`HANDOFF.md` を次タスクへリセットする | エージェント |
| [] | 22 | commit, push して Draftを解除する | エージェント |
| [] | 23 | マージする（squash merge。ブランチは削除してよい） | 人間 |

## やったこと

- issue #7（各markdownドキュメントにopen knowledge formatのyaml-frontmatterを追加する）の内容を確認。
  issue本文が空だったためヒアリングでスコープを確定。
- ブランチ `feature-7-markdown-open-knowledge-format-yaml-frontmatter` と Draft PR #23 を作成。
- Plan（`plans/immutable-painting-kitten.md`）・worklog
  （`worklog/20260816_immutable-painting-kitten.md`）を作成しコミット・push。
- PR #23 description を plan 内容で更新済み。

## 次にやること

- PR #23 でplanのレビューを受ける（flow-id 7）。レビューOKの合図後は
  `comments all` で未解決スレッドが無いことを確認してから実装（flow-id 11）へ進む。
- 実装内容: 対象39ファイルへのfrontmatter（title/type/description/tags。一部ファイルは
  キー構成が異なる）追加・マージ、および新規ルール `.claude/rules/markdown-frontmatter.md` の作成。
  詳細は `plans/immutable-painting-kitten.md` 参照。

## 判断を迷った内容

- issueにtype値の決め方が明記されていなかったため、ディレクトリ種別での自動判定ではなく
  「ファイルごとに人が指定（＝AIが提案しユーザーが確認）」を採用した。
- 既にGitHub issueテンプレート仕様の`title:`と衝突する`.github/ISSUE_TEMPLATE/task.md`は、
  `title`キーのみ除外する形にした（`plans/immutable-painting-kitten.md`の対象外表参照）。

## 未解決の内容

- 特になし（PR #23 のレビュー待ち）。

## 守るべき条件・触ってはいけない範囲

- `.gitlab/issue_templates/task.md` にはfrontmatterを追加しない（GitLab仕様上issue本文へ
  そのまま挿入されるため）。
- `.claude/agents/*.md` / `.claude/skills/*/SKILL.md` の既存`name`/`description`（実際に
  Claude Codeが読み込む値）、`.github/ISSUE_TEMPLATE/task.md` の既存`name`/`about`/`title`/
  `labels`/`assignees`の値は変更しない（新キーの追記のみ）。
