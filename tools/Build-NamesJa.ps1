#requires -Version 5.1
<#
.SYNOPSIS
    スターターアイコンの日本語表示名 (nameJa) を生成し、icons-index.json を v3 へ更新する。

.DESCRIPTION
    各アイコンの英語名 (= Fluent UI Emoji のフォルダ名) から Fluent の metadata.json を引いて
    絵文字グリフを取得し、Unicode CLDR の日本語注釈 (annotations / annotationsDerived) で
    グリフ→日本語短縮名 (tts) に対応付ける。結果を:
      - assets/starter-icons/names-ja.json … 英語ベース名→日本語名 (レビュー用の素データ)
      - assets/starter-icons/icons-index.json … 各エントリへ nameEn / nameJa を付与し version=3
    の両方へ反映する。アプリ (Sic.Core) は icons-index.json の nameJa を読む。

    icons-index.json は ConvertFrom/To-Json を通さず、既存の体裁を保ったまま正規表現で
    nameEn / nameJa の 2 行のみを各エントリへ挿入する（差分を最小化し、PS 5.1 の JSON
    シリアライザの癖を回避するため）。再実行しても二重挿入しない（冪等）。
    開発者がスターターセットを更新するためのツール（エンドユーザーは実行不要・要ネットワーク）。

.PARAMETER CacheDir
    Fluent metadata.json のキャッシュ置き場（既定: %LOCALAPPDATA%\sic-build）。
#>
[CmdletBinding()]
param(
    [string] $CacheDir = (Join-Path $env:LOCALAPPDATA 'sic-build')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo       = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$starterDir = Join-Path $repo 'assets\starter-icons'
$indexPath  = Join-Path $starterDir 'icons-index.json'
$namesPath  = Join-Path $starterDir 'names-ja.json'
$metaDir    = Join-Path $CacheDir 'meta'
New-Item -ItemType Directory -Force -Path $metaDir | Out-Null

$ua      = @{ 'User-Agent' = 'shortcut-icon-changer' }
$rawBase = 'https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/'
$styleSuffixes = @(' (フラット)', ' (ハイコントラスト)')

function Get-BaseName([string] $name) {
    foreach ($suf in $styleSuffixes) {
        if ($name.EndsWith($suf)) { return $name.Substring(0, $name.Length - $suf.Length) }
    }
    return $name
}

function Invoke-WithRetry([scriptblock] $Action, [int] $Tries = 3) {
    for ($t = 1; $t -le $Tries; $t++) {
        try { return & $Action }
        catch { if ($t -eq $Tries) { throw }; Start-Sleep -Milliseconds (250 * $t) }
    }
}

function ConvertTo-JsonStringLiteral($s) {
    if ($null -eq $s) { return 'null' }
    $e = ([string]$s).Replace('\', '\\').Replace('"', '\"')
    return '"' + $e + '"'
}

# 1) CLDR 日本語注釈（本体＋派生）を取得し glyph -> tts 辞書を作る
function Get-CldrAnnotations([string] $url) {
    $a = Invoke-WithRetry { Invoke-RestMethod -Uri $url -Headers $ua -TimeoutSec 90 }
    # 本体は { annotations: { annotations: {...} } }、派生は { annotationsDerived: { annotations: {...} } }
    $root = if ($a.PSObject.Properties['annotations']) { $a.annotations } else { $a.annotationsDerived }
    return $root.annotations
}
Write-Host 'CLDR 日本語注釈を取得中...'
$cldrMain  = Get-CldrAnnotations 'https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-full/annotations/ja/annotations.json'
$cldrDeriv = Get-CldrAnnotations 'https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-derived-full/annotationsDerived/ja/annotations.json'
Write-Host ("  本体 {0} 件 / 派生 {1} 件" -f @($cldrMain.PSObject.Properties).Count, @($cldrDeriv.PSObject.Properties).Count)

function Resolve-JaName([string] $glyph) {
    if ([string]::IsNullOrEmpty($glyph)) { return $null }
    $cands = New-Object System.Collections.Generic.List[string]
    $cands.Add($glyph)
    # 表示用バリエーション セレクタ (U+FE0F/U+FE0E) を除去した候補も試す。
    # 注意: PowerShell の -eq/-ne は既定で照合順 (バリエーション セレクタを無視) のため
    #       "❤" -ne "❤️" が False になる。必ず序数 (Ordinal) で差分判定する。
    $stripped = ($glyph -replace "[\uFE0F\uFE0E]", '')
    if (-not [string]::Equals($stripped, $glyph, [System.StringComparison]::Ordinal)) { $cands.Add($stripped) }
    foreach ($c in $cands) {
        foreach ($mp in @($cldrMain, $cldrDeriv)) {
            $prop = $mp.PSObject.Properties[$c]
            if ($prop -and $prop.Value -and $prop.Value.tts) { return ($prop.Value.tts | Select-Object -First 1) }
        }
    }
    return $null
}

function Get-Glyph([string] $baseName) {
    $cacheF = Join-Path $metaDir (($baseName -replace '[\\/:*?"<>|]', '_') + '.json')
    $md = $null
    if (Test-Path -LiteralPath $cacheF) {
        try { $md = Get-Content -LiteralPath $cacheF -Raw | ConvertFrom-Json } catch { $md = $null }
    }
    if (-not $md) {
        $segs = ("assets/$baseName/metadata.json" -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }
        $url = $rawBase + ($segs -join '/')
        try {
            $md = Invoke-WithRetry { Invoke-RestMethod -Uri $url -Headers $ua -TimeoutSec 30 }
            $md | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cacheF -Encoding UTF8
        } catch { return $null }
    }
    if ($md -and $md.PSObject.Properties['glyph']) { return $md.glyph }
    return $null
}

# 2) index 生テキストを読み、アイコン キーを正規表現で抽出（JSON パーサを通さない）
Write-Host 'icons-index.json を読み込み中...'
$indexText = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
$keyRx = [regex]'(?m)^\s{18}"(?<k>(?:[^"\\]|\\.)*)":\s+\{'
$iconKeys = @($keyRx.Matches($indexText) | ForEach-Object { $_.Groups['k'].Value })
$bases = @($iconKeys | ForEach-Object { Get-BaseName $_ } | Select-Object -Unique)
Write-Host ("  アイコン {0} 件 / ユニーク ベース名 {1} 件" -f $iconKeys.Count, $bases.Count)

# 3) ベース名 -> 日本語名
$nameJaMap = @{}
$hit = 0; $miss = 0; $i = 0
foreach ($b in $bases) {
    $i++
    $glyph = Get-Glyph $b
    $ja = Resolve-JaName $glyph
    if ($ja) { $nameJaMap[$b] = $ja; $hit++ }
    else { $miss++; Write-Warning ("日本語名なし: {0} (glyph='{1}')" -f $b, $glyph) }
    if ($i % 50 -eq 0) { Write-Host ("  {0}/{1} (hit={2} miss={3})" -f $i, $bases.Count, $hit, $miss) }
}
Write-Host ("日本語名: {0}/{1} 解決 (miss={2})" -f $hit, $bases.Count, $miss)

# 4a) names-ja.json（レビュー用素データ・キー順ソート）
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('{')
$sortedBases = @($nameJaMap.Keys | Sort-Object)
for ($n = 0; $n -lt $sortedBases.Count; $n++) {
    $k = $sortedBases[$n]
    $comma = if ($n -lt $sortedBases.Count - 1) { ',' } else { '' }
    [void]$sb.AppendLine(("  {0}: {1}{2}" -f (ConvertTo-JsonStringLiteral $k), (ConvertTo-JsonStringLiteral $nameJaMap[$k]), $comma))
}
[void]$sb.Append('}')
[System.IO.File]::WriteAllText($namesPath, $sb.ToString(), $utf8NoBom)
Write-Host "書き出し: $namesPath ($($sortedBases.Count) 件)"

# 4b) icons-index.json へ nameEn / nameJa を各エントリの先頭 (category の前) へ挿入。
#     既存の体裁を保持し、再実行しても二重挿入しない（先頭が既に nameEn のものは一致しない）。
$injectRx = [regex]'(?m)^(?<ind1>\s{18})"(?<k>(?:[^"\\]|\\.)*)"(?<sep>:\s+)\{(?<eol>\r?\n)(?<ind2>\s+)"category"'
$injected = $injectRx.Matches($indexText).Count
$evaluator = {
    param($m)
    $key  = $m.Groups['k'].Value
    $ind1 = $m.Groups['ind1'].Value
    $sep  = $m.Groups['sep'].Value
    $eol  = $m.Groups['eol'].Value
    $ind2 = $m.Groups['ind2'].Value
    $base = Get-BaseName $key
    $ja   = if ($nameJaMap.ContainsKey($base)) { $nameJaMap[$base] } else { $null }
    $enLit = ConvertTo-JsonStringLiteral $base
    $jaLit = ConvertTo-JsonStringLiteral $ja
    return ($ind1 + '"' + $key + '"' + $sep + '{' + $eol +
            $ind2 + '"nameEn":  ' + $enLit + ',' + $eol +
            $ind2 + '"nameJa":  ' + $jaLit + ',' + $eol +
            $ind2 + '"category"')
}
$newText = $injectRx.Replace($indexText, $evaluator)

# version 2 -> 3、generated 更新
$newText = [regex]::Replace($newText, '"version":\s*2', '"version":  3', 1)
$newText = [regex]::Replace($newText, '"generated":\s*"[^"]*"', ('"generated":  "{0}"' -f (Get-Date).ToString('s')), 1)

[System.IO.File]::WriteAllText($indexPath, $newText, $utf8NoBom)
Write-Host "更新: $indexPath (version=3, nameEn/nameJa を $injected エントリへ挿入)"
