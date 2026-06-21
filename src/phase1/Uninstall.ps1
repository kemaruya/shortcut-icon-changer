#requires -Version 5.1
<#
.SYNOPSIS
    shortcut-icon-changer (Phase 1) をアンインストールする。
.DESCRIPTION
    右クリックメニューのレジストリ登録 (HKCU) を削除し、インストール先のプログラム
    ファイルを削除する。-Purge を付けると、取得済みアイコンライブラリと変換キャッシュ
    (%LOCALAPPDATA%\ShortcutIconChanger) も削除する。
.PARAMETER InstallDir
    インストール先。既定は %LOCALAPPDATA%\Programs\ShortcutIconChanger。
.PARAMETER Purge
    アイコンライブラリ/キャッシュも削除する。
.PARAMETER Quiet
    対話なしで実行。
#>
[CmdletBinding()]
param(
    [string] $InstallDir,
    [switch] $Purge,
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $InstallDir) {
    $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\ShortcutIconChanger'
}

# --- レジストリ verb 削除 -----------------------------------------------
$verbKey = 'HKCU:\Software\Classes\lnkfile\shell\sic.ChangeIcon'
if (Test-Path $verbKey) {
    Remove-Item -Path $verbKey -Recurse -Force
    if (-not $Quiet) { Write-Host "右クリックメニューの登録を削除しました。" -ForegroundColor Green }
}
else {
    if (-not $Quiet) { Write-Host "右クリックメニューの登録は見つかりませんでした。" }
}

# --- プログラムファイル削除 ---------------------------------------------
if (Test-Path $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    if (-not $Quiet) { Write-Host ("インストール先を削除しました: {0}" -f $InstallDir) -ForegroundColor Green }
}

# --- ユーザーデータ (任意) ----------------------------------------------
$userData = Join-Path $env:LOCALAPPDATA 'ShortcutIconChanger'
if ($Purge -and (Test-Path $userData)) {
    Remove-Item -LiteralPath $userData -Recurse -Force
    if (-not $Quiet) { Write-Host ("ライブラリ/キャッシュを削除しました: {0}" -f $userData) -ForegroundColor Green }
}
elseif ((Test-Path $userData) -and -not $Quiet) {
    Write-Host ("アイコンライブラリ/キャッシュは保持しました（削除するには -Purge）: {0}" -f $userData)
}

if (-not $Quiet) {
    Write-Host ""
    Write-Host "アンインストールが完了しました。" -ForegroundColor Green
}
