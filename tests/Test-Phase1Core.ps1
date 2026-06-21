#requires -Version 5.1
<#
.SYNOPSIS
    Phase 1 コア (SicCore.psm1) の自動テスト。
.DESCRIPTION
    UI を伴わない範囲（変換・適用・ライブラリ列挙）を検証する。
    Windows PowerShell 5.1 / pwsh 7 のどちらでも実行可能。
    成功で exit 0、失敗で exit 1。
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Failures = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  [PASS] $msg" -ForegroundColor Green }
    else { Write-Host "  [FAIL] $msg" -ForegroundColor Red; $script:Failures++ }
}

$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$module = Join-Path $repo 'src\phase1\SicCore.psm1'
Write-Host "Importing module: $module"
Import-Module $module -Force

Add-Type -AssemblyName System.Drawing

# テスト用作業ディレクトリ
$work = Join-Path $env:TEMP ("sic-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
Write-Host "Work dir: $work"

try {
    # --- 1) カラフルなテスト PNG を生成 -----------------------------------
    $pngPath = Join-Path $work 'test.png'
    $bmp = New-Object System.Drawing.Bitmap(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.Clear([System.Drawing.Color]::Transparent)
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.Point(0, 0)),
            (New-Object System.Drawing.Point(256, 256)),
            [System.Drawing.Color]::OrangeRed, [System.Drawing.Color]::DodgerBlue)
        $g.FillEllipse($brush, 8, 8, 240, 240)
        $brush.Dispose()
    }
    finally { $g.Dispose() }
    $bmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Assert (Test-Path $pngPath) "テスト PNG を生成した"

    # --- 2) PNG -> ICO 変換 ------------------------------------------------
    $icoPath = Join-Path $work 'test.ico'
    Convert-ToIco -SourcePath $pngPath -DestPath $icoPath -Sizes @(16, 32, 48, 256) | Out-Null
    Assert (Test-Path $icoPath) "ICO ファイルを生成した"

    $bytes = [System.IO.File]::ReadAllBytes($icoPath)
    $reserved = [BitConverter]::ToUInt16($bytes, 0)
    $type = [BitConverter]::ToUInt16($bytes, 2)
    $count = [BitConverter]::ToUInt16($bytes, 4)
    Assert ($reserved -eq 0) "ICO ヘッダ reserved=0"
    Assert ($type -eq 1) "ICO ヘッダ type=1 (icon)"
    Assert ($count -eq 4) "ICO に 4 サイズ含まれる (count=$count)"

    # System.Drawing で読み戻せるか
    $ico = New-Object System.Drawing.Icon($icoPath)
    Assert ($ico -ne $null) "生成した ICO を System.Drawing.Icon で読める"
    $ico.Dispose()

    # 256px エントリは width/height バイトが 0 で表現される
    # 先頭エントリ(16px)の width
    $firstWidth = $bytes[6]
    Assert ($firstWidth -eq 16) "先頭エントリ width=16"

    # --- 3) .ico はそのまま通過 -------------------------------------------
    $icoPath2 = Join-Path $work 'passthrough.ico'
    Convert-ToIco -SourcePath $icoPath -DestPath $icoPath2 | Out-Null
    Assert (Test-Path $icoPath2) ".ico 入力はコピーで通過する"

    # --- 4) SVG は明確に拒否 ----------------------------------------------
    $svgPath = Join-Path $work 'dummy.svg'
    Set-Content -LiteralPath $svgPath -Value '<svg/>' -Encoding UTF8
    $threw = $false
    try { Convert-ToIco -SourcePath $svgPath -DestPath (Join-Path $work 'x.ico') }
    catch { $threw = $true }
    Assert $threw "SVG 入力は明確にエラーになる (Phase 1 未対応)"

    # --- 5) テスト .lnk を作成し、アイコンを適用 --------------------------
    $targetTxt = Join-Path $work 'target.txt'
    Set-Content -LiteralPath $targetTxt -Value 'hello' -Encoding UTF8
    $lnkPath = Join-Path $work 'App.lnk'
    $sh = New-Object -ComObject WScript.Shell
    $sc = $sh.CreateShortcut($lnkPath)
    $sc.TargetPath = $targetTxt
    $sc.Save()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh)
    Assert (Test-Path $lnkPath) "テスト .lnk を作成した"

    # PNG を直接渡す -> 自動で .ico 化されて IconLocation に入るはず
    $result = Set-ShortcutIcon -LnkPath $lnkPath -IconPath $pngPath
    Assert ($result.IconPath.ToLower().EndsWith('.ico')) "PNG 指定が .ico に解決された"
    Assert (Test-Path $result.IconPath) "解決された .ico が存在する"

    # .lnk を読み戻して IconLocation を検証
    $sh2 = New-Object -ComObject WScript.Shell
    $sc2 = $sh2.CreateShortcut($lnkPath)
    $iconLoc = $sc2.IconLocation
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh2)
    Write-Host "  IconLocation = $iconLoc"
    Assert ($iconLoc.ToLower().Contains('.ico')) ".lnk の IconLocation が .ico を指す"
    Assert ($iconLoc.EndsWith(',0')) "IconLocation に索引 ,0 が付く"

    # キャッシュ再利用（2回目は同じパス）
    $result2 = Set-ShortcutIcon -LnkPath $lnkPath -IconPath $pngPath
    Assert ($result2.IconPath -eq $result.IconPath) "同一ソースはキャッシュが再利用される"

    # --- 6) Get-IconLibrary -----------------------------------------------
    $lib = Get-IconLibrary
    Write-Host ("  ライブラリ件数 = {0}" -f (@($lib).Count))
    Assert ($true) "Get-IconLibrary が例外なく動作する"
}
finally {
    Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue
}

Write-Host ""
if ($script:Failures -eq 0) {
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
    exit 0
}
else {
    Write-Host ("FAILED: {0} assertion(s)" -f $script:Failures) -ForegroundColor Red
    exit 1
}
