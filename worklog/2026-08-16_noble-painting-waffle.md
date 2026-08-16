---
title: worklog issue #28 対応工数レポート修正
type: log
description: issue #28（対応工数レポートの日本語修正・経過時間記録追加）の作業ログ
tags: [usage-report, issue-28, worklog]
keywords: [対応工数, 経過時間, transcript, timestamp, usage-tracking, mystery-diff]
---

# worklog: 2026-08-16_noble-painting-waffle

## 経緯・気づいたこと

- `feature-28-issue` ブランチを `origin/main`（6ba2730）から作成し、Draft PR #29 を作成した直後、
  作業ツリーに**自分では作成していない未コミット差分**が7ファイル存在しているのを発見した。
  - `git show HEAD:.gitignore` と作業ツリーの内容を比較し、コミット履歴のどの時点にも存在しない
    内容であることを確認済み（フック（session-start.sh / post-push-usage-report.sh）の処理内容を
    確認したが、いずれもこの種のドキュメント文言を書き換えるロジックは持たない）。
  - 内容はissue #28の要求（「セッション使用量レポート」→「対応工数レポート」への文言統一）と
    完全に一致していた。
  - ユーザーに確認したところ、「このまま活かして作業を進める」との回答を得た。
  - さらに、この差分には**マージ済みDDR（`docs/ddr/0006-...md`）自体のタイトル/本文の書き換え**も
    含まれていたため、`docs-workflow.md`の「DDRは一度マージしたら追記のみ（変更不可）」との整合性を
    別途確認したところ、「この種の書き換えは過去に承認済みの対応」との回答を得たため、そのまま
    活かす方針で確定した。
- なお `HANDOFF.md`（`origin/main`にマージ済みの内容）に、issue #26セッション由来の別の「未解決の
  内容」記載（`.claude/rules/markdown-frontmatter.md`・`worklog/TEMPLATE.md`の出所不明差分）が
  残っていたが、該当2ファイルは現在の作業ツリーで無変更（`git diff`差分なし）であることを確認した。
  issue #28とは無関係かつ現状再現しないため、本ブランチのHANDOFF更新時にこの記載は解消済みとして
  整理した。

## Plan

`plans/noble-painting-waffle.md` 参照。要点: 既存の文言統一差分（出所不明・活用確定）に加えて、
`.claude/hooks/lib/UsageTracking.sh` に経過時間（`elapsedSeconds`）の集計ロジックを追加し、
`post-push-usage-report.sh` のレポートに「対応工数（目安）」として表示する。ドキュメント
（`dev-tools/docs/spec/issue-mr-workflow.md`）とテスト（`tests/test_usage_tracking.sh`新設）も
合わせて対応する。

## 参考実装調査（flow-id 11着手時）

- ユーザーが用意した参考実装2件（`参考ディレクトリ/claude-work-timer`（TypeScript）、
  `参考ディレクトリ/claude-code-time-tracking`（Python）。いずれもClaude Codeのtranscriptから
  実働時間を算出する同種のOSS）を調査した。
- 両実装とも「gapベースのidle検出（既定5分閾値）」を採用しており、レビュー反映済みのPlan設計
  （`IDLE_GAP_THRESHOLD_SECONDS`）の妥当性を裏付ける先行事例として参照した。
- `claude-work-timer`（`src/core/idle-detector.ts`）は、各作業区間（セグメント）の末尾に固定の
  **tail buffer**（既定30秒）を加算する設計を持っており、本Planに無かった要素だったため取り込んだ。
  1イベントのみのセッションでも `activeSeconds` が0にならず、tail buffer分が計上されるようになる
  （旧設計の意図しない挙動を修正）。
  - 境界値の扱い（gapがちょうど閾値の場合は「待ち」側とする）も `claude-work-timer` の
    `idle-detector.test.ts`（`handles exact threshold as idle`）に合わせた。
  - 手計算で複数パターン（1件のみ／2件・閾値内／3件・閾値超1回）を検証し、`claude-work-timer`の
    セグメント定義と一致する結果になることを確認した。加えて、「累計seconds値を毎回re-scanして
    差分を取る」既存の状態マージパターンに対して、tail bufferの暫定加算（走査完了時点でまだ
    閉じていない末尾セグメントに対する加算）が単調非減少性を壊さないことも手計算で確認した
    （次回pushで実gapに置き換わっても差分は必ず0以上になる）。
- `claude-work-timer`のoverlap dedup（複数セッション同時進行時の区間重複除去）は、本issueのスコープ
  （単一ブランチ・単一セッション）では不要と判断し見送った。「対象外」に明記済み。
- `plans/noble-painting-waffle.md` の「1.」節・「対象外」節・「4.」節を上記を反映して更新した。

## 実装中に判明した問題: `fromdateiso8601`が開発機のjqで動かない

- tail buffer込みの設計を`_usage_aggregate_transcript`へ実装し、手計算した期待値と突き合わせる
  ミニテスト（`jq -nc`で合成JSONLを作り関数を直接呼ぶ）を実行したところ、全ケースで
  `activeSeconds`が常に0または`null`になる不具合を発見した。
- 切り分けの結果、`fromdateiso8601`自体が開発機のjq（`C:\Program Files\jq\jq.exe`、jq 1.6、
  Windowsネイティブ版）で`jq: error (at <unknown>): strptime/1 not implemented on this platform`
  として失敗することが原因と判明した（`gmtime`/`strftime`は動くが、`mktime`/`fromdateiso8601`/
  `strptime`は軒並み未実装）。
- さらに厄介だったのは、この失敗が既存の`(try fromjson catch empty)`（不正なJSON行を無視するための
  ガード。パイプラインの前段にある）と組み合わさると、jqが**エラーメッセージを一切出さず終了コード0で
  出力全体が`null`になる**という現象だったこと。`try/catch`を含まない・`select`を含まない最小再現
  ケースでは通常どおり`strptime/1 not implemented...`のエラーが出て終了コード5になることを確認して
  おり、`try/catch`と`select`の組み合わせが後段の無関係なエラーの伝播を壊す、というjq側の未調査の
  癖であることを手動の二分探索で特定した。
- 対応として、`strptime`/`mktime`に依存しない自前のISO8601→epoch秒変換
  （`days_from_civil`アルゴリズムによる四則演算のみの実装）を`_usage_aggregate_transcript`内に
  追加した。`date -u -d <iso8601> +%s`（git bash付属のGNU coreutils date、これは正常に動作する）の
  結果と複数の日付（うるう年境界含む）で一致することを手動確認した。実際のtranscriptタイムスタンプ
  形式（`2026-08-16T02:37:32.461Z`のようにミリ秒付き）でも、固定位置の先頭19文字だけを読む実装のため
  問題なく動作することを実データで確認した。
- `.claude/rules/shell-script-style.md`「JSON操作」節に、今後jqで日付文字列→エポック秒変換が
  必要になった場合のための一般的な注意事項として追記した（issue #28以外の将来のスクリプトにも
  関わる普遍的な制約のため）。

## flow-id 11 実装完了

- `.claude/hooks/lib/UsageTracking.sh`: `IDLE_GAP_THRESHOLD_SECONDS`/`TAIL_BUFFER_SECONDS`定数、
  gapベース＋tail bufferの`activeSeconds`集計ロジック、自前実装`epoch_from_iso8601`
  （`days_from_civil`アルゴリズム）を追加。`_usage_merge_state`に`activeSeconds`の累計差分計算を追加。
- `.claude/hooks/post-push-usage-report.sh`: `fmt_duration`、「対応工数（目安・入力待ち時間を除く）」
  行、`sinceLastPush`リセット形への`activeSeconds: 0`追加。
- `tests/test_usage_tracking.sh`（新設）: 12アサーション、全て合格（`passed=12 failures=0`）。
  既存の`tests/test_vcs_provider.sh`も回帰確認済み（`passed=10 failures=0`）。
- `dev-tools/docs/spec/issue-mr-workflow.md`: 「対応工数レポート」節に稼働時間の算出方法・
  jqのstrptime制約を追記、「未決定事項・懸念点」に既知の誤差要因・overlap dedup未対応を追記、
  「影響範囲」にissue #28分の新規・変更ファイルを追記。
- `tests/README.md`: `test_usage_tracking.sh`の行を追加。
- `.claude/rules/shell-script-style.md`: Windowsネイティブjqの`strptime`/`mktime`未実装という
  一般的な注意事項を「JSON操作」節に追記（issue #28以外の将来のスクリプトにも関わるため）。
- `.gitignore`: 参考実装調査用にローカルへcloneした`参考ディレクトリ/`を除外対象に追加
  （リポジトリ本体には含めない）。
- 全ての変更した`.sh`は`bash -n`で構文チェック済み。

## 次にやること

- コミット・push（flow-id 12）→ `describe`でMR descriptionを更新（flow-id 13）→
  人間レビュー待ち（flow-id 14）に進む。

## レビュー往復（flow-id 14〜15, 1回目）

- ユーザーから「レビューOK」の合図を受けたが、`get_mr_unresolved_comments 29 true`で確認したところ
  未解決スレッドが1件残っていた（`.claude/hooks/post-push-usage-report.sh:131`,
  yuki-matsu783）: 「下記の問題があることをドキュメントなども併せて反映する
  https://gille.ai/en/blog/claude-code-jsonl-logs-undercount-tokens/」
- ルール通り、この合図だけでは次へ進まず内容を確認して対応した。記事の要旨:
  transcript JSONLはストリーミング応答開始時点で`usage.input_tokens`等にプレースホルダー値
  （0または1）を書き込み、応答完了後も更新されないケースがあり、input側で最大100〜174倍、
  output側で最大10〜17倍の過小カウントが観測される。
- 対応: 3箇所に反映した。
  - `dev-tools/docs/spec/issue-mr-workflow.md`: 「対応工数レポート」節の記録範囲・
    「未決定事項・懸念点」に機序・引用元URLを追記。稼働時間（`activeSeconds`）はこの問題の
    影響を受けないことも明記。
  - `dev-tools/docs/ddr/0006-対応工数レポートはtranscript自前パースで実装する.md`:
    マージ済みDDRのため既存内容は変更せず「追記」セクションを追加。
  - `.claude/hooks/post-push-usage-report.sh`: 自動投稿コメントのフッターに過小カウント要因と
    参照URLを追記（実際に次回push時のレポートへ反映されることを確認済み）。
- 署名付きでスレッドへ返信済み（`add_mr_thread_reply`）。ただしスレッドの解決（resolved）は
  レビュアー側の操作のため、返信後も`get_mr_unresolved_comments`では`unresolved`のまま
  表示される（DDR 0003の既定動作どおり）。ユーザーへ再確認を依頼する。

## レビュー往復（flow-id 14〜15, 2回目）

- ユーザーが上記スレッドを解決し、新たなレビューコメントを追加（1件目のスレッドは`resolved`、
  新規スレッド`PRRT_kwDOT4Y-5s6Zk1CA`が`unresolved`として検出された）。ユーザーからの合図は
  「レビュー指摘を記入した」のみだったが、ルール通り`get_mr_unresolved_comments 29 true`で機械的に
  確認し新規スレッドの存在を検出した。
- 指摘（`.claude/hooks/post-push-usage-report.sh:158`）: 「この部分のコメントについては、
  該当MRに対応工数レポートを最初に行うときだけ記載するようにすること」。フッターの免責事項説明文
  （集計方法・既知の過小カウント要因の説明）を、毎回のpushで繰り返し投稿するのではなく、
  そのMRへの初回投稿時のみに限定してほしいという指摘。
- 対応: `post-push-usage-report.sh`に`is_first_post`判定を追加した。状態ファイルの
  `lastPostedAt`（投稿前時点の値。存在すれば過去に投稿成功済み、存在しなければ初回）で分岐し、
  フッターの詳しい説明文（`Claude Codeより: 自動投稿...`の段落）はfalseの場合（2回目以降）は
  出力しないようにした。冒頭の「レビューの合否判定には使用しないでください」という短い注記は
  毎回表示したまま残した（投稿ごとの識別に必要なため）。
  `dev-tools/docs/spec/issue-mr-workflow.md`にもこの挙動を追記した。
- なお、ユーザー（または連携ツール）がフッター文言自体も手動編集していた
  （「transcriptの非公開フォーマットに依存した...」→「セッション情報ログを解析した集計のため、
  目安として扱ってください。」への簡略化）。この編集はそのまま活かし、上書きしていない。
- `bash -n`構文チェック・`tests/test_usage_tracking.sh`/`tests/test_vcs_provider.sh`の回帰確認済み。
  push後の実際のレポート投稿で、2回目以降フッターが省略されることを実地確認する。
- `get_mr_unresolved_comments 29`で未解決スレッド0件を確認済み（flow-id 14〜15ループ終了）。

## 設計反映・AIアセット改善（flow-id 16〜17）

- 実装を進めながら`dev-tools/docs/spec/issue-mr-workflow.md`（稼働時間の算出方法、
  トークン数の過小カウント要因、フッター初回投稿限定の挙動、影響範囲）と
  `dev-tools/docs/ddr/0006-...md`（追記セクション）へ都度反映していたため、flow-id 16時点での
  追加反映はほぼ無かった。差分確認のうえ、影響範囲セクションにレビュー往復2回分の変更ファイルを
  追記した。
- AIアセット改善: 今回のセッションで得られた再利用可能な知見を2件反映した。
  - `.claude/rules/shell-script-style.md`「JSON操作」節: Windowsネイティブjqの`strptime`/`mktime`
    未実装、および`try/catch`との組み合わせでエラーが握りつぶされる現象（issue #28以外の
    将来のスクリプトにも関わる一般的な注意事項のため）。
  - `.claude/rules/directory-structure.md`「配置の指針」: `参考ディレクトリ/`（`.gitignore`対象、
    ローカルにcloneした参考OSSの置き場所）という新しい局所的な慣習を、将来のセッションが
    混乱しないよう明記した。

## レビュー往復（flow-id 7〜8, 1回目）

- 指摘（yuki-matsu783, PR #29 `plans/noble-painting-waffle.md:25`）: 計測したいのは
  「Claude Codeが実際に作業している時間」であり、`AskUserQuestion`等での人間の回答待ちや、
  応答終了後に次の指示を待っている間の「作業していない時間」を除外するロジックになっているか、
  という確認。
- 対応: 単純な「セッション開始〜最終メッセージ」の経過時間ではこれらの待機時間を含んでしまうため、
  設計を変更した。連続するtranscript entry間のgap（時間差）が閾値（既定300秒）を超える区間を
  「人間の入力待ち」とみなして稼働時間（`activeSeconds`）に加算しないgapベースの方式に変更した。
  `plans/noble-painting-waffle.md` の「1.」節を更新済み。
  - トレードオフ: 5分以下の短い待機は区別できず稼働時間に混入しうる／5分を超える長時間ツール実行
    （大きめのビルド等）は逆に稼働時間から漏れうる。「目安」である旨をレポート・ドキュメントに
    明記する方針とした。
- 対応内容をスレッドへ返信予定（`reply`サブコマンド）。
