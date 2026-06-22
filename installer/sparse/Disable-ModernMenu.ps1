#requires -Version 5.1
<#
.SYNOPSIS
  モダン コンテキスト メニュー登録(スパース MSIX)を解除する。

.DESCRIPTION
  Enable-ModernMenu.ps1 の対。per-user パッケージをユーザー コンテキストで除去し、
  任意で取り込んだ証明書(LocalMachine の Root / TrustedPeople)を昇格して削除する。
  レガシー動詞(「その他のオプション」側)は MSI 所有のため本スクリプトは触れない。

.PARAMETER InstallDir
  既定はこのスクリプトの場所(.cer の所在)。

.PARAMETER CerPath
  証明書削除時に拇印を得る .cer。既定 <InstallDir>\sic-codesign.cer。

.PARAMETER KeepCert
  証明書を削除しない(パッケージ登録のみ解除)。

.PARAMETER RemoveCertOnly
  内部用。昇格した子プロセスが証明書削除だけを行う。

.PARAMETER NoRestartExplorer
  反映のための explorer 再起動を抑止する。
#>
[CmdletBinding()]
param(
    [string]$InstallDir = $PSScriptRoot,
    [string]$CerPath,
    [switch]$KeepCert,
    [switch]$RemoveCertOnly,
    [switch]$NoRestartExplorer
)

$ErrorActionPreference = 'Stop'
if (-not $CerPath) { $CerPath = Join-Path $InstallDir 'sic-codesign.cer' }
$LogPath = Join-Path $env:TEMP 'sic-modern-menu-setup.log'
function Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

# ------- 昇格側: 証明書削除のみ -------
if ($RemoveCertOnly) {
    try {
        if (Test-Path $CerPath) {
            $thumb = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CerPath)).Thumbprint
            foreach ($store in 'Root','TrustedPeople') {
                $p = Join-Path "Cert:\LocalMachine\$store" $thumb
                if (Test-Path $p) { Remove-Item $p -Force; Log "削除: $store\$thumb" }
            }
        }
        exit 0
    } catch { Log "ERROR(RemoveCertOnly): $_"; exit 1 }
}

# ------- ユーザー側 -------
try {
    Log "Disable-ModernMenu 開始"
    $pkg = Get-AppxPackage -Name 'kemaruya.ShortcutIconChanger' -ErrorAction SilentlyContinue
    if ($pkg) {
        Remove-AppxPackage -Package $pkg.PackageFullName
        Log "パッケージ登録解除: $($pkg.PackageFullName)"
    } else {
        Log "登録済みパッケージなし(スキップ)。"
    }

    if (-not $KeepCert) {
        Log "証明書を昇格削除します (UAC)。"
        $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",
                  '-RemoveCertOnly','-CerPath',"`"$CerPath`"")
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait | Out-Null
    }

    if (-not $NoRestartExplorer) {
        $ids = (Get-Process explorer -ErrorAction SilentlyContinue).Id
        if ($ids) { Stop-Process -Id $ids -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 800 }
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    }
    Log "Disable-ModernMenu 完了。"
    exit 0
} catch { Log "ERROR: $_"; exit 1 }
