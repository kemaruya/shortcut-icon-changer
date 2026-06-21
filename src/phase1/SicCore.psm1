#requires -Version 5.1
<#
.SYNOPSIS
    shortcut-icon-changer のコア機能（Phase 1）。

.DESCRIPTION
    Windows 11 同梱機能のみで動作する .lnk アイコン変更ロジック。
    - WScript.Shell COM による IconLocation 書き換え
    - System.Drawing (GDI+) によるマルチサイズ PNG -> ICO 変換
    - SHChangeNotify によるシェルアイコンキャッシュ更新
    Windows PowerShell 5.1 互換で記述している（pwsh 7 でも動作）。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

if (-not ('Sic.NativeShell' -as [type])) {
    Add-Type -Namespace 'Sic' -Name 'NativeShell' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int wEventId, uint uFlags, System.IntPtr dwItem1, System.IntPtr dwItem2);
'@
}

# Fluent UI Emoji の group（英語）-> 表示用カテゴリ（日本語）。
$script:SicCategoryJa = @{
    'Smileys & Emotion' = '顔・感情'
    'People & Body'     = '人・体'
    'Animals & Nature'  = '動物・自然'
    'Food & Drink'      = '食べ物'
    'Travel & Places'   = '旅行・場所'
    'Activities'        = 'アクティビティ'
    'Objects'           = '物'
    'Symbols'           = '記号'
    'Flags'             = '旗'
    'Component'         = '部品'
}

# 色調タグの表示順（UI のコンボボックス並びにも使う）。
$script:SicToneOrder = @('赤', '橙', '黄', '緑', '青', '紫', '桃', '茶', '白', '灰', '黒', '多色')

function ConvertTo-SicCategoryJa {
    [CmdletBinding()]
    param([string] $Group)
    if ($Group -and $script:SicCategoryJa.ContainsKey($Group)) { return $script:SicCategoryJa[$Group] }
    return $Group
}

function Get-SicToneOrder {
    [CmdletBinding()]
    param()
    return $script:SicToneOrder
}

function Get-SicRoot {
    [CmdletBinding()]
    param()
    $root = Join-Path $env:LOCALAPPDATA 'ShortcutIconChanger'
    if (-not (Test-Path $root)) { New-Item -ItemType Directory -Force -Path $root | Out-Null }
    return $root
}

function Get-SicLibraryPath {
    [CmdletBinding()]
    param()
    $p = Join-Path (Get-SicRoot) 'library'
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
    return $p
}

function Get-SicCachePath {
    [CmdletBinding()]
    param()
    $p = Join-Path (Get-SicRoot) 'cache'
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
    return $p
}

function Get-SicStarterPath {
    [CmdletBinding()]
    param()
    # 同梱スターターアイコンの場所をレイアウト非依存で解決する。
    #   インストール後 : <installDir>\SicCore.psm1      -> <installDir>\assets\starter-icons
    #   リポジトリ     : <repo>\src\phase1\SicCore.psm1 -> <repo>\assets\starter-icons
    $candidates = @(
        (Join-Path $PSScriptRoot 'assets\starter-icons'),       # インストール後レイアウト
        (Join-Path $PSScriptRoot '..\..\assets\starter-icons'), # リポジトリレイアウト
        (Join-Path $PSScriptRoot '..\assets\starter-icons')     # 予備
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    return $null
}

function Get-SicIconIndex {
    <#
    .SYNOPSIS
        スターター/ライブラリ フォルダの icons-index.json を読み込み、名前 -> メタデータの
        ハッシュテーブルを返す（タグ: category/categoryJa/colors/keywords）。
    #>
    [CmdletBinding()]
    param()

    $map = @{}
    $files = @()
    $sp = Get-SicStarterPath; if ($sp) { $files += (Join-Path $sp 'icons-index.json') }
    $lp = Get-SicLibraryPath; if ($lp) { $files += (Join-Path $lp 'icons-index.json') }

    foreach ($f in $files) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        try {
            $json = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch { continue }
        if (-not $json -or -not $json.icons) { continue }
        foreach ($p in $json.icons.PSObject.Properties) {
            if (-not $map.ContainsKey($p.Name)) { $map[$p.Name] = $p.Value }
        }
    }
    return $map
}

function Get-IconLibrary {
    <#
    .SYNOPSIS
        利用可能なアイコン（同梱スターター + 取得済みライブラリ）を列挙する。
    .OUTPUTS
        PSCustomObject[] : Name, Path, Source('starter'|'library'), Extension,
                           Category, CategoryJa, Colors(string[]), Keywords(string[])
    #>
    [CmdletBinding()]
    param(
        [string[]] $Extensions = @('.ico', '.png')
    )

    $idx = Get-SicIconIndex
    $results = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)

    $sources = @(
        @{ Path = (Get-SicStarterPath); Source = 'starter' },
        @{ Path = (Get-SicLibraryPath); Source = 'library' }
    )

    foreach ($s in $sources) {
        if (-not $s.Path -or -not (Test-Path $s.Path)) { continue }
        Get-ChildItem -Path $s.Path -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
            ForEach-Object {
                $key = $_.BaseName
                if ($seen.Add($key)) {
                    $meta = $idx[$key]
                    $category = ''; $categoryJa = ''
                    $colors = @(); $keywords = @()
                    if ($meta) {
                        if ($meta.PSObject.Properties['category'])   { $category   = [string]$meta.category }
                        if ($meta.PSObject.Properties['categoryJa']) { $categoryJa = [string]$meta.categoryJa }
                        if ($meta.PSObject.Properties['colors']   -and $meta.colors)   { $colors   = @($meta.colors) }
                        if ($meta.PSObject.Properties['keywords'] -and $meta.keywords) { $keywords = @($meta.keywords) }
                    }
                    if (-not $categoryJa -and $category) { $categoryJa = ConvertTo-SicCategoryJa $category }
                    $results.Add([PSCustomObject]@{
                        Name       = $_.BaseName
                        Path       = $_.FullName
                        Source     = $s.Source
                        Extension  = $_.Extension.ToLowerInvariant()
                        Category   = $category
                        CategoryJa = $categoryJa
                        Colors     = $colors
                        Keywords   = $keywords
                    })
                }
            }
    }

    return $results | Sort-Object Name
}

function Convert-ToIco {
    <#
    .SYNOPSIS
        画像ファイルをマルチサイズ .ico に変換する。
    .DESCRIPTION
        .ico はそのまま返す（変換不要）。.png/.jpg/.bmp/.gif は System.Drawing で
        指定サイズにリサイズし、各サイズを PNG エンコードして ICO コンテナに格納する。
        .svg は Phase 1 では未対応。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SourcePath,
        [Parameter(Mandatory)] [string] $DestPath,
        [int[]] $Sizes = @(16, 32, 48, 256)
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "ソース画像が見つかりません: $SourcePath"
    }
    $ext = [System.IO.Path]::GetExtension($SourcePath).ToLowerInvariant()

    if ($ext -eq '.ico') {
        Copy-Item -LiteralPath $SourcePath -Destination $DestPath -Force
        return $DestPath
    }
    if ($ext -eq '.svg') {
        throw "SVG は Phase 1 では未対応です（Phase 1.5 で対応予定）。.ico または .png を指定してください。"
    }

    $src = $null
    $images = New-Object System.Collections.Generic.List[byte[]]
    try {
        $src = New-Object System.Drawing.Bitmap($SourcePath)
        foreach ($size in ($Sizes | Sort-Object -Unique)) {
            $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $g.Clear([System.Drawing.Color]::Transparent)
                $g.DrawImage($src, 0, 0, $size, $size)
            }
            finally { $g.Dispose() }

            $ms = New-Object System.IO.MemoryStream
            try {
                $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                $images.Add($ms.ToArray())
            }
            finally { $ms.Dispose(); $bmp.Dispose() }
        }
    }
    finally {
        if ($src) { $src.Dispose() }
    }

    Write-IcoFile -DestPath $DestPath -PngImages $images -Sizes ($Sizes | Sort-Object -Unique)
    return $DestPath
}

function Write-IcoFile {
    <#
    .SYNOPSIS
        PNG エンコード済み画像群から .ico ファイル（PNG 圧縮エントリ）を生成する。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $DestPath,
        [Parameter(Mandatory)] [System.Collections.Generic.List[byte[]]] $PngImages,
        [Parameter(Mandatory)] [int[]] $Sizes
    )

    $count = $PngImages.Count
    $fs = New-Object System.IO.FileStream($DestPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    $bw = New-Object System.IO.BinaryWriter($fs)
    try {
        # ICONDIR
        $bw.Write([UInt16]0)      # reserved
        $bw.Write([UInt16]1)      # type = icon
        $bw.Write([UInt16]$count) # count

        # 画像データはディレクトリの後ろに連続配置
        $dataOffset = 6 + (16 * $count)

        for ($i = 0; $i -lt $count; $i++) {
            $size = $Sizes[$i]
            $bytes = $PngImages[$i]
            $dim = if ($size -ge 256) { 0 } else { $size }

            # ICONDIRENTRY
            $bw.Write([byte]$dim)            # width  (0 = 256)
            $bw.Write([byte]$dim)            # height (0 = 256)
            $bw.Write([byte]0)              # color count
            $bw.Write([byte]0)              # reserved
            $bw.Write([UInt16]1)           # planes
            $bw.Write([UInt16]32)          # bit count
            $bw.Write([UInt32]$bytes.Length) # bytes in resource
            $bw.Write([UInt32]$dataOffset) # image offset
            $dataOffset += $bytes.Length
        }

        foreach ($bytes in $PngImages) {
            $bw.Write($bytes)
        }
        $bw.Flush()
    }
    finally {
        $bw.Dispose()
        $fs.Dispose()
    }
}

function Get-SicCachedIcon {
    <#
    .SYNOPSIS
        画像ソースをキャッシュ済み .ico に解決する（無ければ生成）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SourcePath
    )

    $full = (Resolve-Path -LiteralPath $SourcePath).Path
    $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
    if ($ext -in @('.ico', '.exe', '.dll')) {
        return $full
    }

    $item = Get-Item -LiteralPath $full
    $sig = "{0}|{1}|{2}" -f $full, $item.Length, $item.LastWriteTimeUtc.Ticks
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try {
        $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sig))
    }
    finally { $sha.Dispose() }
    $hash = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    $dest = Join-Path (Get-SicCachePath) ("{0}.ico" -f $hash)

    if (-not (Test-Path -LiteralPath $dest)) {
        Convert-ToIco -SourcePath $full -DestPath $dest | Out-Null
    }
    return $dest
}

function Get-SicDominantColors {
    <#
    .SYNOPSIS
        画像の代表的な色調（日本語タグ）を推定して返す。
    .DESCRIPTION
        画像を縮小サンプリングし、各ピクセルを色相/彩度/明度から
        赤/橙/黄/緑/青/紫/桃/茶/白/灰/黒 に分類して、支配的な色調を最大 $Max 件返す。
        色味が乏しい場合は無彩色（白/灰/黒）の優勢色を返す。複数の有彩色が強い場合は '多色' を先頭に付ける。
    .OUTPUTS
        string[] : 色調タグ（例: @('青','白')）。判定不能時は空配列。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [int] $Max = 2,
        [int] $SampleSize = 32
    )

    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    $src = $null; $bmp = $null; $g = $null
    try {
        $full = (Resolve-Path -LiteralPath $Path).Path
        $src = New-Object System.Drawing.Bitmap($full)
        $bmp = New-Object System.Drawing.Bitmap($SampleSize, $SampleSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.DrawImage($src, 0, 0, $SampleSize, $SampleSize)
    }
    catch {
        if ($g) { $g.Dispose() }; if ($bmp) { $bmp.Dispose() }; if ($src) { $src.Dispose() }
        return @()
    }
    finally {
        if ($g) { $g.Dispose() }
        if ($src) { $src.Dispose() }
    }

    $counts = @{}
    $opaque = 0
    try {
        for ($y = 0; $y -lt $SampleSize; $y++) {
            for ($x = 0; $x -lt $SampleSize; $x++) {
                $c = $bmp.GetPixel($x, $y)
                if ($c.A -lt 128) { continue }
                $opaque++
                $h = $c.GetHue()
                $s = $c.GetSaturation()
                $l = $c.GetBrightness()

                if ($s -lt 0.18) {
                    if ($l -gt 0.85) { $tone = '白' }
                    elseif ($l -lt 0.18) { $tone = '黒' }
                    else { $tone = '灰' }
                }
                elseif (($h -ge 15 -and $h -lt 45) -and $l -lt 0.4) { $tone = '茶' }
                elseif ($h -lt 15 -or $h -ge 345) { $tone = '赤' }
                elseif ($h -lt 45) { $tone = '橙' }
                elseif ($h -lt 70) { $tone = '黄' }
                elseif ($h -lt 165) { $tone = '緑' }
                elseif ($h -lt 265) { $tone = '青' }
                elseif ($h -lt 295) { $tone = '紫' }
                else { $tone = '桃' }

                if ($counts.ContainsKey($tone)) { $counts[$tone]++ } else { $counts[$tone] = 1 }
            }
        }
    }
    finally { $bmp.Dispose() }

    if ($opaque -eq 0) { return @() }

    $colorKeys = @('赤', '橙', '黄', '緑', '青', '紫', '桃', '茶')
    $coloredTotal = 0
    foreach ($k in $colorKeys) { if ($counts.ContainsKey($k)) { $coloredTotal += $counts[$k] } }

    $result = New-Object System.Collections.Generic.List[string]
    if ($coloredTotal -ge ($opaque * 0.12)) {
        $sorted = @($counts.GetEnumerator() | Where-Object { $colorKeys -contains $_.Key } | Sort-Object Value -Descending)
        $strong = @($sorted | Where-Object { $_.Value -ge ($coloredTotal * 0.20) })
        $added = 0
        foreach ($e in $sorted) {
            if ($added -ge $Max) { break }
            if ($e.Value -ge ($coloredTotal * 0.20)) { [void]$result.Add($e.Key); $added++ }
        }
        if ($added -eq 0 -and $sorted.Count -gt 0) { [void]$result.Add($sorted[0].Key) }
        if ($strong.Count -ge 3) { $result.Insert(0, '多色') }
    }
    else {
        $neutral = @($counts.GetEnumerator() | Where-Object { @('白', '灰', '黒') -contains $_.Key } | Sort-Object Value -Descending)
        if ($neutral.Count -gt 0) { [void]$result.Add($neutral[0].Key) }
    }

    return $result.ToArray()
}

function Update-ShellIconCache {
    [CmdletBinding()]
    param()
    $SHCNE_ASSOCCHANGED = 0x08000000
    $SHCNF_IDLIST = 0x0000
    [Sic.NativeShell]::SHChangeNotify($SHCNE_ASSOCCHANGED, [uint32]$SHCNF_IDLIST, [IntPtr]::Zero, [IntPtr]::Zero)
}

function Set-ShortcutIcon {
    <#
    .SYNOPSIS
        指定したショートカット (.lnk) のアイコンを変更する。
    .PARAMETER LnkPath
        対象の .lnk ファイル。
    .PARAMETER IconPath
        アイコンファイル (.ico/.exe/.dll/.png/...)。png 等は自動で .ico 化される。
    .PARAMETER Index
        アイコン索引（.exe/.dll/複数アイコン .ico 用）。既定 0。
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $LnkPath,
        [Parameter(Mandatory)] [string] $IconPath,
        [int] $Index = 0
    )

    if (-not (Test-Path -LiteralPath $LnkPath)) {
        throw "ショートカットが見つかりません: $LnkPath"
    }
    $lnkFull = (Resolve-Path -LiteralPath $LnkPath).Path
    if ([System.IO.Path]::GetExtension($lnkFull).ToLowerInvariant() -ne '.lnk') {
        throw "対象は .lnk ファイルではありません: $lnkFull"
    }
    if (-not (Test-Path -LiteralPath $IconPath)) {
        throw "アイコンファイルが見つかりません: $IconPath"
    }

    $resolvedIcon = Get-SicCachedIcon -SourcePath $IconPath

    if ($PSCmdlet.ShouldProcess($lnkFull, "IconLocation を '$resolvedIcon,$Index' に設定")) {
        $shell = New-Object -ComObject WScript.Shell
        try {
            $sc = $shell.CreateShortcut($lnkFull)
            $sc.IconLocation = "{0},{1}" -f $resolvedIcon, $Index
            $sc.Save()
        }
        finally {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
        Update-ShellIconCache
    }

    return [PSCustomObject]@{
        LnkPath  = $lnkFull
        IconPath = $resolvedIcon
        Index    = $Index
    }
}

function Reset-ShortcutIcon {
    <#
    .SYNOPSIS
        指定したショートカット (.lnk) のアイコンを既定（ターゲット本来のアイコン）に戻す。
    .DESCRIPTION
        IconLocation を空パス・索引 0（",0"）に設定して保存し、独自アイコン指定を解除する。
        WScript.Shell は空文字 "" を拒否するため、空パス + ",0" を用いる。
    .PARAMETER LnkPath
        対象の .lnk ファイル。
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $LnkPath
    )

    if (-not (Test-Path -LiteralPath $LnkPath)) {
        throw "ショートカットが見つかりません: $LnkPath"
    }
    $lnkFull = (Resolve-Path -LiteralPath $LnkPath).Path
    if ([System.IO.Path]::GetExtension($lnkFull).ToLowerInvariant() -ne '.lnk') {
        throw "対象は .lnk ファイルではありません: $lnkFull"
    }

    if ($PSCmdlet.ShouldProcess($lnkFull, "IconLocation を既定に戻す")) {
        $shell = New-Object -ComObject WScript.Shell
        try {
            $sc = $shell.CreateShortcut($lnkFull)
            $sc.IconLocation = ",0"
            $sc.Save()
        }
        finally {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
        Update-ShellIconCache
    }

    return [PSCustomObject]@{
        LnkPath  = $lnkFull
        IconPath = ''
        Index    = 0
    }
}

Export-ModuleMember -Function @(
    'Get-SicRoot', 'Get-SicLibraryPath', 'Get-SicCachePath', 'Get-SicStarterPath',
    'Get-SicIconIndex', 'ConvertTo-SicCategoryJa', 'Get-SicToneOrder',
    'Get-IconLibrary', 'Convert-ToIco', 'Get-SicCachedIcon', 'Get-SicDominantColors',
    'Update-ShellIconCache', 'Set-ShortcutIcon', 'Reset-ShortcutIcon'
)
