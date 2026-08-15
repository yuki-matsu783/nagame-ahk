#Requires AutoHotkey v2.0
#SingleInstance Force

; エントリーポイント。#Include の集約とアプリ起動のみを行う。
; ロジックはここに書かず、各モジュール（config → lib → core → features）に委譲する。

; Ahk2Exeでコンパイルする際のexeファイル情報。値は config\Settings.ahk の AppName/Version と手動で一致させる。
; 設計: dev-tools/docs/spec/distribution.md
;@Ahk2Exe-SetName nagame-ahk
;@Ahk2Exe-SetDescription nagame-ahk 常駐ホットキー／自動化スクリプト
;@Ahk2Exe-SetVersion 0.1.0
;@Ahk2Exe-SetProductName nagame-ahk
;@Ahk2Exe-SetMainIcon assets\icons\icon.ico

#Include config\Settings.ahk
#Include config\Macros.ahk
#Include lib\Logger.ahk
#Include lib\Json.ahk
#Include lib\WindowUtils.ahk
#Include lib\TcpServer.ahk
#Include lib\WindowOpenWatcher.ahk
#Include lib\FileOpenNotifier.ahk
#Include core\TrayMenu.ahk
#Include core\Hotkeys.ahk
#Include core\App.ahk
#Include core\ExternalCommandServer.ahk
#Include features\ActivityStatus.ahk
#Include features\WindowControl.ahk
#Include features\InputControl.ahk
#Include features\ClipboardControl.ahk
#Include features\NotifyUI.ahk
#Include features\OfficeFileWatcher.ahk
#Include features\PdfFileWatcher.ahk
#Include features\RecentDocsWatcher.ahk

App.Start()