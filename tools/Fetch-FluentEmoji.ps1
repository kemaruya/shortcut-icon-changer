#requires -Version 5.1
<#
.SYNOPSIS
    Microsoft Fluent UI Emoji（3D スタイル PNG）をアイコンライブラリに取得する。
.DESCRIPTION
    Fluent UI Emoji リポジトリ (microsoft/fluentui-emoji) の 3D スタイル PNG を
    匿名（トークン不要）でダウンロードし、ローカルのアイコンライブラリに保存する。
    取得した PNG はピッカーで選択でき、適用時に自動で .ico 化される。

    注: リポジトリの "Flat" スタイルは SVG のみで、ラスタ PNG は 3D スタイルだけが
    提供されている。Phase 1 は in-box の手段で SVG をラスタライズできないため、
    色彩豊かな 3D PNG を採用している。
.PARAMETER Destination
    保存先フォルダ。既定は %LOCALAPPDATA%\ShortcutIconChanger\library。
.PARAMETER Filter
    名前の部分一致フィルタ（例: 'face', 'arrow'）。
.PARAMETER Limit
    取得件数の上限（0 = 全件、約 1,285 件）。
.PARAMETER Quiet
    進捗表示を抑制する。
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\tools\Fetch-FluentEmoji.ps1
.EXAMPLE
    .\tools\Fetch-FluentEmoji.ps1 -Filter 'arrow' -Limit 50
#>
[CmdletBinding()]
param(
    [string] $Destination,
    [string] $Filter = '',
    [int]    $Limit = 0,
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Destination) {
    $Destination = Join-Path $env:LOCALAPPDATA 'ShortcutIconChanger\library'
}
if (-not (Test-Path $Destination)) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
}

$ua = @{ 'User-Agent' = 'shortcut-icon-changer'; 'Accept' = 'application/vnd.github+json' }
$rawBase = 'https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/'

function Get-RawUrl([string] $path) {
    $segs = $path -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }
    return $rawBase + ($segs -join '/')
}

Write-Host "Fluent UI Emoji のファイル一覧を取得中..."
try {
    $tree = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/fluentui-emoji/git/trees/main?recursive=1' -Headers $ua -TimeoutSec 60
}
catch {
    throw "ファイル一覧の取得に失敗しました（GitHub API のレート制限の可能性があります。しばらく待って再実行してください）: $($_.Exception.Message)"
}

$entries = $tree.tree | Where-Object { $_.path -match '/3D/.*_3d\.png$' }

# assets/<Name>/3D/<file>_3d.png -> 表示名 = <Name>
$items = foreach ($e in $entries) {
    $parts = $e.path -split '/'
    [PSCustomObject]@{
        Name = $parts[1]
        Path = $e.path
    }
}

if ($Filter) {
    $items = $items | Where-Object { $_.Name -like "*$Filter*" }
}
$items = @($items | Sort-Object Name)
if ($Limit -gt 0 -and $items.Count -gt $Limit) {
    $items = $items[0..($Limit - 1)]
}

Write-Host ("対象: {0} 件 -> {1}" -f $items.Count, $Destination)

$ok = 0; $skip = 0; $fail = 0; $i = 0
foreach ($it in $items) {
    $i++
    $safeName = ($it.Name -replace '[\\/:*?"<>|]', '_')
    $dest = Join-Path $Destination ("{0}.png" -f $safeName)
    if (Test-Path -LiteralPath $dest) { $skip++; continue }
    try {
        Invoke-WebRequest -Uri (Get-RawUrl $it.Path) -OutFile $dest -UseBasicParsing -TimeoutSec 60
        $ok++
    }
    catch {
        $fail++
        if (-not $Quiet) { Write-Warning ("失敗: {0} ({1})" -f $it.Name, $_.Exception.Message) }
        continue
    }
    if (-not $Quiet -and ($i % 50 -eq 0)) {
        Write-Host ("  {0}/{1} ..." -f $i, $items.Count)
    }
}

Write-Host ""
Write-Host ("完了: 取得 {0} / スキップ(既存) {1} / 失敗 {2}" -f $ok, $skip, $fail) -ForegroundColor Green
Write-Host ("ライブラリ: {0}" -f $Destination)
