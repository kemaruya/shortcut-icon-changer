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
    取り込むスタイル。既定は 3D / Flat / High Contrast。3D は PNG をそのまま、
    Flat / High Contrast は SVG をビルド時に PNG へラスタライズして同梱する。
.PARAMETER Clean
    既存の starter-icons を全消去して再生成する（既定は不足分のみ追加＝冪等）。
.PARAMETER CacheDir
    SVG ラスタライズ用の作業フォルダ（resvg の node_modules と一時 SVG を置く）。
#>
[CmdletBinding()]
param(
    [ValidateSet('3D', 'Flat', 'High Contrast')]
    [string[]] $Styles = @('3D', 'Flat', 'High Contrast'),
    [switch] $Clean,
    [string] $CacheDir = (Join-Path $env:LOCALAPPDATA 'sic-build')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$starterDir = Join-Path $repo 'assets\starter-icons'
$assetsDir = Join-Path $repo 'assets'
New-Item -ItemType Directory -Force -Path $starterDir | Out-Null

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

# ショートカット用途に有用な絵文字（名前は Fluent UI Emoji の asset フォルダ名）。
# カテゴリ（顔/動物/食べ物/旅行/物/記号/アクティビティ等）と色調が満遍なく入るよう選定。
$wanted = @(
    # --- 物 / ツール / テック / オフィス ---
    'Rocket', 'Light bulb', 'Gear', 'Laptop', 'Desktop computer', 'Keyboard',
    'Computer mouse', 'Printer', 'Floppy disk', 'Optical disk', 'DVD', 'Camera',
    'Video camera', 'Movie camera', 'Television', 'Telephone', 'Mobile phone',
    'Battery', 'Electric plug', 'Flashlight', 'Candle', 'Magnifying glass tilted left',
    'Microscope', 'Telescope', 'Satellite antenna', 'Hammer', 'Wrench',
    'Hammer and wrench', 'Nut and bolt', 'Screwdriver', 'Toolbox', 'Gear',
    'Magnet', 'Test tube', 'Petri dish', 'Pill', 'Syringe', 'Thermometer',
    'Broom', 'Shopping cart', 'Money bag', 'Credit card', 'Coin', 'Dollar banknote',
    'Briefcase', 'File folder', 'Open file folder', 'Card index dividers',
    'Card file box', 'Clipboard', 'Pushpin', 'Round pushpin', 'Paperclip',
    'Linked paperclips', 'Triangular ruler', 'Straight ruler', 'Scissors', 'Pen',
    'Fountain pen', 'Pencil', 'Crayon', 'Paintbrush', 'Memo', 'Book', 'Books',
    'Blue book', 'Green book', 'Orange book', 'Notebook', 'Ledger', 'Closed book',
    'Open book', 'Newspaper', 'Bookmark', 'Label', 'Calendar', 'Spiral calendar',
    'Spiral notebook', 'Bar chart', 'Chart increasing', 'Chart decreasing',
    'Locked', 'Unlocked', 'Key', 'Old key', 'Locked with key', 'Shield', 'Bell',
    'Megaphone', 'Loudspeaker', 'Musical note', 'Musical notes', 'Headphone',
    'Studio microphone', 'Trophy', 'Crown', 'Gem stone', 'Ring', 'Artist palette',
    'Framed picture', 'Joystick', 'Game die', 'Puzzle piece', 'Teddy bear',
    'Balloon', 'Party popper', 'Wrapped gift', 'Package', 'Postbox', 'Envelope',
    'Inbox tray', 'Outbox tray', 'Scroll', 'Page facing up', 'Receipt', 'Hourglass done',
    'Alarm clock', 'Stopwatch',
    # --- 記号 / ハート ---
    'Red heart', 'Orange heart', 'Yellow heart', 'Green heart', 'Blue heart',
    'Purple heart', 'Brown heart', 'Black heart', 'White heart', 'Sparkling heart',
    'Star', 'Glowing star', 'Sparkles', 'Fire', 'High voltage', 'Collision',
    'Check mark button', 'Cross mark', 'Warning', 'Recycling symbol', 'Heart on fire',
    # --- 動物 / 自然 ---
    'Dog face', 'Cat face', 'Fox', 'Lion', 'Tiger face', 'Unicorn', 'Panda',
    'Koala', 'Penguin', 'Bird', 'Owl', 'Butterfly', 'Honeybee', 'Lady beetle',
    'Snail', 'Turtle', 'Tropical fish', 'Dolphin', 'Whale', 'Octopus', 'Paw prints',
    'Four leaf clover', 'Herb', 'Cactus', 'Palm tree', 'Evergreen tree', 'Seedling',
    'Maple leaf', 'Fallen leaf', 'Sunflower', 'Rose', 'Tulip', 'Blossom', 'Hibiscus',
    'Cherry blossom', 'Mushroom', 'Sun', 'Sun behind cloud', 'Cloud', 'Rainbow',
    'Snowflake', 'Droplet', 'Water wave', 'Crescent moon',
    # --- 食べ物 / 飲み物 ---
    'Red apple', 'Green apple', 'Watermelon', 'Grapes', 'Strawberry', 'Cherries',
    'Peach', 'Banana', 'Pineapple', 'Lemon', 'Avocado', 'Tomato', 'Carrot',
    'Ear of corn', 'Hot pepper', 'Broccoli', 'Bread', 'Croissant', 'Cheese wedge',
    'Hamburger', 'French fries', 'Pizza', 'Hot dog', 'Taco', 'Sushi', 'Bento box',
    'Rice ball', 'Cooked rice', 'Spaghetti', 'Cookie', 'Doughnut', 'Cupcake',
    'Birthday cake', 'Chocolate bar', 'Candy', 'Lollipop', 'Ice cream',
    'Hot beverage', 'Beer mug', 'Wine glass', 'Cocktail glass', 'Tropical drink',
    # --- 旅行 / 場所 / 乗り物 ---
    'Airplane', 'Small airplane', 'Flying saucer', 'Helicopter', 'Automobile',
    'Taxi', 'Bus', 'Police car', 'Fire engine', 'Ambulance', 'Bicycle', 'Motorcycle',
    'Locomotive', 'Bullet train', 'Ship', 'Sailboat', 'Anchor', 'Fuel pump',
    'World map', 'Compass', 'Mountain', 'Snow-capped mountain', 'Volcano', 'Camping',
    'Beach with umbrella', 'Desert island', 'Castle', 'House', 'Houses',
    'Office building', 'School', 'Hospital', 'Bank', 'Hotel', 'Factory', 'Tent',
    'Sunrise', 'Cityscape', 'Fountain', 'Ferris wheel', 'Roller coaster',
    # --- アクティビティ / スポーツ / 音楽 ---
    'Soccer ball', 'Basketball', 'American football', 'Baseball', 'Tennis',
    'Volleyball', 'Bowling', 'Direct hit', 'Video game', 'Kite', 'Ticket',
    'Performing arts', 'Drum', 'Guitar', 'Trumpet', 'Saxophone', 'Violin',
    'Musical keyboard',
    # --- 顔 / 感情 / キャラ ---
    'Grinning face', 'Smiling face with heart-eyes', 'Star-struck',
    'Face with tears of joy', 'Smiling face with sunglasses', 'Thinking face',
    'Partying face', 'Robot', 'Alien', 'Ghost', 'Jack-o-lantern', 'Skull',
    'Clown face', 'Pile of poo',
    # --- 人 / 体 / ジェスチャー ---
    'Waving hand', 'Thumbs up', 'Thumbs down', 'OK hand', 'Victory hand',
    'Folded hands', 'Clapping hands', 'Flexed biceps', 'Eyes', 'Brain',
    # --- 旗 ---
    'Chequered flag', 'Triangular flag', 'Pirate flag', 'Crossed flags'
)

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

if ($Clean) {
    Get-ChildItem -LiteralPath $starterDir -Filter *.png -File -ErrorAction SilentlyContinue | Remove-Item -Force
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
$uniqueWanted = @($wanted | Select-Object -Unique)

$i = 0
foreach ($want in $uniqueWanted) {
    $i++
    $lk = $want.ToLowerInvariant()
    foreach ($st in $selectedStyles) {
        $spec = $styleSpec[$st]
        $map = $styleMaps[$st]
        if (-not $map.ContainsKey($lk)) {
            if ($st -eq '3D') { Write-Warning "見つかりません(3D): $want"; $miss++ }
            continue
        }
        $entry = $map[$lk]
        $realName = $entry.Name
        $safeName = ($realName -replace '[\\/:*?"<>|]', '_')
        $destBase = $safeName + $spec.DestSuffix
        $dest = Join-Path $starterDir ("{0}.png" -f $destBase)

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
    $p = Join-Path $starterDir ("{0}.png" -f $cand)
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
