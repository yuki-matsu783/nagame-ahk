# worklog: pr4-review-followup2

対応するplan: `plans/pr4-review-followup2.md`

## 経緯

`3-開発フローを変える`（issue #3, PR #4）で、人間から「レビューした」との合図を受けた。
`.claude/skills/issue-mr-flow/SKILL.md` の「レビュー完了合図の確認」節に従い `comments all`
（`Get-MrUnresolvedComments -IncludeResolved`）で再確認したところ、前回返信済みの1件とは別に、
新たに未解決コメントが2件見つかった。

## 指摘1: 全体フロー表の担当混在（`PRRT_kwDOT4Y-5s6ZfGIk`）

`SKILL.md:43`（全体フロー旧行14）で「MRでレビュー・コメントする（人間）」と「対応完了コメントに
返信する（`reply`、AI）」が1行に混在していた。行8・9では既に人間/AIで分離済みのパターンがあり、
旧行14だけ揃っていなかった。

対応: 旧行14を新14（人間）・新15（`comments`/`reply`）に分割し、旧15〜20を新16〜21へ繰り下げた。
本文中の番号参照（`comments`/`reply`見出し、`resume`内のステップ数、レビュー完了合図確認の見出し）も
すべて更新した。

## 指摘2: AI返信のアイデンティティ（`PRRT_kwDOT4Y-5s6ZfGaK`）

AIが`reply`サブコマンドで返信すると、GitHub上は投稿者アカウントが元コメントの投稿者（`gh` CLIの
認証ユーザー＝人間自身）と同一に見えてしまう。AIが返信したとわかるように表示できないか、という指摘。

### 検討した選択肢

1. **返信本文への署名（採用）**: `reply`サブコマンドの手順で、返信本文の先頭に
   `Claude Codeより:` を必ず付ける運用ルールを追加する。
   - 長所: 追加の認証情報・インフラ不要。`SKILL.md`の手順変更のみで即座に対応できる。
   - 短所: GitHub UI上のアカウント表示自体は変わらない（本文を読まないと分からない）。
2. **botアカウントによる投稿者分離**: 専用のGitHub bot/machineアカウントを作成し、そのPATを
   `Add-MrThreadReply`（`Github.ps1`/`Gitlab.ps1`）で使うよう認証を切り替える。
   - 長所: GitHub UI上で本当に別アカウントとして表示される（根本解決）。
   - 短所: bot アカウントの作成・PAT管理（保管場所・ローテーション）・
     `Provider.ps1`/`Github.ps1`/`Gitlab.ps1`の認証切り替え実装が必要になり、
     本PR（issue #3）の規模を大きく超える。GitHub/GitLab双方の対応も要る。
3. **見送り・未決定事項として記録**: 今回は対応せず、specの「未決定事項」に追記するのみ。
   - 長所: 実装コストゼロ。
   - 短所: レビュアーの指摘に対して具体的な改善が示せない。

ユーザー（プロジェクトオーナー）に選択肢を提示して確認した結果、**選択肢1（返信本文への署名）を
採用**した。選択肢2は将来的に必要になれば別issueとして起票する。

### 既存決定事項との整合性

`dev-tools/docs/spec/issue-mr-workflow.md` の「決定済み事項」には既に
「`Add-MrThreadReply` の `-ReplyBody` は呼び出し側が組み立てた自由文をそのまま渡す。関数側で
定型の接頭辞等は付けない」という決定がある。今回の署名方式はこの決定と矛盾しない
（関数自体は変更せず、`SKILL.md`の`reply`手順＝呼び出し側の運用ルールとして署名を含める）。

## 対応

- `.claude/skills/issue-mr-flow/SKILL.md`: 全体フロー表の分割・番号振り直し、`reply`手順への
  署名ルール追加。
- `dev-tools/docs/spec/issue-mr-workflow.md`: 「20ステップ」→「21ステップ」の事実訂正のみ
  （決定事項・ADRへの反映は設計反映タイミングに委ねる。次回セッションでの対応候補）。
- `HANDOFF.md`: 現在地・次回やることを更新。
- 両スレッドへの返信（署名運用を実際に使う最初のケース）は次のステップで実施。

## 次回セッションへの申し送り

- `PRRT_kwDOT4Y-5s6ZfGIk` / `PRRT_kwDOT4Y-5s6ZfGaK` への返信がまだ済んでいない場合は、
  `/issue-mr-flow reply` で対応する。
- 設計反映（全体フロー16）のタイミングで、本worklogの「検討した選択肢」を
  `dev-tools/docs/spec/issue-mr-workflow.md` の決定済み事項に、必要なら新規ADR
  （0004番）として反映する。
