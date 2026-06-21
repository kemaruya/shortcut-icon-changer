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
    # モジュールからの相対: <repo>\src\phase1\SicCore.psm1 -> <repo>\assets\starter-icons
    $candidate = Join-Path $PSScriptRoot '..\..\assets\starter-icons'
    if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    return $null
}

function Get-IconLibrary {
    <#
    .SYNOPSIS
        利用可能なアイコン（同梱スターター + 取得済みライブラリ）を列挙する。
    .OUTPUTS
        PSCustomObject[] : Name, Path, Source('starter'|'library'), Extension
    #>
    [CmdletBinding()]
    param(
        [string[]] $Extensions = @('.ico', '.png')
    )

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
                    $results.Add([PSCustomObject]@{
                        Name      = $_.BaseName
                        Path      = $_.FullName
                        Source    = $s.Source
                        Extension = $_.Extension.ToLowerInvariant()
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

Export-ModuleMember -Function @(
    'Get-SicRoot', 'Get-SicLibraryPath', 'Get-SicCachePath', 'Get-SicStarterPath',
    'Get-IconLibrary', 'Convert-ToIco', 'Get-SicCachedIcon',
    'Update-ShellIconCache', 'Set-ShortcutIcon'
)
