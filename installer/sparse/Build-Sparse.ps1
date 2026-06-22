#requires -Version 5.1
<#
.SYNOPSIS
  モダン コンテキスト メニュー用のスパース MSIX をビルドし、自己署名証明書で署名する。

.DESCRIPTION
  manifest(AppxManifest.xml)とロゴのみを含む sparse パッケージを作成する。
  アプリ本体(exe/Sic.ShellExt.dll/assets)は MSI 導入先に置き、登録時に
  Add-AppxPackage -ExternalLocation で外部参照する(Enable-ModernMenu.ps1)。

  手順: ロゴ生成 → manifest の __VERSION__ 置換 → makeappx pack → signtool sign。
  署名は CurrentUser\My 上の証明書(既定 CN=kemaruya)を拇印参照で使用(pfx 不要)。
  事前に New-SelfSignedCert.ps1 を実行して証明書を用意しておくこと。

.PARAMETER Version
  パッケージ バージョン。既定はリポジトリ ルートの VERSION から x.y.z.0 を生成。

.PARAMETER Subject
  署名に使う証明書のサブジェクト。manifest の Publisher と一致。既定 "CN=kemaruya"。

.PARAMETER OutDir
  .msix の出力先。既定 dist。
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Subject = 'CN=kemaruya',
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$SparseDir = $PSScriptRoot
$RepoRoot  = (Resolve-Path (Join-Path $SparseDir '..\..')).Path
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'dist' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# --- バージョン (x.y.z.0) ---
if (-not $Version) {
    $verRaw = (Get-Content (Join-Path $RepoRoot 'VERSION') -Raw).Trim()
    $Version = "$verRaw.0"
}
if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw "バージョン形式が不正です: $Version (a.b.c.d 期待)" }
Write-Host "バージョン: $Version"

# --- 署名証明書 ---
$cert = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object {
        $_.Subject -eq $Subject -and $_.HasPrivateKey -and
        ($_.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.3')
    } |
    Sort-Object NotAfter -Descending | Select-Object -First 1
if (-not $cert) { throw "コード署名証明書 '$Subject' が CurrentUser\My にありません。先に New-SelfSignedCert.ps1 を実行してください。" }
Write-Host "署名証明書: $($cert.Subject) (拇印 $($cert.Thumbprint))"

# --- SDK ツール (makeappx / signtool) ---
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
$makeappx = Find-SdkTool 'makeappx.exe'
$signtool = Find-SdkTool 'signtool.exe'

# --- コンテンツ ディレクトリ組み立て ---
$content = Join-Path $env:TEMP ("sic-sparse-" + [guid]::NewGuid().ToString('N'))
$assets  = Join-Path $content 'Assets'
New-Item -ItemType Directory -Force -Path $assets | Out-Null

# manifest (__VERSION__ 置換)
$manifest = Get-Content (Join-Path $SparseDir 'AppxManifest.xml') -Raw
$manifest = $manifest -replace '__VERSION__', $Version
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $content 'AppxManifest.xml'), $manifest, $utf8NoBom)

# ロゴ生成 (System.Drawing・同梱の System.Drawing のみ使用)
Add-Type -AssemblyName System.Drawing
function New-Logo([int]$w, [int]$h, [string]$path) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::FromArgb(0,0,0,0))
    $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 10, 91, 211))
    $pad = [Math]::Max(1, [int]($w * 0.08))
    $rect = New-Object System.Drawing.Rectangle($pad, $pad, ($w-2*$pad), ($h-2*$pad))
    $g.FillRectangle($bg, $rect)
    # 中央に白い菱形(アイコン変更の含意・簡素)
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
New-Logo 50  50  (Join-Path $assets 'StoreLogo.png')
New-Logo 44  44  (Join-Path $assets 'Square44x44Logo.png')
New-Logo 150 150 (Join-Path $assets 'Square150x150Logo.png')

# --- pack ---
$msix = Join-Path $OutDir ("ShortcutIconChanger-ModernMenu-$Version.msix")
if (Test-Path $msix) { Remove-Item $msix -Force }
Write-Host "makeappx pack ..."
& $makeappx pack /d $content /p $msix /o /nv
if ($LASTEXITCODE -ne 0) { throw "makeappx に失敗しました (exit $LASTEXITCODE)。" }

# --- sign (拇印参照・自己署名のためタイムスタンプなし) ---
Write-Host "signtool sign ..."
& $signtool sign /fd SHA256 /sha1 $cert.Thumbprint /v $msix
if ($LASTEXITCODE -ne 0) { throw "signtool に失敗しました (exit $LASTEXITCODE)。" }

Remove-Item $content -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("OK: {0} ({1:N0} bytes)" -f $msix, (Get-Item $msix).Length) -ForegroundColor Green
$msix
