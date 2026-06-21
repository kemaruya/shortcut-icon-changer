#requires -Version 5.1
<#
.SYNOPSIS
    shortcut-icon-changer (Phase 1) をインストールする（HKCU・管理者権限不要）。
.DESCRIPTION
    アプリ一式を %LOCALAPPDATA%\Programs\ShortcutIconChanger へコピーし、
    .lnk の右クリックメニューに「アイコンを変更」を登録する。
    リポジトリ レイアウトでも配布パッケージ（app\ サブフォルダ）でも動作する。
    インストール先にコピーするため、リポジトリの場所に依存しない。
.PARAMETER InstallDir
    インストール先。既定は %LOCALAPPDATA%\Programs\ShortcutIconChanger。
.PARAMETER Quiet
    対話なしで実行（自己解凍インストーラから利用）。
#>
[CmdletBinding()]
param(
    [string] $InstallDir,
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot

# --- アプリのソース（スクリプト/アセット）を解決 -------------------------
$scriptDir = $null
foreach ($c in @($here, (Join-Path $here 'app'))) {
    if ($c -and (Test-Path (Join-Path $c 'SicCore.psm1'))) { $scriptDir = $c; break }
}
if (-not $scriptDir) { throw "アプリ本体 (SicCore.psm1) が見つかりません。" }

$assetsDir = $null
foreach ($c in @((Join-Path $scriptDir 'assets'), (Join-Path $here 'assets'), (Join-Path $here '..\..\assets'))) {
    if ($c -and (Test-Path $c)) { $assetsDir = (Resolve-Path $c).Path; break }
}
if (-not $assetsDir) { throw "assets フォルダが見つかりません。" }

if (-not $InstallDir) {
    $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\ShortcutIconChanger'
}

# --- コピー -------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$scripts = @('SicCore.psm1', 'IconPicker.ps1', 'Launch-IconPicker.ps1')
foreach ($s in $scripts) {
    $srcFile = Join-Path $scriptDir $s
    if (-not (Test-Path $srcFile)) { throw "必要なファイルがありません: $s" }
    Copy-Item -LiteralPath $srcFile -Destination (Join-Path $InstallDir $s) -Force
}

$destAssets = Join-Path $InstallDir 'assets'
if (Test-Path $destAssets) { Remove-Item -LiteralPath $destAssets -Recurse -Force }
Copy-Item -LiteralPath $assetsDir -Destination $destAssets -Recurse -Force

$versionFile = Join-Path $here 'VERSION'
if (-not (Test-Path $versionFile)) { $versionFile = Join-Path $here '..\..\VERSION' }
$version = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { 'dev' }
Set-Content -Path (Join-Path $InstallDir 'VERSION') -Value $version -NoNewline -Encoding ascii

# --- レジストリ verb 登録 (HKCU) ----------------------------------------
$verbKey = 'HKCU:\Software\Classes\lnkfile\shell\sic.ChangeIcon'
$cmdKey = "$verbKey\command"
$appIcon = Join-Path $InstallDir 'assets\app.ico'
$launch = Join-Path $InstallDir 'Launch-IconPicker.ps1'
$psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$command = '"{0}" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" -LnkPath "%1"' -f $psExe, $launch

New-Item -Path $verbKey -Force | Out-Null
Set-ItemProperty -Path $verbKey -Name '(Default)' -Value 'アイコンを変更(&I)...'
Set-ItemProperty -Path $verbKey -Name 'Icon' -Value $appIcon
New-Item -Path $cmdKey -Force | Out-Null
Set-ItemProperty -Path $cmdKey -Name '(Default)' -Value $command

if (-not $Quiet) {
    Write-Host ""
    Write-Host "インストールが完了しました。" -ForegroundColor Green
    Write-Host ("  インストール先 : {0}" -f $InstallDir)
    Write-Host ("  バージョン     : {0}" -f $version)
    Write-Host ""
    Write-Host "使い方: 任意の .lnk を右クリック →「その他のオプションを表示」→「アイコンを変更」"
    Write-Host "全アイコン取得（任意）: tools\Fetch-FluentEmoji.ps1"
}
