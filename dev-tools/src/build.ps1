<#
    Windows用exeへのビルドスクリプト（Ahk2Exeを呼び出す）。
    設計: dev-tools/docs/spec/distribution.md

    使い方:
        powershell -File dev-tools\src\build.ps1

    前提: 開発者PCに AutoHotkey v2（Ahk2Exeを含む）がインストール済みであること。
    Ahk2Exe.exe / AutoHotkey v2本体の場所が既定と異なる場合は、環境変数
    AHK2EXE_PATH / AHK_V2_EXE_PATH でパスを指定する。

    注意: Ahk2Exe.exe（Compilerフォルダ）は環境によってv1系のbaseファイルが既定になっている
    ことがあるため、/base で明示的にAutoHotkey v2本体(AutoHotkey64.exe)を指定してコンパイルする。
#>

$ErrorActionPreference = "Stop"

# リポジトリルート（このスクリプトの2階層上: dev-tools\src -> リポジトリルート）
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$mainAhk = Join-Path $repoRoot "src\main.ahk"
$buildDir = Join-Path $repoRoot "build"

# Ahk2Exe.exe のパス（環境変数 AHK2EXE_PATH で上書き可能。既定はAutoHotkey標準インストール先のCompilerフォルダ）
$ahk2exe = if ($env:AHK2EXE_PATH) {
    $env:AHK2EXE_PATH
} else {
    Join-Path $env:ProgramFiles "AutoHotkey\Compiler\Ahk2Exe.exe"
}

if (-not (Test-Path $ahk2exe)) {
    Write-Error "Ahk2Exe.exe が見つかりません: $ahk2exe`n環境変数 AHK2EXE_PATH でパスを指定してください。"
    exit 1
}

# コンパイルのbase(実行ランタイム)となるAutoHotkey v2本体のパス
# （環境変数 AHK_V2_EXE_PATH で上書き可能。既定はAutoHotkey v2の標準インストール先）
$ahkV2Exe = if ($env:AHK_V2_EXE_PATH) {
    $env:AHK_V2_EXE_PATH
} else {
    Join-Path $env:ProgramFiles "AutoHotkey\v2\AutoHotkey64.exe"
}

if (-not (Test-Path $ahkV2Exe)) {
    Write-Error "AutoHotkey v2本体(AutoHotkey64.exe)が見つかりません: $ahkV2Exe`n環境変数 AHK_V2_EXE_PATH でパスを指定してください。"
    exit 1
}

# src\main.ahk の ;@Ahk2Exe-SetVersion ディレクティブから配布ファイル名用のバージョンを取得する
# （src\config\Settings.ahk の Version と手動同期している前提。distribution.md 参照）
$versionMatch = Select-String -Path $mainAhk -Pattern "^;@Ahk2Exe-SetVersion\s+(\S+)" | Select-Object -First 1
if (-not $versionMatch) {
    Write-Error "src\main.ahk に ;@Ahk2Exe-SetVersion ディレクティブが見つかりません。"
    exit 1
}
$version = $versionMatch.Matches[0].Groups[1].Value

if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}

$outFile = Join-Path $buildDir "nagame-ahk-v$version.exe"

# アイコンが用意されていれば指定する（未配置の場合はAhk2Exe既定アイコンを使う）
$iconPath = Join-Path $repoRoot "assets\icons\icon.ico"
$ahk2exeArgs = @("/in", $mainAhk, "/out", $outFile, "/base", $ahkV2Exe)
if (Test-Path $iconPath) {
    $ahk2exeArgs += @("/icon", $iconPath)
}

if (Test-Path $outFile) {
    Remove-Item $outFile -Force
}

Write-Host "Building $outFile ..."
& $ahk2exe @ahk2exeArgs

# Ahk2Exe.exe はGUIサブシステムのアプリで $LASTEXITCODE が信用できず、また出力ファイルの書き込みが
# 呼び出し元への復帰より遅れて完了することがあるため、$LASTEXITCODE ではなく出力ファイルの存在を
# 数秒間リトライしながら判定する。
$timeoutSec = 20
$waited = 0
while (-not (Test-Path $outFile) -and $waited -lt $timeoutSec) {
    Start-Sleep -Seconds 1
    $waited++
}

if (-not (Test-Path $outFile)) {
    Write-Error "Ahk2Exe のビルドに失敗しました（${timeoutSec}秒待っても出力ファイルが生成されませんでした: $outFile）"
    exit 1
}

Write-Host "Build succeeded: $outFile"
