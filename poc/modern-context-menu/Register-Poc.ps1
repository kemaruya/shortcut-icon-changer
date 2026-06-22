#requires -Version 5.1
<#
.SYNOPSIS
  Windows 11 モダン コンテキスト メニュー PoC を「開発者モードの未署名ルース登録」で導入する。

.DESCRIPTION
  - Sic.App (net48 WPF) の Release 出力 + ビルド済み Sic.ShellExt.dll + AppxManifest + ロゴを
    1 つのステージ フォルダ(=パッケージ ルート)へ集約し、Add-AppxPackage -Register で登録する。
  - 署名・管理者権限は不要。開発者モード(設定 > プライバシーとセキュリティ > 開発者向け)が前提。
  - 登録後、.lnk を右クリックするとモダン メニュー(第一階層)に「アイコンを変更」が出る。

.PARAMETER StageDir
  パッケージ ルートとして使うステージ フォルダ。既定 C:\TEMP\sic-poc-stage。

.PARAMETER RestartExplorer
  指定時、登録直後に explorer.exe を再起動してメニュー キャッシュを確実に更新する。
#>
[CmdletBinding()]
param(
    [string]$StageDir = 'C:\TEMP\sic-poc-stage',
    [switch]$RestartExplorer
)

$ErrorActionPreference = 'Stop'
$PocDir   = $PSScriptRoot
$RepoRoot = (Resolve-Path (Join-Path $PocDir '..\..')).Path
$Release  = Join-Path $RepoRoot 'src\phase2\Sic.App\bin\Release\net48'
$RepoAssets = Join-Path $RepoRoot 'assets\starter-icons'
$Dll      = Join-Path $PocDir 'Sic.ShellExt.dll'
$Manifest = Join-Path $PocDir 'AppxManifest.xml'
$Logos    = Join-Path $PocDir 'Assets'

Write-Host '== Shortcut Icon Changer / モダン コンテキスト メニュー PoC 登録 ==' -ForegroundColor Cyan

# 開発者モード確認 (プロセス ビット数に依存しない 64bit ビュー読み)
$base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
$sub  = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock')
$dev  = if ($sub) { $sub.GetValue('AllowDevelopmentWithoutDevLicense') } else { $null }
if ($dev -ne 1) {
    Write-Warning '開発者モードが無効です。未署名ルース登録には開発者モードが必要です。'
    Write-Warning '設定 > プライバシーとセキュリティ > 開発者向け > 開発者モード を ON にしてください。'
    throw '開発者モードが必要です。'
}

# 前提物の存在確認
if (-not (Test-Path $Dll))      { throw "Sic.ShellExt.dll がありません。先に Build-ShellExt.ps1 を実行してください: $Dll" }
if (-not (Test-Path $Manifest)) { throw "AppxManifest.xml がありません: $Manifest" }
if (-not (Test-Path $Release)) {
    throw "Sic.App の Release 出力がありません。先に build\Build-Phase2.ps1 を実行してください: $Release"
}

# ステージ初期化
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

# 1) アプリ本体(exe / Sic.Core.dll / *.config)をコピー
Write-Host "[1/5] Release 出力をステージへコピー..."
Copy-Item (Join-Path $Release '*') -Destination $StageDir -Recurse -Force

# 1b) スターター アイコン(icons.zip / index / names-ja)を exe 隣の assets\starter-icons へ
Write-Host "[2/5] スターター アイコン(icons.zip ほか)をステージへコピー..."
if (-not (Test-Path $RepoAssets)) { throw "assets\starter-icons がありません: $RepoAssets" }
$stageStarter = Join-Path $StageDir 'assets\starter-icons'
New-Item -ItemType Directory -Force -Path $stageStarter | Out-Null
Copy-Item (Join-Path $RepoAssets '*') -Destination $stageStarter -Recurse -Force

# 2) シェル拡張 DLL とマニフェストをパッケージ ルートへ
Write-Host "[3/5] Sic.ShellExt.dll / AppxManifest.xml を配置..."
Copy-Item $Dll      -Destination $StageDir -Force
Copy-Item $Manifest -Destination $StageDir -Force

# 3) パッケージ ロゴを Assets へ(アプリ アセットとは別ディレクトリ)
Write-Host "[4/5] パッケージ ロゴを Assets へ配置..."
$stageAssets = Join-Path $StageDir 'Assets'
New-Item -ItemType Directory -Force -Path $stageAssets | Out-Null
Copy-Item (Join-Path $Logos '*.png') -Destination $stageAssets -Force

# 4) 既存登録があれば解除してから登録
Write-Host "[5/5] パッケージを登録 (Add-AppxPackage -Register)..."
Get-AppxPackage -Name 'kemaruya.ShortcutIconChanger.ContextMenuPoC' -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-AppxPackage $_.PackageFullName -ErrorAction SilentlyContinue }

Add-AppxPackage -Register (Join-Path $StageDir 'AppxManifest.xml')

$pkg = Get-AppxPackage -Name 'kemaruya.ShortcutIconChanger.ContextMenuPoC'
if ($pkg) {
    Write-Host "`nOK: 登録しました。" -ForegroundColor Green
    Write-Host "  PackageFullName : $($pkg.PackageFullName)"
    Write-Host "  InstallLocation : $($pkg.InstallLocation)"
    Write-Host "  StageDir        : $StageDir"
    Write-Host "`n.lnk ファイルを右クリックし、モダン メニュー(第一階層)に「アイコンを変更」が出るか確認してください。"
    Write-Host '見えない場合は -RestartExplorer 付きで再実行するか、エクスプローラーを再起動してください。'
} else {
    throw '登録に失敗しました。Get-AppxPackage で確認してください。'
}

if ($RestartExplorer) {
    Write-Host "`nexplorer.exe を再起動します..."
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}
