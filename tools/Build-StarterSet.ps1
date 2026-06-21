#requires -Version 5.1
<#
.SYNOPSIS
    リポジトリ同梱用のスターターアイコン集 (assets/starter-icons) を生成する。
.DESCRIPTION
    Fluent UI Emoji（3D PNG）からショートカット用途に有用な少数のアイコンを
    匿名ダウンロードして assets/starter-icons へ保存し、メニュー用 assets/app.ico も生成する。
    開発者がスターターセットを更新するためのツール（エンドユーザーは実行不要）。
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$starterDir = Join-Path $repo 'assets\starter-icons'
$assetsDir = Join-Path $repo 'assets'
New-Item -ItemType Directory -Force -Path $starterDir | Out-Null

Import-Module (Join-Path $repo 'src\phase1\SicCore.psm1') -Force

$ua = @{ 'User-Agent' = 'shortcut-icon-changer'; 'Accept' = 'application/vnd.github+json' }
$rawBase = 'https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/'

function Get-RawUrl([string] $path) {
    $segs = $path -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }
    return $rawBase + ($segs -join '/')
}

# ショートカット用途に有用な絵文字（名前は Fluent UI Emoji の asset フォルダ名）
$wanted = @(
    'Rocket', 'Star', 'Fire', 'Light bulb', 'Gear', 'Laptop', 'Desktop computer',
    'File folder', 'Open file folder', 'Card index dividers', 'Package',
    'Hammer and wrench', 'Wrench', 'Books', 'Blue book', 'Notebook', 'Memo',
    'Spiral calendar', 'Bar chart', 'Chart increasing', 'Magnifying glass tilted left',
    'Globe showing Europe-Africa', 'Locked', 'Key', 'Shield', 'Gem stone',
    'Artist palette', 'Floppy disk', 'Camera', 'Envelope', 'House', 'Red heart',
    'Sparkles', 'Trophy', 'Bell', 'Pushpin', 'Paperclip', 'Wrench', 'Toolbox', 'Robot'
)

Write-Host "Fluent UI Emoji のファイル一覧を取得中..."
$tree = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/fluentui-emoji/git/trees/main?recursive=1' -Headers $ua -TimeoutSec 60
$all3d = $tree.tree | Where-Object { $_.path -match '/3D/.*_3d\.png$' }

# 名前 -> path の索引
$byName = @{}
foreach ($e in $all3d) {
    $name = ($e.path -split '/')[1]
    if (-not $byName.ContainsKey($name)) { $byName[$name] = $e.path }
}

$got = New-Object System.Collections.Generic.List[string]
foreach ($name in ($wanted | Select-Object -Unique)) {
    if (-not $byName.ContainsKey($name)) {
        Write-Warning "見つかりません: $name"
        continue
    }
    $dest = Join-Path $starterDir ("{0}.png" -f $name)
    try {
        Invoke-WebRequest -Uri (Get-RawUrl $byName[$name]) -OutFile $dest -UseBasicParsing -TimeoutSec 60
        $got.Add($name)
        Write-Host ("  OK  {0}" -f $name)
    }
    catch {
        Write-Warning ("失敗: {0} ({1})" -f $name, $_.Exception.Message)
    }
}

Write-Host ("スターターアイコン: {0} 件 -> {1}" -f $got.Count, $starterDir) -ForegroundColor Green

# メニュー用 app.ico を生成（Star を採用、無ければ先頭）
$iconSeed = Join-Path $starterDir 'Star.png'
if (-not (Test-Path $iconSeed) -and $got.Count -gt 0) {
    $iconSeed = Join-Path $starterDir ("{0}.png" -f $got[0])
}
if (Test-Path $iconSeed) {
    $appIco = Join-Path $assetsDir 'app.ico'
    Convert-ToIco -SourcePath $iconSeed -DestPath $appIco -Sizes @(16, 32, 48, 256) | Out-Null
    Write-Host ("app.ico を生成: {0}" -f $appIco) -ForegroundColor Green
}
else {
    Write-Warning "app.ico の元画像が見つからないため生成をスキップしました。"
}
