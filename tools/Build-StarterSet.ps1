#requires -Version 5.1
<#
.SYNOPSIS
    リポジトリ同梱用のスターターアイコン集 (assets/starter-icons) と
    タグ索引 (icons-index.json) を生成する。
.DESCRIPTION
    Fluent UI Emoji からショートカット用途に有用なアイコンを匿名ダウンロードして
    assets/starter-icons へ保存し、各アイコンの metadata.json（group / keywords）と
    画像から推定した色調タグ、見た目スタイル（3D / フラット / ハイコントラスト）を
    まとめた icons-index.json を生成する。3D は PNG をそのまま、Flat / High Contrast は
    SVG をビルド時に PNG へラスタライズ（resvg）して同梱する。
    メニュー用 assets/app.ico も生成する。
    開発者がスターターセットを更新するためのツール（エンドユーザーは実行不要）。
.PARAMETER Styles
    取り込むスタイル。既定は 3D / Flat（ハイコントラストは使用率が低いため既定では同梱しない。
    必要なら明示指定で取り込める）。3D は PNG をそのまま、Flat / High Contrast は SVG を
    ビルド時に PNG へラスタライズして同梱する。
.PARAMETER Names
    取り込むアイコン名（Fluent UI Emoji のフォルダ名）。既定は空＝ツリー上の全アイコンを同梱する。
.PARAMETER Clean
    既存の作業フォルダ PNG を全消去して再生成する（既定は不足分のみ追加＝冪等）。
.PARAMETER CacheDir
    ダウンロード/ラスタライズ用の作業フォルダ（PNG キャッシュ・resvg の node_modules・一時 SVG）。
.NOTES
    同梱物は loose PNG ではなく単一の assets/starter-icons/icons.zip に packing する
    （導入時のファイル数・AV スキャン・MSI ハーベストを軽量化）。アプリ (Sic.Core) は
    icons.zip があればそこから、無ければ loose PNG から列挙する。
#>
[CmdletBinding()]
param(
    [ValidateSet('3D', 'Flat', 'High Contrast')]
    [string[]] $Styles = @('3D', 'Flat'),
    [string[]] $Names = @(),
    [switch] $Clean,
    [string] $CacheDir = (Join-Path $env:LOCALAPPDATA 'sic-build')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$starterDir = Join-Path $repo 'assets\starter-icons'
$assetsDir = Join-Path $repo 'assets'
$workDir = Join-Path $CacheDir 'starter-png'   # ダウンロード/ラスタライズ済み PNG の永続キャッシュ（リポジトリ外）
New-Item -ItemType Directory -Force -Path $starterDir | Out-Null
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

Import-Module (Join-Path $repo 'src\phase1\SicCore.psm1') -Force

$ua = @{ 'User-Agent' = 'shortcut-icon-changer'; 'Accept' = 'application/vnd.github+json' }
$rawBase = 'https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/'

# スタイルごとの定義: Fluent UI Emoji のフォルダ名 / ファイル名サフィックス / 拡張子 /
# 表示ラベル（英 / 日）/ 同梱 PNG ファイル名に付ける接尾辞（3D は無印で安定キー）。
$styleSpec = [ordered]@{
    '3D'            = @{ Folder = '3D';            FileSuffix = '_3d';            Ext = 'png'; Label = '3D';            LabelJa = '3D';            DestSuffix = '' }
    'Flat'          = @{ Folder = 'Flat';          FileSuffix = '_flat';          Ext = 'svg'; Label = 'Flat';          LabelJa = 'フラット';      DestSuffix = ' (フラット)' }
    'High Contrast' = @{ Folder = 'High Contrast'; FileSuffix = '_high_contrast'; Ext = 'svg'; Label = 'High Contrast'; LabelJa = 'ハイコントラスト'; DestSuffix = ' (ハイコントラスト)' }
}
$selectedStyles = @($Styles | Select-Object -Unique)
$needsRaster = @($selectedStyles | Where-Object { $styleSpec[$_].Ext -eq 'svg' }).Count -gt 0
$rasterWidth = 256

function Get-RawUrl([string] $path) {
    $segs = $path -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }
    return $rawBase + ($segs -join '/')
}

function Initialize-Resvg {
    <#
    .SYNOPSIS
        SVG ラスタライズ用に Node.js + @resvg/resvg-js を CacheDir に用意し、
        require が解決できるよう NODE_PATH を設定する。
    #>
    param([string] $CacheDir)
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        throw "SVG スタイル（Flat / High Contrast）の取り込みには Node.js が必要です。`n" +
              "https://nodejs.org/ から Node.js をインストールするか、-Styles 3D で実行してください。"
    }
    $nodeModules = Join-Path $CacheDir 'node_modules'
    $resvgDir = Join-Path $nodeModules '@resvg\resvg-js'
    if (-not (Test-Path -LiteralPath $resvgDir)) {
        Write-Host "resvg（SVG ラスタライザ）を準備中... ($CacheDir)"
        New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
        $pkg = Join-Path $CacheDir 'package.json'
        Set-Content -LiteralPath $pkg -Value '{ "name":"sic-build","private":true,"version":"1.0.0" }' -Encoding ascii
        Push-Location $CacheDir
        try {
            & npm install '@resvg/resvg-js@2' --no-audit --no-fund 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" }
            if ($LASTEXITCODE -ne 0) { throw "npm install @resvg/resvg-js が失敗しました (exit=$LASTEXITCODE)。" }
        }
        finally { Pop-Location }
    }
    $env:NODE_PATH = $nodeModules
    return $nodeModules
}

# 取り込むアイコン名。既定（-Names 未指定）はツリー上の全アイコンを対象とする
# （実際の名前一覧は下の $styleMaps 構築後に算出する）。
$uniqueWantedNames = New-Object System.Collections.Generic.List[string]
foreach ($n in @($Names | Select-Object -Unique)) { [void]$uniqueWantedNames.Add($n) }
$wanted = @($Names)

Write-Host "Fluent UI Emoji のファイル一覧を取得中..."
$tree = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/fluentui-emoji/git/trees/main?recursive=1' -Headers $ua -TimeoutSec 60

# スタイルごとに 小文字名 -> 実名/パス の索引を作る（大小無視で照合）
$styleMaps = @{}
foreach ($st in $selectedStyles) {
    $spec = $styleSpec[$st]
    $pat = "/$([regex]::Escape($spec.Folder))/[^/]*$([regex]::Escape($spec.FileSuffix))\.$($spec.Ext)$"
    $m = @{}
    foreach ($e in ($tree.tree | Where-Object { $_.path -match $pat })) {
        $name = ($e.path -split '/')[1]
        $lk = $name.ToLowerInvariant()
        if (-not $m.ContainsKey($lk)) { $m[$lk] = [PSCustomObject]@{ Name = $name; Path = $e.path } }
    }
    $styleMaps[$st] = $m
    Write-Host ("  {0}: {1} 件" -f $st, $m.Count)
}

# -Names 未指定なら、選択スタイルのツリー上に存在する全アイコン名を対象にする（＝全件同梱）。
if ($uniqueWantedNames.Count -eq 0 -and @($wanted).Count -eq 0) {
    $seenName = @{}
    foreach ($st in $selectedStyles) {
        foreach ($v in $styleMaps[$st].Values) {
            $lk2 = $v.Name.ToLowerInvariant()
            if (-not $seenName.ContainsKey($lk2)) { $seenName[$lk2] = $true; [void]$uniqueWantedNames.Add($v.Name) }
        }
    }
    Write-Host ("  対象アイコン（全件）: {0} 件" -f $uniqueWantedNames.Count)
}

if ($Clean) {
    Get-ChildItem -LiteralPath $workDir -Filter *.png -File -ErrorAction SilentlyContinue | Remove-Item -Force
}

# SVG ラスタライズの準備（Flat / High Contrast がある場合のみ）
$svgStageDir = $null
if ($needsRaster) {
    [void](Initialize-Resvg -CacheDir $CacheDir)
    $svgStageDir = Join-Path $CacheDir 'svg'
    New-Item -ItemType Directory -Force -Path $svgStageDir | Out-Null
}

function Get-EmojiMetadata([string] $name) {
    $segs = ("assets/$name/metadata.json" -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }
    $url = $rawBase + ($segs -join '/')
    try { return Invoke-RestMethod -Uri $url -Headers $ua -TimeoutSec 30 } catch { return $null }
}

$metaCache = @{}
$rasterQueue = New-Object System.Collections.Generic.List[object]
$pending = New-Object System.Collections.Generic.List[object]
$dlPng = 0; $skipPng = 0; $dlSvg = 0; $miss = 0
$uniqueWanted = @($uniqueWantedNames)

$i = 0
foreach ($want in $uniqueWanted) {
    $i++
    $lk = $want.ToLowerInvariant()
    foreach ($st in $selectedStyles) {
        $spec = $styleSpec[$st]
        $map = $styleMaps[$st]
        if (-not $map.ContainsKey($lk)) {
            if ($st -eq '3D') { $miss++ }
            continue
        }
        $entry = $map[$lk]
        $realName = $entry.Name
        $safeName = ($realName -replace '[\\/:*?"<>|]', '_')
        $destBase = $safeName + $spec.DestSuffix
        $dest = Join-Path $workDir ("{0}.png" -f $destBase)

        if ($spec.Ext -eq 'png') {
            if (-not (Test-Path -LiteralPath $dest)) {
                try { Invoke-WebRequest -Uri (Get-RawUrl $entry.Path) -OutFile $dest -UseBasicParsing -TimeoutSec 60; $dlPng++ }
                catch { Write-Warning ("DL 失敗(PNG): {0} ({1})" -f $realName, $_.Exception.Message); continue }
            }
            else { $skipPng++ }
        }
        else {
            if (-not (Test-Path -LiteralPath $dest)) {
                $svgPath = Join-Path $svgStageDir ("{0}{1}.svg" -f $safeName, $spec.FileSuffix)
                if (-not (Test-Path -LiteralPath $svgPath) -or (Get-Item -LiteralPath $svgPath).Length -eq 0) {
                    try { Invoke-WebRequest -Uri (Get-RawUrl $entry.Path) -OutFile $svgPath -UseBasicParsing -TimeoutSec 60; $dlSvg++ }
                    catch { Write-Warning ("DL 失敗(SVG): {0} ({1})" -f $realName, $_.Exception.Message); continue }
                }
                $rasterQueue.Add([PSCustomObject]@{ in = $svgPath; out = $dest; width = $rasterWidth })
            }
        }
        $pending.Add([PSCustomObject]@{ Key = $destBase; Dest = $dest; Name = $realName; StyleLabel = $spec.Label; StyleJa = $spec.LabelJa })
    }
    if ($i % 25 -eq 0) { Write-Host ("  {0}/{1} ..." -f $i, $uniqueWanted.Count) }
}

# --- SVG をまとめて PNG にラスタライズ（resvg, 単一 node プロセス） ---
if ($rasterQueue.Count -gt 0) {
    Write-Host ("SVG を PNG にラスタライズ中... {0} 件" -f $rasterQueue.Count)
    $manifestPath = Join-Path $CacheDir 'manifest.json'
    $mjson = $rasterQueue | ConvertTo-Json -Depth 4
    if ($rasterQueue.Count -eq 1) { $mjson = '[' + $mjson + ']' }
    [System.IO.File]::WriteAllText($manifestPath, $mjson, (New-Object System.Text.UTF8Encoding($false)))
    & node (Join-Path $PSScriptRoot 'rasterize.js') $manifestPath
    if ($LASTEXITCODE -ne 0) { Write-Warning "一部の SVG ラスタライズに失敗しました (exit=$LASTEXITCODE)。" }
}

# --- 色調計算 & 索引構築（メタデータは絵文字名ごとにキャッシュ） ---
$icons = [ordered]@{}
$built = 0
foreach ($p in $pending) {
    if (-not (Test-Path -LiteralPath $p.Dest)) { continue }
    if ($metaCache.ContainsKey($p.Name)) { $meta = $metaCache[$p.Name] }
    else { $meta = Get-EmojiMetadata $p.Name; $metaCache[$p.Name] = $meta }
    $group = if ($meta -and $meta.PSObject.Properties['group']) { [string]$meta.group } else { '' }
    $keywords = @()
    if ($meta -and $meta.PSObject.Properties['keywords'] -and $meta.keywords) { $keywords = @($meta.keywords) }
    $colors = @()
    try { $colors = @(Get-SicDominantColors -Path $p.Dest -Max 2) } catch { }
    $icons[$p.Key] = [ordered]@{
        category   = $group
        categoryJa = (ConvertTo-SicCategoryJa $group)
        colors     = $colors
        keywords   = $keywords
        style      = $p.StyleLabel
        styleJa    = $p.StyleJa
    }
    $built++
}

Write-Host ("スターターアイコン: PNG取得 {0} / PNG既存 {1} / SVG取得 {2} / 索引 {3} 件 / 3D不明 {4}" -f $dlPng, $skipPng, $dlSvg, $built, $miss) -ForegroundColor Green

# --- icons-index.json を出力 ---
$srcLabel = 'microsoft/fluentui-emoji (' + ($selectedStyles -join ' / ') + ')'
$index = [ordered]@{
    version   = 2
    generated = (Get-Date).ToString('s')
    source    = $srcLabel
    styles    = @($selectedStyles)
    icons     = $icons
}
$indexPath = Join-Path $starterDir 'icons-index.json'
$json = $index | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($indexPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("索引: {0} 件 -> {1}" -f $icons.Count, $indexPath) -ForegroundColor Green

# --- メニュー用 app.ico を生成（3D の Sparkles -> Star -> 先頭の無印 PNG） ---
$seedCandidates = @('Sparkles', 'Star') + @($icons.Keys)
$iconSeed = $null
foreach ($cand in $seedCandidates) {
    $p = Join-Path $workDir ("{0}.png" -f $cand)
    if (Test-Path $p) { $iconSeed = $p; break }
}
if ($iconSeed) {
    $appIco = Join-Path $assetsDir 'app.ico'
    Convert-ToIco -SourcePath $iconSeed -DestPath $appIco -Sizes @(16, 32, 48, 256) | Out-Null
    Write-Host ("app.ico を生成: {0}（元: {1}）" -f $appIco, (Split-Path $iconSeed -Leaf)) -ForegroundColor Green
}
else {
    Write-Warning "app.ico の元画像が見つからないため生成をスキップしました。"
}

# --- 全 PNG を単一 zip に packing（同梱物のファイル数を 1 に＝導入/AV スキャン/MSI ハーベストを軽量化）---
# PNG は既に圧縮済みのため CompressionLevel は NoCompression（zip 化の目的は連結・ファイル数削減）。
# ZipArchiveMode/CompressionLevel は System.IO.Compression（コア）側にあるため両アセンブリを読み込む。
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = Join-Path $starterDir 'icons.zip'
if (Test-Path -LiteralPath $zipPath) { Remove-Item -Force -LiteralPath $zipPath }
$indexedKeys = @{}
foreach ($k in $icons.Keys) { $indexedKeys[$k] = $true }
$zipCount = 0
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($png in (Get-ChildItem -LiteralPath $workDir -Filter *.png -File | Sort-Object Name)) {
        $key = [System.IO.Path]::GetFileNameWithoutExtension($png.Name)
        if (-not $indexedKeys.ContainsKey($key)) { continue }  # 索引に載るものだけ同梱
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $png.FullName, $png.Name, [System.IO.Compression.CompressionLevel]::NoCompression)
        $zipCount++
    }
}
finally { $zip.Dispose() }
# 旧レイアウトの loose PNG が残っていれば掃除（zip 一本化）。zip 生成成功後に行う。
Get-ChildItem -LiteralPath $starterDir -Filter *.png -File -ErrorAction SilentlyContinue | Remove-Item -Force
$zipMb = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 2)
Write-Host ("icons.zip を生成: {0} 件 / {1} MB -> {2}" -f $zipCount, $zipMb, $zipPath) -ForegroundColor Green

# --- スタイル別 / カテゴリ別件数のサマリ ---
Write-Host ""
Write-Host "スタイル別:" -ForegroundColor Cyan
$icons.GetEnumerator() |
    Group-Object { $_.Value.styleJa } |
    Sort-Object Count -Descending |
    ForEach-Object { Write-Host ("  {0,-14} {1}" -f $_.Name, $_.Count) }
Write-Host ""
Write-Host "カテゴリ別:" -ForegroundColor Cyan
$icons.GetEnumerator() |
    Group-Object { $_.Value.categoryJa } |
    Sort-Object Count -Descending |
    ForEach-Object { Write-Host ("  {0,-12} {1}" -f $_.Name, $_.Count) }
