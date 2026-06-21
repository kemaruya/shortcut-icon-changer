#requires -Version 5.1
<#
.SYNOPSIS
  Phase 2 (ネイティブ WPF + WiX MSI) のビルド スクリプト。

.DESCRIPTION
  Sic.App (net48 WPF) を Release ビルドし、exe / Sic.Core.dll / assets を
  ステージへ集約してから WiX 6 で perUser MSI を生成する。
  追加ランタイム不要 (.NET Framework 4.8 は Windows 11 in-box / MSI は msiexec のみ)。

.PARAMETER Configuration
  ビルド構成 (既定: Release)。

.PARAMETER RunTests
  指定時、MSI 生成前に xUnit (Sic.Core.Tests) を実行する。

.EXAMPLE
  pwsh build\Build-Phase2.ps1 -RunTests
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [switch]$RunTests
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$Phase2     = Join-Path $RepoRoot 'src\phase2'
$AppProj    = Join-Path $Phase2  'Sic.App\Sic.App.csproj'
$TestProj   = Join-Path $Phase2  'Sic.Core.Tests\Sic.Core.Tests.csproj'
$Wxs        = Join-Path $RepoRoot 'installer\wix\Package.wxs'
$AssetsDir  = Join-Path $RepoRoot 'assets\starter-icons'
$DistDir    = Join-Path $RepoRoot 'dist'
$StageDir   = Join-Path $DistDir  '_stage'

function Resolve-MSBuild {
    # 既知の動作実績パス (Enterprise: dotnet SDK 経由で Microsoft.NET.Sdk を解決可能) を最優先。
    # BuildTools は .NET SDK リゾルバを欠くため除外する。
    $enterprise = 'C:\Program Files\Microsoft Visual Studio\18\Enterprise\MSBuild\Current\Bin\MSBuild.exe'
    if (Test-Path $enterprise) { return $enterprise }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $p = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild `
                 -find 'MSBuild\**\Bin\MSBuild.exe' |
                 Where-Object { $_ -notmatch 'BuildTools' } | Select-Object -First 1
        if ($p -and (Test-Path $p)) { return $p }
    }
    throw 'Microsoft.NET.Sdk を解決できる MSBuild.exe が見つかりません (Visual Studio が必要です)。'
}

function Get-ProductVersion {
    $vfile = Join-Path $RepoRoot 'VERSION'
    $v = (Get-Content $vfile -Raw).Trim()
    $parts = $v.Split('.')
    while ($parts.Count -lt 3) { $parts += '0' }
    return ('{0}.{1}.{2}.0' -f $parts[0], $parts[1], $parts[2])
}

Write-Host '== Shortcut Icon Changer / Phase 2 build ==' -ForegroundColor Cyan
$msbuild = Resolve-MSBuild
$ver     = Get-ProductVersion
Write-Host "MSBuild       : $msbuild"
Write-Host "ProductVersion: $ver"

# 1) ビルド
Write-Host "`n[1/4] Building Sic.App ($Configuration)..." -ForegroundColor Yellow
& $msbuild $AppProj -t:Restore,Build -p:Configuration=$Configuration -nologo -v:m
if ($LASTEXITCODE -ne 0) { throw "ビルドに失敗しました ($LASTEXITCODE)" }

# 2) テスト (任意)
if ($RunTests) {
    Write-Host "`n[2/4] Running unit tests..." -ForegroundColor Yellow
    & dotnet test $TestProj -c $Configuration --nologo
    if ($LASTEXITCODE -ne 0) { throw "テストに失敗しました ($LASTEXITCODE)" }
} else {
    Write-Host "`n[2/4] Skipping tests (-RunTests 未指定)" -ForegroundColor DarkGray
}

# 3) ステージング
Write-Host "`n[3/4] Staging payload..." -ForegroundColor Yellow
$binDir = Join-Path $Phase2 "Sic.App\bin\$Configuration\net48"
if (-not (Test-Path $binDir)) { throw "ビルド出力が見つかりません: $binDir" }

if (Test-Path $StageDir) { Remove-Item -Recurse -Force $StageDir }
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

# 必要ファイルのみ (pdb / xml は除外)
$payload = @(
    'ShortcutIconChanger.exe',
    'ShortcutIconChanger.exe.config',
    'Sic.Core.dll'
)
foreach ($f in $payload) {
    $src = Join-Path $binDir $f
    if (-not (Test-Path $src)) {
        if ($f -like '*.config') { continue }  # config は無くても可
        throw "必要ファイルが見つかりません: $src"
    }
    Copy-Item $src (Join-Path $StageDir $f) -Force
}

# スターター アイコン (icons.zip 同梱 + index)
$stageAssets = Join-Path $StageDir 'assets\starter-icons'
New-Item -ItemType Directory -Force -Path $stageAssets | Out-Null
Copy-Item (Join-Path $AssetsDir '*') $stageAssets -Recurse -Force
$zipFile = Join-Path $stageAssets 'icons.zip'
if (Test-Path $zipFile) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zr = [System.IO.Compression.ZipFile]::OpenRead($zipFile)
    try { $iconCount = $zr.Entries.Count } finally { $zr.Dispose() }
    $zipMb = [math]::Round((Get-Item $zipFile).Length / 1MB, 2)
    Write-Host "  staged files  : $((Get-ChildItem $StageDir -Recurse -File).Count) (icons.zip: $iconCount 件 / $zipMb MB)"
}
else {
    $iconCount = (Get-ChildItem $stageAssets -Recurse -File -Include *.png, *.ico).Count
    Write-Host "  staged files  : $((Get-ChildItem $StageDir -Recurse -File).Count) (icons: $iconCount)"
}

# 4) MSI 生成
Write-Host "`n[4/4] Building MSI with WiX..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$msi = Join-Path $DistDir ("ShortcutIconChanger-{0}-perUser.msi" -f ((Get-Content (Join-Path $RepoRoot 'VERSION') -Raw).Trim()))

& wix build $Wxs -d "StageDir=$StageDir" -d "ProductVersion=$ver" -arch x64 -o $msi
if ($LASTEXITCODE -ne 0) { throw "WiX ビルドに失敗しました ($LASTEXITCODE)" }

$size = [math]::Round((Get-Item $msi).Length / 1MB, 2)
Write-Host "`nOK: $msi ($size MB)" -ForegroundColor Green
