#requires -Version 5.1
<#
.SYNOPSIS
  モダン コンテキスト メニュー PoC を解除し、ステージ フォルダを削除する。
#>
[CmdletBinding()]
param(
    [string]$StageDir = 'C:\TEMP\sic-poc-stage',
    [switch]$KeepStage
)

$ErrorActionPreference = 'Stop'
Write-Host '== モダン コンテキスト メニュー PoC 解除 ==' -ForegroundColor Cyan

$pkg = Get-AppxPackage -Name 'kemaruya.ShortcutIconChanger.ContextMenuPoC' -ErrorAction SilentlyContinue
if ($pkg) {
    Remove-AppxPackage $pkg.PackageFullName
    Write-Host "解除しました: $($pkg.PackageFullName)" -ForegroundColor Green
} else {
    Write-Host '登録済みパッケージは見つかりませんでした。'
}

if (-not $KeepStage -and (Test-Path $StageDir)) {
    Remove-Item $StageDir -Recurse -Force
    Write-Host "ステージを削除しました: $StageDir"
}
