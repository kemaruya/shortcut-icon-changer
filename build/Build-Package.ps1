#requires -Version 5.1
<#
.SYNOPSIS
    Phase 1 の配布パッケージを生成する: ZIP ＋ 自己解凍インストーラ EXE (IExpress)。
.DESCRIPTION
    リポジトリのアプリ一式をステージングし、以下を dist\ に出力する。
      1. shortcut-icon-changer-phase1-v<VERSION>.zip
         展開して Install.cmd を実行すれば導入できる ZIP。
      2. shortcut-icon-changer-phase1-v<VERSION>-installer.exe
         Windows 同梱の IExpress による自己解凍インストーラ。ダブルクリックで導入。
         （内部に上記 ZIP を内包し、展開して Install.ps1 を実行する。）
    追加ランタイムやサードパーティ ツールは不要（IExpress は Windows 標準）。
.PARAMETER Version
    パッケージ バージョン。既定はリポジトリ ルートの VERSION ファイル。
.PARAMETER OutDir
    出力先。既定は <repo>\dist。
.PARAMETER SkipExe
    自己解凍 EXE の生成を省略し ZIP のみ作る。
#>
[CmdletBinding()]
param(
    [string] $Version,
    [string] $OutDir,
    [switch] $SkipExe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$phase1 = Join-Path $repo 'src\phase1'
$assets = Join-Path $repo 'assets'

if (-not $Version) {
    $vf = Join-Path $repo 'VERSION'
    $Version = if (Test-Path $vf) { (Get-Content $vf -Raw).Trim() } else { '0.0.0' }
}
if (-not $OutDir) { $OutDir = Join-Path $repo 'dist' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$pkgName = "shortcut-icon-changer-phase1-v$Version"
$zipPath = Join-Path $OutDir "$pkgName.zip"
$exePath = Join-Path $OutDir "$pkgName-installer.exe"

Write-Host ("パッケージ生成: {0}" -f $pkgName) -ForegroundColor Cyan

# --- 1) ステージング -----------------------------------------------------
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("sic-stage-" + [guid]::NewGuid().ToString('N'))
$appStage = Join-Path $staging 'app'
New-Item -ItemType Directory -Force -Path $appStage | Out-Null

# アプリ本体 -> app\
foreach ($s in @('SicCore.psm1', 'IconPicker.ps1', 'Launch-IconPicker.ps1')) {
    Copy-Item -LiteralPath (Join-Path $phase1 $s) -Destination (Join-Path $appStage $s) -Force
}
Copy-Item -LiteralPath $assets -Destination (Join-Path $appStage 'assets') -Recurse -Force

# インストーラ / 付随ファイル -> ルート
Copy-Item -LiteralPath (Join-Path $phase1 'Install.ps1')   -Destination (Join-Path $staging 'Install.ps1')   -Force
Copy-Item -LiteralPath (Join-Path $phase1 'Uninstall.ps1') -Destination (Join-Path $staging 'Uninstall.ps1') -Force
Copy-Item -LiteralPath (Join-Path $repo 'LICENSE')                 -Destination (Join-Path $staging 'LICENSE') -Force
Copy-Item -LiteralPath (Join-Path $repo 'THIRD-PARTY-NOTICES.md')  -Destination (Join-Path $staging 'THIRD-PARTY-NOTICES.md') -Force
Set-Content -Path (Join-Path $staging 'VERSION') -Value $Version -NoNewline -Encoding ascii

$bom = New-Object System.Text.UTF8Encoding($true)

$installCmd = @"
@echo off
rem shortcut-icon-changer Phase 1 installer (per-user, no admin)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
pause
"@
[System.IO.File]::WriteAllText((Join-Path $staging 'Install.cmd'), $installCmd, $bom)

$uninstallCmd = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1" %*
pause
"@
[System.IO.File]::WriteAllText((Join-Path $staging 'Uninstall.cmd'), $uninstallCmd, $bom)

$readme = @"
shortcut-icon-changer (Phase 1)  v$Version
==========================================

.lnk ショートカットのアイコンを右クリックから変更するツールです。
Windows 11 標準機能のみで動作します（追加ランタイム不要・管理者権限不要）。

インストール:
  Install.cmd をダブルクリック（または右クリック→実行）してください。
  アプリは %LOCALAPPDATA%\Programs\ShortcutIconChanger にコピーされ、
  .lnk の右クリックメニューに「アイコンを変更」が追加されます。

使い方:
  任意の .lnk を右クリック →「その他のオプションを表示」→「アイコンを変更」

全アイコンの取得（任意）:
  インストール後、tools\Fetch-FluentEmoji.ps1 で Fluent UI Emoji 約 1,285 種を取得できます。

アンインストール:
  Uninstall.cmd を実行してください。

ライセンス: LICENSE / THIRD-PARTY-NOTICES.md を参照。
"@
[System.IO.File]::WriteAllText((Join-Path $staging 'README.txt'), $readme, $bom)

# --- 2) ZIP --------------------------------------------------------------
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zipPath -Force
Write-Host ("ZIP: {0}" -f $zipPath) -ForegroundColor Green

# --- 3) 自己解凍 EXE (IExpress) -----------------------------------------
if (-not $SkipExe) {
    $iexpress = Join-Path $env:WINDIR 'System32\iexpress.exe'
    if (-not (Test-Path $iexpress)) {
        Write-Warning "iexpress.exe が見つからないため EXE 生成をスキップします。"
    }
    else {
        $sfxSrc = Join-Path ([System.IO.Path]::GetTempPath()) ("sic-sfx-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $sfxSrc | Out-Null

        $zipFileName = Split-Path $zipPath -Leaf
        Copy-Item -LiteralPath $zipPath -Destination (Join-Path $sfxSrc $zipFileName) -Force

        $bootstrap = @"
@echo off
setlocal
set "TMPD=%TEMP%\sic_inst_%RANDOM%%RANDOM%"
mkdir "%TMPD%" >nul 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%~dp0$zipFileName' -DestinationPath '%TMPD%' -Force"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TMPD%\Install.ps1" -Quiet
endlocal
"@
        $bootstrapName = '_sic_bootstrap.cmd'
        [System.IO.File]::WriteAllText((Join-Path $sfxSrc $bootstrapName), $bootstrap, (New-Object System.Text.ASCIIEncoding))

        # IExpress SED（CreateProcess。サブフォルダ非対応のため zip + bootstrap の 2 ファイル構成）
        $sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=ショートカット アイコン変更ツール (Phase 1) をインストールしました。.lnk を右クリックしてご利用ください。
TargetName=$exePath
FriendlyName=Shortcut Icon Changer (Phase 1) v$Version
AppLaunched=cmd /c $bootstrapName
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
FILE0=$bootstrapName
FILE1=$zipFileName
SourceFiles=SourceFiles
[SourceFiles]
SourceFiles0=$sfxSrc\
[SourceFiles0]
%FILE0%=
%FILE1%=
"@
        $sedPath = Join-Path $sfxSrc 'package.sed'
        # IExpress は SED を ANSI（システム既定コードページ）として読み込むため、
        # 日本語を含む SED は UTF-8 ではなく ACP（日本語環境なら cp932）で書き出す。
        # UTF-8 で書くと FinishMessage 等が文字化けする。
        $acp = $null
        try { $acp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -Name ACP -ErrorAction Stop).ACP } catch { }
        $sedEnc = if ($acp) { [System.Text.Encoding]::GetEncoding([int]$acp) } else { [System.Text.Encoding]::Default }
        [System.IO.File]::WriteAllText($sedPath, $sed, $sedEnc)

        if (Test-Path $exePath) { Remove-Item $exePath -Force }
        Write-Host "IExpress で自己解凍 EXE を生成中..."
        & $iexpress /N /Q $sedPath | Out-Null

        if (Test-Path $exePath) {
            Write-Host ("EXE: {0}" -f $exePath) -ForegroundColor Green
        }
        else {
            Write-Warning "EXE の生成に失敗しました（SED: $sedPath を確認してください）。"
        }
        Remove-Item -LiteralPath $sfxSrc -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "完了。" -ForegroundColor Green
Get-ChildItem $OutDir -Filter "$pkgName*" | ForEach-Object {
    Write-Host ("  {0}  ({1:N0} KB)" -f $_.Name, ($_.Length / 1KB))
}
