#requires -Version 5.1
<#
.SYNOPSIS
    右クリックメニューのエントリポイント。.lnk のアイコンを変更する。
.DESCRIPTION
    レジストリ verb から powershell.exe -STA で呼ばれる。%1 のショートカットパスを受け取り、
    アイコンピッカーを表示して選択結果を .lnk に適用する。
    -IconPath を指定すると UI を出さずに直接適用する（CLI/自動テスト用）。
    -Reset を指定すると UI を出さずにアイコンを既定（ターゲット本来）に戻す。
    ピッカーで「既定に戻す」を選んだ場合も同様に既定へ戻す。
    -WindowStyle Hidden で起動されるため、エラーは MessageBox で表示する。
.PARAMETER LnkPath
    対象の .lnk ファイル（右クリック対象）。
.PARAMETER IconPath
    指定時は UI を出さずこのアイコンを適用する。
.PARAMETER Reset
    指定時は UI を出さずアイコンを既定に戻す。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $LnkPath,
    [string] $IconPath,
    [switch] $Reset
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ピッカーが「既定に戻す」を表す番兵（IconPicker.ps1 と一致させること）。
$ResetSentinel = '__SIC_RESET__'

# UI を出す場合は STA が必要。MTA なら powershell.exe -STA で再起動する。
# -IconPath / -Reset は UI を出さないため再起動不要。
if (-not $IconPath -and -not $Reset -and [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $ps -NoProfile -STA -ExecutionPolicy Bypass -File $PSCommandPath -LnkPath $LnkPath
    exit $LASTEXITCODE
}

Import-Module (Join-Path $PSScriptRoot 'SicCore.psm1') -Force
. (Join-Path $PSScriptRoot 'IconPicker.ps1')

function Show-Error([string] $message) {
    try {
        [System.Windows.MessageBox]::Show($message, 'アイコンを変更', 'OK', 'Error') | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($message, 'アイコンを変更') | Out-Null
    }
}

try {
    if (-not (Test-Path -LiteralPath $LnkPath)) {
        throw "ショートカットが見つかりません:`n$LnkPath"
    }
    if ([System.IO.Path]::GetExtension($LnkPath).ToLowerInvariant() -ne '.lnk') {
        throw "対象は .lnk（ショートカット）ではありません:`n$LnkPath"
    }

    if ($Reset) {
        Reset-ShortcutIcon -LnkPath $LnkPath | Out-Null
        exit 0
    }

    if ($IconPath) {
        Set-ShortcutIcon -LnkPath $LnkPath -IconPath $IconPath | Out-Null
        exit 0
    }

    $picked = Show-SicIconPicker -LnkPath $LnkPath
    if ($picked -eq $ResetSentinel) {
        Reset-ShortcutIcon -LnkPath $LnkPath | Out-Null
    }
    elseif ($picked) {
        Set-ShortcutIcon -LnkPath $LnkPath -IconPath $picked | Out-Null
    }
    exit 0
}
catch {
    Show-Error ("アイコンの変更に失敗しました。`n`n" + $_.Exception.Message)
    exit 1
}
