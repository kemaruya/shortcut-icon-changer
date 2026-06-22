#requires -Version 5.1
<#
.SYNOPSIS
  Microsoft Store 配布用の完全(自己完結) MSIX をビルドする。

.DESCRIPTION
  Sic.App(net48 WPF)を Release ビルドし、IExplorerCommand ハンドラを SIC_STORE 定義付きで
  ビルドし(reparent-to-explorer を無効化)、exe / config / Sic.Core.dll / Sic.ShellExt.dll /
  starter-icons(icons.zip)/ ロゴ / トークン置換済み AppxManifest.xml を 1 つのコンテンツ
  ディレクトリへ集約し、makeappx pack で .msix を生成する。

  Store 提出用(既定): 署名しない。Partner Center にアップロードすると Microsoft が
    信頼された証明書で再署名する。-IdentityName / -Publisher / -PublisherDisplay には
    Partner Center で予約したアプリの Identity を渡す。

  ローカル/VM 検証用(-SelfSign): CurrentUser\My の自己署名コード署名証明書(既定 CN=kemaruya)で
    署名する。サイドロード前に証明書を LocalMachine の信頼ストアへ取り込む必要がある(管理者)。
    Publisher は証明書サブジェクトと完全一致が必須。

.PARAMETER Version          パッケージ バージョン(既定: VERSION から x.y.z.0)。
.PARAMETER IdentityName     Identity/@Name(既定: kemaruya.ShortcutIconChanger)。Store では予約名。
.PARAMETER Publisher        Identity/@Publisher(既定: CN=kemaruya)。Store では発行者 ID(例 CN=XXXX...)。
.PARAMETER PublisherDisplay PublisherDisplayName(既定: kemaruya)。
.PARAMETER SelfSign         指定時、自己署名証明書で署名(ローカル/VM 検証用)。
.PARAMETER Subject          署名証明書のサブジェクト(既定: $Publisher)。-SelfSign 時のみ使用。
.PARAMETER Configuration    ビルド構成(既定: Release)。
.PARAMETER OutDir           .msix の出力先(既定: dist)。
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$IdentityName    = 'kemaruya.ShortcutIconChanger',
    [string]$Publisher       = 'CN=kemaruya',
    [string]$PublisherDisplay = 'kemaruya',
    [switch]$SelfSign,
    [string]$Subject,
    [string]$Configuration   = 'Release',
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$StoreDir    = $PSScriptRoot
$RepoRoot    = (Resolve-Path (Join-Path $StoreDir '..\..')).Path
$Phase2      = Join-Path $RepoRoot 'src\phase2'
$AppProj     = Join-Path $Phase2  'Sic.App\Sic.App.csproj'
$AssetsDir   = Join-Path $RepoRoot 'assets\starter-icons'
$ShellExtDir = Join-Path $RepoRoot 'src\shellext'
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'dist' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (-not $Subject) { $Subject = $Publisher }

function Resolve-MSBuild {
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

function Find-SdkTool([string]$name) {
    $roots = @("${env:ProgramFiles(x86)}\Windows Kits\10\bin", "$env:ProgramFiles\Windows Kits\10\bin")
    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { continue }
        $hit = Get-ChildItem $r -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^10\.' } | Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName "x64\$name" } |
            Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    throw "$name が見つかりません。Windows SDK が必要です。"
}

function New-Logo([int]$w, [int]$h, [string]$path) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::FromArgb(0,0,0,0))
    $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 10, 91, 211))
    $pad = [Math]::Max(1, [int]($w * 0.08))
    $rect = New-Object System.Drawing.Rectangle($pad, $pad, ($w-2*$pad), ($h-2*$pad))
    $g.FillRectangle($bg, $rect)
    $fg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $cx = $w/2.0; $cy = $h/2.0; $r = $w*0.22
    $pts = @(
        (New-Object System.Drawing.PointF($cx, ($cy-$r))),
        (New-Object System.Drawing.PointF(($cx+$r), $cy)),
        (New-Object System.Drawing.PointF($cx, ($cy+$r))),
        (New-Object System.Drawing.PointF(($cx-$r), $cy))
    )
    $g.FillPolygon($fg, $pts)
    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

Write-Host '== Shortcut Icon Changer / Store MSIX build ==' -ForegroundColor Cyan

# --- バージョン (x.y.z.0) ---
if (-not $Version) {
    $verRaw = (Get-Content (Join-Path $RepoRoot 'VERSION') -Raw).Trim()
    $parts = $verRaw.Split('.'); while ($parts.Count -lt 3) { $parts += '0' }
    $Version = ('{0}.{1}.{2}.0' -f $parts[0], $parts[1], $parts[2])
}
if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw "バージョン形式が不正です: $Version (a.b.c.d 期待)" }
Write-Host "Version        : $Version"
Write-Host "Identity Name  : $IdentityName"
Write-Host "Publisher      : $Publisher"
Write-Host ("Sign mode      : {0}" -f ($(if ($SelfSign) { "self-sign ($Subject)" } else { 'unsigned (Store re-signs)' })))

$msbuild  = Resolve-MSBuild
$makeappx = Find-SdkTool 'makeappx.exe'

# 1) Sic.App ビルド
Write-Host "`n[1/5] Building Sic.App ($Configuration)..." -ForegroundColor Yellow
& $msbuild $AppProj -t:Restore,Build -p:Configuration=$Configuration -nologo -v:m
if ($LASTEXITCODE -ne 0) { throw "Sic.App のビルドに失敗しました ($LASTEXITCODE)" }
$binDir = Join-Path $Phase2 "Sic.App\bin\$Configuration\net48"
if (-not (Test-Path $binDir)) { throw "ビルド出力が見つかりません: $binDir" }

# 2) IExplorerCommand ハンドラ (SIC_STORE: reparent 無効)
Write-Host "`n[2/5] Building shell extension (SIC_STORE, no reparent)..." -ForegroundColor Yellow
$shellTmp = Join-Path $env:TEMP ("sic-storeshell-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $shellTmp | Out-Null
& (Join-Path $ShellExtDir 'Build-ShellExt.ps1') -OutDir $shellTmp -Defines 'SIC_STORE'
if ($LASTEXITCODE -ne 0) { throw "Sic.ShellExt.dll (Store) のビルドに失敗しました ($LASTEXITCODE)" }
$storeDll = Join-Path $shellTmp 'Sic.ShellExt.dll'
if (-not (Test-Path $storeDll)) { throw "Store 版 Sic.ShellExt.dll が生成されませんでした: $storeDll" }

# 3) コンテンツ ディレクトリ組み立て
Write-Host "`n[3/5] Staging package content..." -ForegroundColor Yellow
$content = Join-Path $env:TEMP ("sic-store-" + [guid]::NewGuid().ToString('N'))
$assets  = Join-Path $content 'Assets'
$starter = Join-Path $assets  'starter-icons'
New-Item -ItemType Directory -Force -Path $starter | Out-Null

# manifest (トークン置換)
$manifest = Get-Content (Join-Path $StoreDir 'AppxManifest.xml') -Raw
$manifest = $manifest -replace '__VERSION__',          $Version
$manifest = $manifest -replace '__IDENTITY_NAME__',    $IdentityName
$manifest = $manifest -replace '__PUBLISHER__',        $Publisher
$manifest = $manifest -replace '__PUBLISHER_DISPLAY__', $PublisherDisplay
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $content 'AppxManifest.xml'), $manifest, $utf8NoBom)

# バイナリ (pdb / xml は除外)
foreach ($f in @('ShortcutIconChanger.exe', 'ShortcutIconChanger.exe.config', 'Sic.Core.dll')) {
    $src = Join-Path $binDir $f
    if (-not (Test-Path $src)) {
        if ($f -like '*.config') { continue }
        throw "必要ファイルが見つかりません: $src"
    }
    Copy-Item $src (Join-Path $content $f) -Force
}
Copy-Item $storeDll (Join-Path $content 'Sic.ShellExt.dll') -Force

# starter-icons (icons.zip + index)。アプリは Assets\starter-icons / assets\starter-icons 双方を探索する。
Copy-Item (Join-Path $AssetsDir '*') $starter -Recurse -Force

# ロゴ生成
Add-Type -AssemblyName System.Drawing
New-Logo 50  50  (Join-Path $assets 'StoreLogo.png')
New-Logo 44  44  (Join-Path $assets 'Square44x44Logo.png')
New-Logo 150 150 (Join-Path $assets 'Square150x150Logo.png')

$fileCount = (Get-ChildItem $content -Recurse -File).Count
$zipFile = Join-Path $starter 'icons.zip'
if (Test-Path $zipFile) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zr = [System.IO.Compression.ZipFile]::OpenRead($zipFile)
    try { $iconCount = $zr.Entries.Count } finally { $zr.Dispose() }
    Write-Host ("  staged        : {0} files (icons.zip: {1} entries)" -f $fileCount, $iconCount)
} else {
    Write-Host ("  staged        : {0} files" -f $fileCount)
}

# 4) makeappx pack (manifest スキーマ検証あり)
Write-Host "`n[4/5] makeappx pack..." -ForegroundColor Yellow
$msix = Join-Path $OutDir ("ShortcutIconChanger-Store-$Version.msix")
if (Test-Path $msix) { Remove-Item $msix -Force }
& $makeappx pack /d $content /p $msix /o
if ($LASTEXITCODE -ne 0) { throw "makeappx に失敗しました (exit $LASTEXITCODE)。" }

# 5) 署名 (任意・ローカル/VM 検証用)
Write-Host "`n[5/5] Signing..." -ForegroundColor Yellow
if ($SelfSign) {
    $signtool = Find-SdkTool 'signtool.exe'
    $cert = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object {
            $_.Subject -eq $Subject -and $_.HasPrivateKey -and
            ($_.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.3')
        } |
        Sort-Object NotAfter -Descending | Select-Object -First 1
    if (-not $cert) { throw "コード署名証明書 '$Subject' が CurrentUser\My にありません。先に New-SelfSignedCert.ps1 を実行してください。" }
    if ($Publisher -ne $Subject) { Write-Warning "Publisher ($Publisher) と署名サブジェクト ($Subject) が不一致です。Add-AppxPackage が拒否します。" }
    Write-Host "  cert          : $($cert.Subject) (拇印 $($cert.Thumbprint))"
    & $signtool sign /fd SHA256 /sha1 $cert.Thumbprint /v $msix
    if ($LASTEXITCODE -ne 0) { throw "signtool に失敗しました (exit $LASTEXITCODE)。" }
} else {
    Write-Host "  unsigned (Partner Center へアップロードすると Microsoft が再署名します)" -ForegroundColor DarkGray
}

# 後始末
Remove-Item $content  -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $shellTmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host ("OK: {0} ({1:N0} bytes)" -f $msix, (Get-Item $msix).Length) -ForegroundColor Green
$msix
