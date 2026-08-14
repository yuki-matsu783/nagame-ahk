<#
.SYNOPSIS
    ExternalCommandServer(docs/spec/external-command-server.md)の結合スモークテスト。

.DESCRIPTION
    src/main.ahk を実際に起動し、TCPクライアントとして接続して Auth および代表的なコマンドを
    送受信し、レスポンスが期待通りかを確認する。テスト終了後は起動したAutoHotkeyプロセスを終了する。

    確認しているのは低リスクなコマンドのみ(SendKeys/MouseClick/PlayMacro/GUI系ダイアログは
    実機の入力・表示を伴うため対象外。手動で確認すること)。

.NOTES
    - 副作用があります: クリップボードの内容を書き換える、トレイにトースト通知を表示する。
    - 既に常駐版nagame-ahkが起動していると多重起動になり誤検知するため、実行前に一旦終了しておくこと。
      (このスクリプトはテスト対象のAutoHotkeyプロセスを名前で判別して終了するため、無関係な
      AutoHotkeyスクリプトが同時に動いていると巻き込んで終了させてしまう点に注意)
    - Settings.ServerPort / Settings.AuthToken を変更した場合は、下記の $port / $authToken も
      合わせて変更すること。

.EXAMPLE
    powershell -File tests\test_external_command_server.ps1
#>

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ahkExe = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$mainScript = Join-Path $repoRoot "src\main.ahk"
$logPath = Join-Path $repoRoot "nagame-ahk.log"
$serverHost = "127.0.0.1"
$port = 39321       # Settings.ServerPort の既定値
$authToken = "ahk-rira" # Settings.AuthToken の既定値

$script:passed = 0
$script:failures = 0

function Assert-Equal($actual, $expected, $label) {
    if ("$actual" -eq "$expected") {
        $script:passed++
    } else {
        $script:failures++
        Write-Output "FAIL: $label expected=[$expected] actual=[$actual]"
    }
}

function Assert-True($condition, $label) {
    if ($condition) {
        $script:passed++
    } else {
        $script:failures++
        Write-Output "FAIL: $label (condition was false)"
    }
}

function New-Client {
    $client = New-Object System.Net.Sockets.TcpClient($serverHost, $port)
    $writer = New-Object System.IO.StreamWriter($client.GetStream())
    $writer.AutoFlush = $true
    $reader = New-Object System.IO.StreamReader($client.GetStream())
    return [PSCustomObject]@{ Client = $client; Writer = $writer; Reader = $reader }
}

function Send-Command($conn, $json) {
    $conn.Writer.WriteLine($json)
    $line = $conn.Reader.ReadLine()
    if ($null -eq $line) {
        throw "接続が切断され応答を受信できませんでした"
    }
    return $line | ConvertFrom-Json
}

# ---- 準備: 既存プロセスを止めてから起動 ----
Get-Process -Name "AutoHotkey64" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
if (Test-Path $logPath) { Remove-Item $logPath -Force }

Start-Process -FilePath $ahkExe -ArgumentList "`"$mainScript`""
Start-Sleep -Seconds 2

$proc = Get-Process -Name "AutoHotkey64" -ErrorAction SilentlyContinue
Assert-True ($null -ne $proc) "main.ahkのプロセスが起動していること"

try {
    # ---- 未認証状態: 誤トークンは拒否され、以降の書き込みも失敗する(切断されている) ----
    $conn = New-Client
    $res = Send-Command $conn '{"id":"1","command":"Auth","params":{"token":"wrong-token"}}'
    Assert-Equal $res.ok $false "誤トークンのAuthはok:falseを返す"
    Assert-Equal $res.error "authentication required" "誤トークンのAuthのエラーメッセージ"
    Start-Sleep -Milliseconds 200
    $disconnected = $false
    try {
        $conn.Writer.WriteLine('{"id":"x","command":"ShowToast","params":{"title":"x","message":"y"}}')
        if ($null -eq $conn.Reader.ReadLine()) { $disconnected = $true }
    } catch {
        $disconnected = $true
    }
    Assert-True $disconnected "認証失敗後は接続がサーバー側から切断されること"
    $conn.Client.Close()

    # ---- 未認証状態でAuth以外を送ると拒否される ----
    $conn = New-Client
    $res = Send-Command $conn '{"id":"1","command":"GetActiveWindow","params":{}}'
    Assert-Equal $res.ok $false "未認証でコマンドを送るとok:falseになる"
    $conn.Client.Close()

    # ---- 正常系 ----
    $conn = New-Client
    $res = Send-Command $conn ('{{"id":"1","command":"Auth","params":{{"token":"{0}"}}}}' -f $authToken)
    Assert-Equal $res.ok $true "正しいトークンでのAuthが成功すること"

    $res = Send-Command $conn '{"id":"2","command":"GetActiveWindow","params":{}}'
    Assert-Equal $res.ok $true "GetActiveWindowが成功すること"
    Assert-True ($res.result.hwnd -gt 0) "GetActiveWindowがhwndを返すこと"

    $res = Send-Command $conn '{"id":"3","command":"ListWindows","params":{}}'
    Assert-Equal $res.ok $true "ListWindowsが成功すること"
    Assert-True ($res.result.windows.Count -gt 0) "ListWindowsが1件以上返すこと"

    $marker = "nagame-ahk-test-" + [Guid]::NewGuid().ToString("N")
    $res = Send-Command $conn ('{{"id":"4","command":"SetClipboard","params":{{"text":"{0}"}}}}' -f $marker)
    Assert-Equal $res.ok $true "SetClipboardが成功すること"
    $res = Send-Command $conn '{"id":"5","command":"GetClipboard","params":{}}'
    Assert-Equal $res.result.text $marker "GetClipboardがSetClipboardした内容を返すこと(クリップボードを書き換えます)"

    $res = Send-Command $conn '{"id":"6","command":"ShowToast","params":{"title":"テスト","message":"外部コマンドサーバーのスモークテストです"}}'
    Assert-Equal $res.ok $true "ShowToastが成功すること(トースト通知が表示されます)"

    $res = Send-Command $conn '{"id":"7","command":"NoSuchCommand","params":{}}'
    Assert-Equal $res.ok $false "未知のコマンドはok:falseになる"
    Assert-True ($res.error -like "unknown command:*") "未知のコマンドのエラーメッセージ"

    $conn.Client.Close()
} finally {
    Get-Process -Name "AutoHotkey64" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Output "----"
Write-Output "passed=$script:passed failures=$script:failures"
if ($script:failures -gt 0) {
    exit 1
} else {
    exit 0
}
