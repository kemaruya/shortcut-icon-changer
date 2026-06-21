#requires -Version 5.1
<#
.SYNOPSIS
    リポジトリ同梱用のスターターアイコン集 (assets/starter-icons) と
    タグ索引 (icons-index.json) を生成する。
.DESCRIPTION
    Fluent UI Emoji（3D PNG）からショートカット用途に有用なアイコンを匿名ダウンロードして
    assets/starter-icons へ保存し、各アイコンの metadata.json（group / keywords）と
    画像から推定した色調タグをまとめた icons-index.json を生成する。
    メニュー用 assets/app.ico も生成する。
    開発者がスターターセットを更新するためのツール（エンドユーザーは実行不要）。
.PARAMETER KeepExisting
    既存の starter-icons を消さずに不足分のみ追加する（既定は全消去して再生成）。
#>
[CmdletBinding()]
param(
    [switch] $KeepExisting
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

function Get-RawUrl([string] $path) {
    $segs = $path -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }
    return $rawBase + ($segs -join '/')
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
$all3d = $tree.tree | Where-Object { $_.path -match '/3D/.*_3d\.png$' }

# 小文字名 -> 実名/3D パス の索引（大小無視で照合）
$byName = @{}
foreach ($e in $all3d) {
    $name = ($e.path -split '/')[1]
    $lk = $name.ToLowerInvariant()
    if (-not $byName.ContainsKey($lk)) {
        $byName[$lk] = [PSCustomObject]@{ Name = $name; Path = $e.path }
    }
}
Write-Host ("3D アイコン総数: {0}" -f $byName.Count)

if (-not $KeepExisting) {
    Get-ChildItem -LiteralPath $starterDir -Filter *.png -File -ErrorAction SilentlyContinue | Remove-Item -Force
}

function Get-EmojiMetadata([string] $name) {
    $segs = ("assets/$name/metadata.json" -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }
    $url = $rawBase + ($segs -join '/')
    try { return Invoke-RestMethod -Uri $url -Headers $ua -TimeoutSec 30 } catch { return $null }
}

$icons = [ordered]@{}
$got = 0; $skip = 0; $fail = 0
$uniqueWanted = @($wanted | Select-Object -Unique)
$i = 0
foreach ($want in $uniqueWanted) {
    $i++
    $lk = $want.ToLowerInvariant()
    if (-not $byName.ContainsKey($lk)) {
        Write-Warning "見つかりません: $want"
        $fail++
        continue
    }
    $entry = $byName[$lk]
    $realName = $entry.Name
    $safeName = ($realName -replace '[\\/:*?"<>|]', '_')
    $dest = Join-Path $starterDir ("{0}.png" -f $safeName)

    if (-not (Test-Path -LiteralPath $dest)) {
        try {
            Invoke-WebRequest -Uri (Get-RawUrl $entry.Path) -OutFile $dest -UseBasicParsing -TimeoutSec 60
            $got++
        }
        catch {
            Write-Warning ("DL 失敗: {0} ({1})" -f $realName, $_.Exception.Message)
            $fail++
            continue
        }
    }
    else { $skip++ }

    # メタデータ（group / keywords）
    $meta = Get-EmojiMetadata $realName
    $group = if ($meta -and $meta.PSObject.Properties['group']) { [string]$meta.group } else { '' }
    $keywords = @()
    if ($meta -and $meta.PSObject.Properties['keywords'] -and $meta.keywords) { $keywords = @($meta.keywords) }

    # 色調（画像から推定）
    $colors = @()
    try { $colors = @(Get-SicDominantColors -Path $dest -Max 2) } catch { }

    $icons[$safeName] = [ordered]@{
        category   = $group
        categoryJa = (ConvertTo-SicCategoryJa $group)
        colors     = $colors
        keywords   = $keywords
    }

    if ($i % 25 -eq 0) { Write-Host ("  {0}/{1} ..." -f $i, $uniqueWanted.Count) }
}

Write-Host ("スターターアイコン: 取得 {0} / 既存 {1} / 失敗 {2} -> {3}" -f $got, $skip, $fail, $starterDir) -ForegroundColor Green

# --- icons-index.json を出力 ---
$index = [ordered]@{
    version   = 1
    generated = (Get-Date).ToString('s')
    source    = 'microsoft/fluentui-emoji (3D)'
    icons     = $icons
}
$indexPath = Join-Path $starterDir 'icons-index.json'
$json = $index | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($indexPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("索引: {0} 件 -> {1}" -f $icons.Count, $indexPath) -ForegroundColor Green

# --- メニュー用 app.ico を生成（Sparkles -> Star -> 先頭） ---
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

# --- カテゴリ別件数のサマリ ---
Write-Host ""
Write-Host "カテゴリ別:" -ForegroundColor Cyan
$icons.GetEnumerator() |
    Group-Object { $_.Value.categoryJa } |
    Sort-Object Count -Descending |
    ForEach-Object { Write-Host ("  {0,-12} {1}" -f $_.Name, $_.Count) }
