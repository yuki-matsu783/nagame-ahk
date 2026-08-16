---
title: HANDOFF
type: handoff
description: セッション間・作業者間の引継ぎメモ（現在地・次回やること等）
tags: [handoff, workflow]
keywords: [issue-7, pr-23, フロー進捗, worklog, レビューコメント, フロントマター, 引き継ぎ]
---

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
| [x] | 7 | MRで再度planについてレビュー・コメントする | 人間 |
| [x] | 8 | レビュー内容を取得し、planを修正する。対応が完了したコメントには対応内容を返信する（7〜8を合意まで繰り返す） | `comments` / `reply` |
| [x] | 9 | planをもとにMR descriptionを更新する | `describe` |
| [] | 10 | コンテキスト削減のためにセッションをcompactする | 人間 |
| [x] | 11 | planをもとに作業を進める、作業内容はworklogに更新する | エージェント |
| [x] | 12 | commit, push してレビュー依頼を行う | エージェント |
| [x] | 13 | 作業内容をもとにMR descriptionを更新する | `describe` |
| [x][x][] | 14 | MRでレビュー・コメントする | 人間 |
| [x][x][] | 15 | レビュー内容を取得し、実装・ドキュメントを修正する。対応が完了したコメントには対応内容を返信する（11〜15の作業ループを合意まで繰り返す） | `comments` / `reply` |
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
- PR #23 レビュー1回目「TEMPLATEはやっぱりfrontmatter不要で良いや」（対象:
  `.github/ISSUE_TEMPLATE/task.md`）を受け、同ファイルを完全にfrontmatter対象外へ変更
  （対象ファイル数39→38）。planを修正しコミット・push、スレッドに返信。
  `comments all`で未解決スレッド0件（resolved）を確認済み。
- 対象38ファイルへ`title`/`type`/`description`/`tags`を追加・マージ実装。実装中に既存frontmatter
  （`alwaysApply`/`paths`）を持つルールファイルを追加発見し、既存キーを保持したままマージ。
- ユーザーからの追加指示で`resource`（該当ファイルのみ・今回は全ファイル省略）と`timestamp`
  （ISO 8601・タイムゾーン省略・全ファイル一律の値を`sed`で機械的に付与）をスキーマに追加。
- 新規ルール`.claude/rules/markdown-frontmatter.md`を作成（キー定義: `type`のみ必須、他は推奨）。
- plan・worklogを最終スキーマに合わせて更新し、commit・push（`d56811e`）、PR description更新済み。
- PR #23の実装レビュー（flow-id 14 round1）で3件のレビュースレッド（`timestamp`削除・`keywords`
  追加・説明列の記述改善）と2件の追加要望コメント（`index.md`作成・frontmatter抽出jsonlスクリプト
  作成）を受領。ユーザーに追加要望2件のスコープ・`keywords`バックフィル要否を確認の上、plan
  （`plans/purrfect-churning-oasis.md`）を作成・承認を得て対応（flow-id 15 round1）。
- `.claude/rules/markdown-frontmatter.md`のキー定義をOKF spec文言に沿って書き直し、`timestamp`を
  削除、`keywords`（複数形）を追加。対象39ファイル全てから`timestamp`実データを一括削除し、
  各ファイルへ`keywords`実データをバックフィル。
- `index.md`（Repository Map）、`dev-tools/src/extract-frontmatter.sh`（frontmatter抽出jsonl
  スクリプト）、`tests/test_extract_frontmatter.sh`（単体テスト）を新規作成。3件のレビュースレッドに
  対応内容を返信済み（worklog参照）。commit・push・PR description更新済み（`e273f4f`）。
- PR #23の再レビュー（flow-id 14 round2）で「説明列の改善」スレッドがresolvedになった一方、
  「keywords追加」スレッドに新規コメント（「日本語の単語もバランスよく含めてほしい」）、加えて
  新規スレッド2件（index.mdとdirectory-structure.mdの記載重複、extract-frontmatter.shでのyq利用
  可否）を受領。plan（`plans/ember-quilted-narwhal.md`）を作成・承認を得て対応（flow-id 15 round2）。
- 対象39ファイル全ての`keywords`を、既存の英語技術用語と本文中の日本語の単語を概ね半々で混在させる
  形に書き直し、`.claude/rules/markdown-frontmatter.md`のkeywords説明にも追記。
- `index.md`＝各ディレクトリの役割説明（正）、`.claude/rules/directory-structure.md`＝ツリー構造・
  配置ルール・個別ファイルの役割説明（正）と責務を分離し、ツリーからディレクトリ単位の役割コメントを
  削除、相互に参照する一文を追記。
- `dev-tools/src/extract-frontmatter.sh`を、`yq`がPATH上にあれば優先利用し、無ければ自前の軽量
  パーサーへフォールバックする構成に変更（新規の必須外部依存にはしない）。3件のスレッドに対応内容を
  返信済み（worklog参照）。commit・push・PR description更新済み（`5072ce3`）。
- ユーザーから「各ディレクトリのjsonl出力を実施し、gitignoreにせず管理してほしい」との指示を受け、
  対象ディレクトリの粒度をAskUserQuestionで確認（「index.mdの主要ディレクトリごと」を選択）。
  plan（`plans/gilded-tundra-sparrow.md`）を作成・承認を得て対応。
- `.gitignore`から`index.jsonl`の除外ルールを削除し、markdownファイルを含む8ディレクトリ
  （`docs/`, `dev-tools/`, `tests/`, `.claude/`, `plans/`, `worklog/`, `.github/ISSUE_TEMPLATE/`,
  `.gitlab/issue_templates/`）で`extract-frontmatter.sh`を実行、生成された`index.jsonl`をgit管理下に
  置いた（`src/`, `assets/icons/`, `.gemini/`, `build/`はmarkdownが無いため対象外）。
  commit・push済み（`82823cd`, CR除去修正`7de9063`）。
- レビューで「イメージが違った」との指摘（出力は指定ディレクトリ1箇所への集約ではなく、markdownが
  存在する各ディレクトリごとに分散させ、concept_idは常にリポジトリルート基準の相対パスにすべき）を
  受領。plan（`plans/velvet-copper-lynx.md`）を作成・承認を得て`extract-frontmatter.sh`を再設計。
- `resolve_repo_root`関数を新設（`git rev-parse --show-toplevel`のWindowsドライブレター表記と
  `realpath`のMSYS表記が一致しない問題を、`cd`経由で吸収）。`main()`を、markdownが直下に存在する
  ディレクトリ毎にそのディレクトリ自身へ`index.jsonl`を出力し、concept_id/directoryは常に
  リポジトリルート基準の相対パスにする設計へ変更。誤った旧仕様の8ファイルを削除し、
  リポジトリルートで1回実行して16ファイルへ再生成。`tests/test_extract_frontmatter.sh`も
  `resolve_repo_root`・repo_root基準のconcept_id導出テストへ更新（15アサーション成功）。

## 次にやること

- commit・push・PR description更新（`describe`）を行い、人間の再レビューを受ける（flow-id 14
  round3）。`comments all`で返信済みスレッドが実際にresolvedになっているか、新規指摘が無いかを
  確認してから設計反映（flow-id 16）へ進む。
- 設計反映: `plans/purrfect-churning-oasis.md`（round2、`plans/immutable-painting-kitten.md`同様
  上書きしない） / `plans/ember-quilted-narwhal.md`（round3） / `plans/gilded-tundra-sparrow.md`
  （index.jsonl管理化） / `plans/velvet-copper-lynx.md`（出力仕様の再設計） / 対応するworklog4件の
  内容を`dev-tools/docs/spec/`（`extract-frontmatter.sh`の正史仕様。ディレクトリ分散出力・
  repo root基準concept_id・生成物`index.jsonl`を手動管理する運用や再生成のタイミングを記載する）・
  `.claude/rules/markdown-frontmatter.md`・`.claude/rules/directory-structure.md`（既に反映済み）
  へ反映する。

## 判断を迷った内容

- issueにtype値の決め方が明記されていなかったため、ディレクトリ種別での自動判定ではなく
  「ファイルごとに人が指定（＝AIが提案しユーザーが確認）」を採用した。
- 当初`.github/ISSUE_TEMPLATE/task.md`は`title`キーのみ除外する案だったが、レビューで
  「issueテンプレートにはOKF frontmatter自体が不要」と判断され、完全に対象外へ変更した。
- `resource`キーは対応する外部リソースが無い場合は空文字列ではなくキー自体を省略する方針にした
  （今回の対象38ファイルは全て省略）。
- `keyword`フィールドはレビューコメントでは単数形表記だったが、既存の`tags`との命名規則統一を
  優先し複数形`keywords`を採用した（ユーザー承認済み。詳細は`plans/purrfect-churning-oasis.md`参照）。
- frontmatter抽出スクリプトのYAML→JSON変換は、当初`yq`等の外部ツールを新規導入せず自前パーサーのみで
  実装したが、レビューで「yqがあれば優先利用すべきでは」との指摘を受け、`yq`がPATH上にあれば優先的に
  使い、無ければ自前パーサーへフォールバックする方式に変更した（yq自体を新規の必須外部依存には
  していない）。
- Planモードの再突入時、ハーネスが追跡する「今回のplanファイル」が前回（round2）のパス
  （`plans/purrfect-churning-oasis.md`）に固定される仕様のため、`ExitPlanMode`がround3の内容を
  正しく読めるよう一時的に同ファイルへround3の内容を書き込み、承認後に`git checkout`でround2時点の
  コミット済み内容へ復元し、round3の正式なplanは新規ファイル（`plans/ember-quilted-narwhal.md`）に
  分離した。`.claude/rules/plan-mode-safety.md`「計画ごとに新しいplanファイル名を使う」の趣旨を、
  ハーネス側の1re-entry=1ファイル固定という制約の中でも満たすための対応。

## 未解決の内容

- レビュースレッド`PRRT_kwDOT4Y-5s6Zi1VH`（timestamp削除）への返信作業中、誤って動作確認用の
  ダミー返信「test」を同スレッドに投稿してしまった。訂正の返信を追加投稿済みだが、GitHub上の
  スレッドには誤投稿がそのまま履歴として残っている（削除手段が無いため）。実害は無いが、
  次回レビュー時に念のためユーザーへ一言断っておく。

## 守るべき条件・触ってはいけない範囲

- `.gitlab/issue_templates/task.md`、`.github/ISSUE_TEMPLATE/task.md` にはfrontmatterを
  追加しない（前者はGitLab仕様上issue本文へそのまま挿入されるため、後者はレビューでの方針変更）。
- `.claude/agents/*.md` / `.claude/skills/*/SKILL.md` の既存`name`/`description`、
  `.claude/rules/directory-structure.md`等の既存`alwaysApply`、`.claude/rules/ahk-style.md`の
  既存`paths`（いずれも実際にツール/設定が読み込む値）は変更しない（新キーの追記のみ）。
