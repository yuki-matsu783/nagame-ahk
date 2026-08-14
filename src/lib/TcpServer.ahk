#Requires AutoHotkey v2.0

; 設計: docs/external-command-server.md
; TCPループバックソケットの接続待受・送受信のみを担当する汎用レイヤー。
; メッセージ(コマンド)の意味を知らず、改行区切りの1行(文字列)を渡す/受け取るだけの役割に徹する。
; JSONのパースやコマンドディスパッチは core/ExternalCommandServer.ahk が担当する。
;
; Winsock(ws2_32.dll)を非ブロッキングモードで使い、Settings.ServerPollIntervalMs間隔の
; SetTimerでaccept/recv/sendの可否をポーリングする(実装メモ: 当初はWSAAsyncSelect+OnMessageの
; イベント駆動方式を試したが、初回の接続が完了した後は以降の接続でFD_ACCEPT等のウィンドウ
; メッセージが一切届かなくなる再現性の高い不具合に遭遇し、原因を切り分けきれなかったため、
; 実績のあるポーリング方式に戻した)。
class TcpServer {
    ; ---- Winsock定数 ----
    static AF_INET := 2
    static SOCK_STREAM := 1
    static IPPROTO_TCP := 6
    static SOL_SOCKET := 0xFFFF
    static SO_REUSEADDR := 4
    static FIONBIO := 0x8004667E
    static WSAEWOULDBLOCK := 10035

    static _listenSocket := 0
    static _clientSocket := 0
    static _recvBuffer := ""     ; 受信済みだが改行未到達の文字列
    static _queuedLines := []    ; 送信待ちの文字列(エンコード前、1件=1メッセージ)
    static _pendingBuf := ""     ; 送信中(部分送信が発生した)バイト列のBuffer
    static _pendingOffset := 0
    static _pendingLen := 0
    static _wsaStarted := false
    ; SetTimerの登録/解除には同一のコールバックオブジェクトが必要なため、
    ; static プロパティとして1つ保持し、Start/Stopの両方で使い回す。
    static _pollCallback := (*) => TcpServer._Poll()

    ; 1行(JSON文字列)を受信するたびに呼ばれるコールバック。core側が差し込む。引数: (line)
    static OnLine := ""
    ; クライアントが接続したときに呼ばれるコールバック。
    static OnConnect := ""
    ; クライアントが切断したときに呼ばれるコールバック。
    static OnDisconnect := ""

    ; リッスンを開始する
    static Start() {
        if TcpServer._listenSocket != 0 {
            return
        }

        try {
            TcpServer._EnsureWsaStarted()
            TcpServer._listenSocket := TcpServer._CreateListenSocket()
            SetTimer(TcpServer._pollCallback, Settings.ServerPollIntervalMs)
            Logger.Info("外部コマンドサーバーを開始しました (" Settings.ServerHost ":" Settings.ServerPort ")")
        } catch as e {
            Logger.Error("外部コマンドサーバーの起動に失敗しました: " e.Message)
            Logger.Debug("Host=" Settings.ServerHost " Port=" Settings.ServerPort)
            TcpServer._listenSocket := 0
        }
    }

    ; リッスンを停止し、接続中のクライアントも切断する
    static Stop() {
        if TcpServer._listenSocket = 0 {
            return
        }

        SetTimer(TcpServer._pollCallback, 0)
        TcpServer._CloseClient(false)

        try {
            DllCall("ws2_32\closesocket", "Ptr", TcpServer._listenSocket)
        } catch as e {
            Logger.Error("リッスンソケットのクローズに失敗しました: " e.Message)
        }
        TcpServer._listenSocket := 0
        Logger.Info("外部コマンドサーバーを停止しました")
    }

    static IsRunning() {
        return TcpServer._listenSocket != 0
    }

    static IsConnected() {
        return TcpServer._clientSocket != 0
    }

    ; 現在接続中のクライアントを切断する(リッスンソケット自体は継続し、次の接続を待つ)
    static DisconnectClient() {
        TcpServer._CloseClient(true)
    }

    ; 接続中のクライアントへ1メッセージ(1行)送信する。改行は自動付与する。
    static SendLine(text) {
        if TcpServer._clientSocket = 0 {
            Logger.Debug("SendLine呼び出し時にクライアント未接続のため送信をスキップしました")
            return
        }
        TcpServer._queuedLines.Push(text "`n")
        TcpServer._FlushSendQueue()
    }

    static _EnsureWsaStarted() {
        if TcpServer._wsaStarted {
            return
        }
        ; WSADATA構造体。内容は使わないため十分なサイズのバッファを確保するだけでよい。
        wsaData := Buffer(512, 0)
        result := DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaData, "Int")
        if result != 0 {
            throw Error("WSAStartupに失敗しました (code=" result ")")
        }
        TcpServer._wsaStarted := true
    }

    static _CreateListenSocket() {
        sock := DllCall("ws2_32\socket", "Int", TcpServer.AF_INET, "Int", TcpServer.SOCK_STREAM, "Int", TcpServer.IPPROTO_TCP, "Ptr")
        if sock = -1 {
            throw Error("socket()に失敗しました (WSAGetLastError=" DllCall("ws2_32\WSAGetLastError", "Int") ")")
        }

        optVal := Buffer(4, 0)
        NumPut("Int", 1, optVal)
        DllCall("ws2_32\setsockopt", "Ptr", sock, "Int", TcpServer.SOL_SOCKET, "Int", TcpServer.SO_REUSEADDR, "Ptr", optVal, "Int", 4)

        addr := TcpServer._BuildSockAddr(Settings.ServerHost, Settings.ServerPort)
        if DllCall("ws2_32\bind", "Ptr", sock, "Ptr", addr, "Int", addr.Size, "Int") = -1 {
            errCode := DllCall("ws2_32\WSAGetLastError", "Int")
            DllCall("ws2_32\closesocket", "Ptr", sock)
            throw Error("bind()に失敗しました (WSAGetLastError=" errCode ")")
        }

        if DllCall("ws2_32\listen", "Ptr", sock, "Int", 5, "Int") = -1 {
            errCode := DllCall("ws2_32\WSAGetLastError", "Int")
            DllCall("ws2_32\closesocket", "Ptr", sock)
            throw Error("listen()に失敗しました (WSAGetLastError=" errCode ")")
        }

        try {
            TcpServer._SetNonBlocking(sock)
        } catch as e {
            DllCall("ws2_32\closesocket", "Ptr", sock)
            throw e
        }

        return sock
    }

    ; ソケットを非ブロッキングモードに設定する。accept()で生成した新しいソケットは
    ; リッスンソケットのモードを自動継承しないため、クライアント側でも都度呼び出す。
    static _SetNonBlocking(sock) {
        flag := Buffer(4, 0)
        NumPut("UInt", 1, flag)
        if DllCall("ws2_32\ioctlsocket", "Ptr", sock, "Int", TcpServer.FIONBIO, "Ptr", flag, "Int") = -1 {
            errCode := DllCall("ws2_32\WSAGetLastError", "Int")
            throw Error("ioctlsocket(FIONBIO)に失敗しました (WSAGetLastError=" errCode ")")
        }
    }

    ; sockaddr_in構造体(16byte)を構築する
    static _BuildSockAddr(host, port) {
        addr := Buffer(16, 0)
        NumPut("Short", TcpServer.AF_INET, addr, 0)
        NumPut("UShort", DllCall("ws2_32\htons", "UShort", port, "UShort"), addr, 2)
        NumPut("UInt", DllCall("ws2_32\inet_addr", "AStr", host, "UInt"), addr, 4)
        return addr
    }

    ; SetTimerで定期的に呼ばれ、accept/recv/sendの可否をポーリングする
    static _Poll(*) {
        if TcpServer._listenSocket = 0 {
            return
        }

        TcpServer._PollAccept()

        if TcpServer._clientSocket != 0 {
            TcpServer._PollRead()
        }
        if TcpServer._clientSocket != 0 {
            TcpServer._FlushSendQueue()
        }
    }

    ; 保留中の新規接続が無くなるまで(WSAEWOULDBLOCKになるまで)accept()し続ける
    static _PollAccept() {
        loop {
            client := DllCall("ws2_32\accept", "Ptr", TcpServer._listenSocket, "Ptr", 0, "Ptr", 0, "Ptr")
            if client = -1 {
                errCode := DllCall("ws2_32\WSAGetLastError", "Int")
                if errCode != TcpServer.WSAEWOULDBLOCK {
                    Logger.Error("accept()に失敗しました (WSAGetLastError=" errCode ")")
                }
                return
            }

            if TcpServer._clientSocket != 0 {
                ; v1は同時1接続のみ想定。既存接続がある場合は新規接続を受け入れず即座に閉じる。
                DllCall("ws2_32\closesocket", "Ptr", client)
                Logger.Info("既に接続中のため新規接続を拒否しました")
                continue
            }

            try {
                TcpServer._SetNonBlocking(client)
            } catch as e {
                Logger.Error("クライアントソケットの非ブロッキング化に失敗しました: " e.Message)
                DllCall("ws2_32\closesocket", "Ptr", client)
                continue
            }

            TcpServer._clientSocket := client
            TcpServer._recvBuffer := ""
            TcpServer._queuedLines := []
            TcpServer._pendingBuf := ""
            Logger.Info("クライアントが接続しました")
            if TcpServer.OnConnect != "" {
                TcpServer.OnConnect.Call()
            }
        }
    }

    ; 読める分が無くなるまで(WSAEWOULDBLOCKになるまで)recv()し続ける
    static _PollRead() {
        buf := Buffer(Settings.ServerBufferSize, 0)
        loop {
            ; _ProcessRecvBuffer()が呼ぶOnLineコールバック(認証失敗時のDisconnectClient等)の中で
            ; 同期的にソケットが閉じられることがあるため、ループの各周回で必ず再チェックする。
            if TcpServer._clientSocket = 0 {
                return
            }
            n := DllCall("ws2_32\recv", "Ptr", TcpServer._clientSocket, "Ptr", buf, "Int", buf.Size, "Int", 0, "Int")
            if n > 0 {
                TcpServer._recvBuffer .= StrGet(buf, n, "UTF-8")
                TcpServer._ProcessRecvBuffer()
                continue
            } else if n = 0 {
                TcpServer._HandleClose()
                return
            } else {
                errCode := DllCall("ws2_32\WSAGetLastError", "Int")
                if errCode != TcpServer.WSAEWOULDBLOCK {
                    Logger.Error("recv()に失敗しました (WSAGetLastError=" errCode ")")
                    TcpServer._HandleClose()
                }
                ; WSAEWOULDBLOCKは「現時点で読める分は読み切った」ことを意味するので正常終了
                return
            }
        }
    }

    ; 受信バッファを改行区切りで分割し、1行ごとにOnLineコールバックへ渡す
    static _ProcessRecvBuffer() {
        loop {
            pos := InStr(TcpServer._recvBuffer, "`n")
            if !pos {
                break
            }
            line := SubStr(TcpServer._recvBuffer, 1, pos - 1)
            TcpServer._recvBuffer := SubStr(TcpServer._recvBuffer, pos + 1)
            line := Trim(line, "`r")
            if line = "" {
                continue
            }
            Logger.Debug("受信: " line)
            if TcpServer.OnLine != "" {
                TcpServer.OnLine.Call(line)
            }
        }
    }

    ; 送信待ちキューを可能な限り送信する。ソケットバッファが満杯(WSAEWOULDBLOCK)の場合は
    ; 途中で打ち切り、次のポーリングタイミングで再試行する。
    static _FlushSendQueue() {
        if TcpServer._clientSocket = 0 {
            return
        }

        loop {
            if TcpServer._pendingBuf = "" {
                if TcpServer._queuedLines.Length = 0 {
                    return
                }
                nextText := TcpServer._queuedLines.RemoveAt(1)
                byteLen := StrPut(nextText, "UTF-8") - 1 ; 末尾null分を除く
                buf := Buffer(byteLen, 0)
                StrPut(nextText, buf, "UTF-8")
                TcpServer._pendingBuf := buf
                TcpServer._pendingOffset := 0
                TcpServer._pendingLen := byteLen
            }

            remaining := TcpServer._pendingLen - TcpServer._pendingOffset
            if remaining <= 0 {
                TcpServer._pendingBuf := ""
                continue
            }

            ; 送信済み位置からのポインタを渡すことで、マルチバイト文字境界を意識せず
            ; バイト単位で安全に再送できる(文字列を再スライスするとUTF-8境界を壊す恐れがあるため)
            n := DllCall("ws2_32\send", "Ptr", TcpServer._clientSocket, "Ptr", TcpServer._pendingBuf.Ptr + TcpServer._pendingOffset, "Int", remaining, "Int", 0, "Int")
            if n = -1 {
                errCode := DllCall("ws2_32\WSAGetLastError", "Int")
                if errCode != TcpServer.WSAEWOULDBLOCK {
                    Logger.Error("send()に失敗しました (WSAGetLastError=" errCode ")")
                    TcpServer._HandleClose()
                }
                return
            }

            TcpServer._pendingOffset += n
            if TcpServer._pendingOffset >= TcpServer._pendingLen {
                TcpServer._pendingBuf := ""
            }
        }
    }

    static _HandleClose() {
        wasConnected := TcpServer._clientSocket != 0
        TcpServer._CloseClient(true)
        if wasConnected {
            Logger.Info("クライアントが切断しました")
        }
    }

    ; クライアントソケットを閉じ、状態をリセットする
    ; notify: true の場合、OnDisconnectコールバックを呼ぶ(サーバー全体停止時の呼び出しでは不要なためfalseにする)
    static _CloseClient(notify) {
        if TcpServer._clientSocket != 0 {
            try {
                DllCall("ws2_32\closesocket", "Ptr", TcpServer._clientSocket)
            } catch as e {
                Logger.Error("クライアントソケットのクローズに失敗しました: " e.Message)
            }
        }
        hadClient := TcpServer._clientSocket != 0
        TcpServer._clientSocket := 0
        TcpServer._recvBuffer := ""
        TcpServer._queuedLines := []
        TcpServer._pendingBuf := ""

        if notify && hadClient && TcpServer.OnDisconnect != "" {
            TcpServer.OnDisconnect.Call()
        }
    }
}
