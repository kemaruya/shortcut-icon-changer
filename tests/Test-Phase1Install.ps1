#requires -Version 5.1
<#
.SYNOPSIS
    Phase 1 のインストール/アンインストール・ランチャー・ピッカー構築の自動テスト。
.DESCRIPTION
    - Install.ps1 を一時インストール先で実行し、ファイル配置とレジストリ verb を検証
    - Launch-IconPicker.ps1 -IconPath で UI なしのアイコン適用を検証
    - IconPicker の Show-SicIconPicker -NoShow を STA で構築できることを検証
    - アイコンのクリック発火で選択パスが Window.Tag に入ることを検証 (回帰テスト)
    - Uninstall.ps1 で後始末
    実行は powershell.exe (5.1) を推奨。成功で exit 0。
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Failures = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  [PASS] $msg" -ForegroundColor Green }
    else { Write-Host "  [FAIL] $msg" -ForegroundColor Red; $script:Failures++ }
}

$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$phase1 = Join-Path $repo 'src\phase1'
$psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$verbKey = 'HKCU:\Software\Classes\lnkfile\shell\sic.ChangeIcon'

$work = Join-Path $env:TEMP ("sic-itest-" + [guid]::NewGuid().ToString('N'))
$installDir = Join-Path $work 'Install'
New-Item -ItemType Directory -Force -Path $work | Out-Null

try {
    # --- 1) インストール ---------------------------------------------------
    & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $phase1 'Install.ps1') -InstallDir $installDir -Quiet
    Assert ($LASTEXITCODE -eq 0) "Install.ps1 が正常終了した"
    Assert (Test-Path (Join-Path $installDir 'SicCore.psm1')) "SicCore.psm1 がコピーされた"
    Assert (Test-Path (Join-Path $installDir 'Launch-IconPicker.ps1')) "Launch-IconPicker.ps1 がコピーされた"
    Assert (Test-Path (Join-Path $installDir 'IconPicker.ps1')) "IconPicker.ps1 がコピーされた"
    Assert (Test-Path (Join-Path $installDir 'assets\app.ico')) "assets\app.ico がコピーされた"
    $starterCount = (Get-ChildItem (Join-Path $installDir 'assets\starter-icons') -Filter *.png -ErrorAction SilentlyContinue).Count
    Assert ($starterCount -gt 0) "スターターアイコンがコピーされた ($starterCount 件)"

    # --- 1b) インストール先モジュールがライブラリを列挙できるか（空リスト回帰防止） ---
    $libProbe = @"
Import-Module '$installDir\SicCore.psm1' -Force
@(Get-IconLibrary).Count
"@
    $libProbeFile = Join-Path $work 'libprobe.ps1'
    Set-Content -LiteralPath $libProbeFile -Value $libProbe -Encoding UTF8
    $libOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $libProbeFile
    $libCount = [int]($libOut | Select-Object -Last 1)
    Write-Host "  Get-IconLibrary (installed layout) = $libCount"
    Assert ($libCount -ge $starterCount) "インストール先モジュールがスターターアイコンを列挙できる ($libCount 件)"

    # --- 2) レジストリ verb ------------------------------------------------
    Assert (Test-Path $verbKey) "レジストリ verb が作成された"
    $verbDefault = (Get-ItemProperty -Path $verbKey).'(default)'
    Assert ($verbDefault -like '*アイコンを変更*') "verb の表示名が設定された"
    $cmd = (Get-ItemProperty -Path "$verbKey\command").'(default)'
    Write-Host "  command = $cmd"
    Assert ($cmd -like "*$installDir*Launch-IconPicker.ps1*") "command がインストール先の Launch を指す"
    Assert ($cmd -like '*-STA*') "command に -STA が含まれる"
    Assert ($cmd -like '*powershell.exe*') "command が powershell.exe (5.1) を使う"
    Assert ($cmd -like '*"%1"*') "command に %1 (.lnk パス) が含まれる"

    # --- 3) ランチャーで UI なし適用 --------------------------------------
    $target = Join-Path $work 'target.txt'
    Set-Content -LiteralPath $target -Value 'x' -Encoding ascii
    $lnk = Join-Path $work 'Test.lnk'
    $sh = New-Object -ComObject WScript.Shell
    $sc = $sh.CreateShortcut($lnk); $sc.TargetPath = $target; $sc.Save()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh)

    $iconPng = Join-Path $installDir 'assets\starter-icons\Rocket.png'
    & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installDir 'Launch-IconPicker.ps1') -LnkPath $lnk -IconPath $iconPng
    Assert ($LASTEXITCODE -eq 0) "Launch-IconPicker.ps1 -IconPath が正常終了した"

    $sh2 = New-Object -ComObject WScript.Shell
    $sc2 = $sh2.CreateShortcut($lnk); $iconLoc = $sc2.IconLocation
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh2)
    Write-Host "  IconLocation = $iconLoc"
    Assert ($iconLoc.ToLower().Contains('.ico')) ".lnk に .ico が適用された"

    # --- 4) ピッカー構築 (STA, NoShow) ------------------------------------
    $pickerProbe = @"
Import-Module '$installDir\SicCore.psm1' -Force
. '$installDir\IconPicker.ps1'
`$r = Show-SicIconPicker -LnkPath '$lnk' -NoShow
exit 0
"@
    $probeFile = Join-Path $work 'probe.ps1'
    Set-Content -LiteralPath $probeFile -Value $pickerProbe -Encoding UTF8
    & $psExe -NoProfile -STA -ExecutionPolicy Bypass -File $probeFile
    Assert ($LASTEXITCODE -eq 0) "Show-SicIconPicker -NoShow が STA で例外なく構築できた"

    # --- 4b) 実クリックで選択パスが Window.Tag に入る (回帰: ShowDialog/Selected 例外) ---
    $clickProbe = @"
Import-Module '$installDir\SicCore.psm1' -Force
. '$installDir\IconPicker.ps1'
Add-Type -AssemblyName PresentationFramework
`$win = New-SicIconPickerWindow -LnkPath '$lnk'
`$panel = `$win.FindName('IconPanel')
`$btn = `$null
foreach (`$c in `$panel.Children) { if (`$c -is [System.Windows.Controls.Button]) { `$btn = `$c; break } }
if (-not `$btn) { Write-Host 'NO_BUTTON'; exit 2 }
`$expected = `$btn.Tag
`$btn.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
if (`$win.Tag -and `$win.Tag -eq `$expected) { Write-Host ("PICKED=" + `$win.Tag); exit 0 }
Write-Host ("BAD_TAG=[" + `$win.Tag + "]"); exit 3
"@
    $clickFile = Join-Path $work 'clickprobe.ps1'
    Set-Content -LiteralPath $clickFile -Value $clickProbe -Encoding UTF8
    $clickOut = & $psExe -NoProfile -STA -ExecutionPolicy Bypass -File $clickFile 2>&1
    Write-Host ("  " + ($clickOut -join ' '))
    Assert ($LASTEXITCODE -eq 0) "アイコンのクリックで選択パスが Window.Tag に入る (回帰テスト)"

    # --- 4c) 既定に戻すボタンで番兵が入る + カテゴリ/色調コンボが構築される ---
    $resetProbe = @"
Import-Module '$installDir\SicCore.psm1' -Force
. '$installDir\IconPicker.ps1'
Add-Type -AssemblyName PresentationFramework
`$win = New-SicIconPickerWindow -LnkPath '$lnk'
`$cat = `$win.FindName('CategoryCombo')
`$col = `$win.FindName('ColorCombo')
`$reset = `$win.FindName('ResetButton')
if (-not `$reset) { Write-Host 'NO_RESET'; exit 2 }
if (`$cat.Items.Count -lt 2) { Write-Host ('CAT_ITEMS=' + `$cat.Items.Count); exit 4 }
if (`$col.Items.Count -lt 2) { Write-Host ('COL_ITEMS=' + `$col.Items.Count); exit 5 }
`$reset.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
if (`$win.Tag -eq '__SIC_RESET__') { Write-Host ('CAT=' + `$cat.Items.Count + ' COL=' + `$col.Items.Count); exit 0 }
Write-Host ('BAD_TAG=[' + `$win.Tag + ']'); exit 3
"@
    $resetFile = Join-Path $work 'resetprobe.ps1'
    Set-Content -LiteralPath $resetFile -Value $resetProbe -Encoding UTF8
    $resetOut = & $psExe -NoProfile -STA -ExecutionPolicy Bypass -File $resetFile 2>&1
    Write-Host ("  " + ($resetOut -join ' '))
    Assert ($LASTEXITCODE -eq 0) "「既定に戻す」ボタンで番兵が Window.Tag に入る / コンボボックスが構築される"

    # --- 5) ランチャー -Reset で既定に戻す --------------------------------
    & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installDir 'Launch-IconPicker.ps1') -LnkPath $lnk -Reset
    Assert ($LASTEXITCODE -eq 0) "Launch-IconPicker.ps1 -Reset が正常終了した"
    $sh4 = New-Object -ComObject WScript.Shell
    $sc4 = $sh4.CreateShortcut($lnk); $iconLocReset = $sc4.IconLocation
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh4)
    Write-Host "  IconLocation(after reset) = $iconLocReset"
    Assert ($iconLocReset -eq ',0') "ランチャー -Reset で IconLocation が ',0'（既定）になる"
}
finally {
    # --- 後始末（アンインストール） ---------------------------------------
    try {
        & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $phase1 'Uninstall.ps1') -InstallDir $installDir -Quiet | Out-Null
    } catch { }
    if (Test-Path $verbKey) { Remove-Item $verbKey -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Assert (-not (Test-Path $verbKey)) "アンインストールでレジストリ verb が削除された"

Write-Host ""
if ($script:Failures -eq 0) {
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
    exit 0
}
else {
    Write-Host ("FAILED: {0} assertion(s)" -f $script:Failures) -ForegroundColor Red
    exit 1
}
