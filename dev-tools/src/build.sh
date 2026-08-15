#!/usr/bin/env bash
#
# Windows用exeへのビルドスクリプト（Ahk2Exeを呼び出す。bash版）。
# 設計: dev-tools/docs/spec/distribution.md, dev-tools/docs/spec/shell-scripts.md
#
# 使い方:
#     dev-tools/src/build.sh
#
# 前提: 開発者PCに AutoHotkey v2（Ahk2Exeを含む）がインストール済みであること。
# Ahk2Exe.exe / AutoHotkey v2本体の場所が既定と異なる場合は、環境変数
# AHK2EXE_PATH / AHK_V2_EXE_PATH でパスを指定する。
#
# 注意: Ahk2Exe.exe（Compilerフォルダ）は環境によってv1系のbaseファイルが既定になっている
# ことがあるため、/base で明示的にAutoHotkey v2本体(AutoHotkey64.exe)を指定してコンパイルする。

set -euo pipefail

# リポジトリルート（このスクリプトの2階層上: dev-tools/src -> リポジトリルート）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MAIN_AHK="${REPO_ROOT}/src/main.ahk"
BUILD_DIR="${REPO_ROOT}/build"

# Ahk2Exe.exe のパス（環境変数 AHK2EXE_PATH で上書き可能。既定はAutoHotkey標準インストール先のCompilerフォルダ）
AHK2EXE="${AHK2EXE_PATH:-${PROGRAMFILES}/AutoHotkey/Compiler/Ahk2Exe.exe}"

if [ ! -f "$AHK2EXE" ]; then
  echo "Ahk2Exe.exe が見つかりません: ${AHK2EXE}
環境変数 AHK2EXE_PATH でパスを指定してください。" >&2
  exit 1
fi

# コンパイルのbase(実行ランタイム)となるAutoHotkey v2本体のパス
# （環境変数 AHK_V2_EXE_PATH で上書き可能。既定はAutoHotkey v2の標準インストール先）
AHK_V2_EXE="${AHK_V2_EXE_PATH:-${PROGRAMFILES}/AutoHotkey/v2/AutoHotkey64.exe}"

if [ ! -f "$AHK_V2_EXE" ]; then
  echo "AutoHotkey v2本体(AutoHotkey64.exe)が見つかりません: ${AHK_V2_EXE}
環境変数 AHK_V2_EXE_PATH でパスを指定してください。" >&2
  exit 1
fi

# src/main.ahk の ;@Ahk2Exe-SetVersion ディレクティブから配布ファイル名用のバージョンを取得する
# （src/config/Settings.ahk の Version と手動同期している前提。distribution.md参照）
VERSION="$(grep -m1 -E '^;@Ahk2Exe-SetVersion[[:space:]]+' "$MAIN_AHK" | sed -E 's/^;@Ahk2Exe-SetVersion[[:space:]]+(\S+).*/\1/')"
if [ -z "$VERSION" ]; then
  echo "src/main.ahk に ;@Ahk2Exe-SetVersion ディレクティブが見つかりません。" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

OUT_FILE="${BUILD_DIR}/nagame-ahk-v${VERSION}.exe"

# アイコンが用意されていれば指定する（未配置の場合はAhk2Exe既定アイコンを使う）
#
# 注意（git bashのパス変換）: `/in` のようなDOS形式の単一スラッシュ引数は、git bash（MSYS）が
# 「POSIXパスらしき文字列」と誤認し、Windowsパスへ自動変換してしまう既知の問題がある
# （実機確認: `/in` が `C:/Program Files/Git/in` に化けて「Unrecognised parameter」エラーになった）。
# 先頭を `//` にするとMSYSの自動変換対象から外れ、ネイティブ側には `/in` として渡る
# （`tasklist`/`taskkill`のWindowsフラグも同様の理由で `//FI` 等と書く。詳細:
# dev-tools/docs/spec/shell-scripts.md「git bashのパス変換」節）。
ICON_PATH="${REPO_ROOT}/assets/icons/icon.ico"
AHK2EXE_ARGS=(//in "$MAIN_AHK" //out "$OUT_FILE" //base "$AHK_V2_EXE")
if [ -f "$ICON_PATH" ]; then
  AHK2EXE_ARGS+=(//icon "$ICON_PATH")
fi

if [ -f "$OUT_FILE" ]; then
  rm -f "$OUT_FILE"
fi

echo "Building ${OUT_FILE} ..."
"$AHK2EXE" "${AHK2EXE_ARGS[@]}"

# Ahk2Exe.exe はGUIサブシステムのアプリで終了コードが信用できず、また出力ファイルの書き込みが
# 呼び出し元への復帰より遅れて完了することがあるため、終了コードではなく出力ファイルの存在を
# 数秒間リトライしながら判定する。
TIMEOUT_SEC=20
WAITED=0
while [ ! -f "$OUT_FILE" ] && [ "$WAITED" -lt "$TIMEOUT_SEC" ]; do
  sleep 1
  WAITED=$((WAITED + 1))
done

if [ ! -f "$OUT_FILE" ]; then
  echo "Ahk2Exe のビルドに失敗しました（${TIMEOUT_SEC}秒待っても出力ファイルが生成されませんでした: ${OUT_FILE}）" >&2
  exit 1
fi

echo "Build succeeded: ${OUT_FILE}"
