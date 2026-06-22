#requires -Version 5.1
<#
.SYNOPSIS
  IExplorerCommand ハンドラ DLL (Sic.ShellExt.dll) を x64 でビルドする。

.DESCRIPTION
  WRL/ATL 非依存の生 COM 実装を MSVC で /MT 静的リンク ビルドする。追加ランタイム依存なし。
  Visual Studio (BuildTools/Enterprise いずれか) の vcvars64.bat を自動検出する。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PocDir = $PSScriptRoot

# vcvars64.bat を検出 (Enterprise / Professional / Community / BuildTools)
$candidates = @(
    'Enterprise','Professional','Community','BuildTools'
) | ForEach-Object {
    "C:\Program Files\Microsoft Visual Studio\18\$_\VC\Auxiliary\Build\vcvars64.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2022\$_\VC\Auxiliary\Build\vcvars64.bat"
}
$vcvars = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $vcvars) { throw 'vcvars64.bat が見つかりません。Visual Studio C++ ツールセットが必要です。' }

Write-Host "vcvars : $vcvars"
Write-Host "build  : Sic.ShellExt.dll (x64, /MT)"

$cl = "cl /nologo /std:c++17 /W3 /EHsc /MT /LD /DUNICODE /D_UNICODE Sic.ShellExt.cpp /link /DEF:Sic.ShellExt.def /OUT:Sic.ShellExt.dll"
& $env:ComSpec /c "call `"$vcvars`" >nul 2>nul && cd /d `"$PocDir`" && $cl"
if ($LASTEXITCODE -ne 0) { throw "コンパイルに失敗しました (exit $LASTEXITCODE)。" }

$dll = Join-Path $PocDir 'Sic.ShellExt.dll'
if (-not (Test-Path $dll)) { throw 'DLL が生成されませんでした。' }
Write-Host ("OK: {0} ({1:N0} bytes)" -f $dll, (Get-Item $dll).Length) -ForegroundColor Green
