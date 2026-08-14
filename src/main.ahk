#Requires AutoHotkey v2.0
#SingleInstance Force

; エントリーポイント。#Include の集約とアプリ起動のみを行う。
; ロジックはここに書かず、各モジュール（config → lib → core → features）に委譲する。
#Include config\Settings.ahk
#Include lib\Logger.ahk
#Include lib\WindowUtils.ahk
#Include core\TrayMenu.ahk
#Include core\Hotkeys.ahk
#Include core\App.ahk
#Include features\ActivityStatus.ahk

App.Start()
