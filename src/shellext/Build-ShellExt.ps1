#requires -Version 5.1
<#
.SYNOPSIS
  IExplorerCommand ハンドラ DLL (Sic.ShellExt.dll) を x64 でビルドする(本番)。

.DESCRIPTION
  WRL/ATL 非依存の生 COM 実装を MSVC で /MT 静的リンク ビルドする。追加ランタイム依存なし。
  出力 Sic.ShellExt.dll は installer\sparse のスパース パッケージ + MSI ペイロードに同梱される。
  Visual Studio (Enterprise/Professional/Community/BuildTools) の vcvars64.bat を自動検出する。

.PARAMETER OutDir
  DLL の出力先。既定はこのスクリプトと同じフォルダ (src\shellext)。
#>
[CmdletBinding()]
param(
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$SrcDir = $PSScriptRoot
if (-not $OutDir) { $OutDir = $SrcDir }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$candidates = @('Enterprise','Professional','Community','BuildTools') | ForEach-Object {
    "C:\Program Files\Microsoft Visual Studio\18\$_\VC\Auxiliary\Build\vcvars64.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2022\$_\VC\Auxiliary\Build\vcvars64.bat"
}
$vcvars = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $vcvars) { throw 'vcvars64.bat が見つかりません。Visual Studio C++ ツールセットが必要です。' }

$dllOut = Join-Path $OutDir 'Sic.ShellExt.dll'
Write-Host "vcvars : $vcvars"
Write-Host "out    : $dllOut (x64, /MT)"

$cl = "cl /nologo /std:c++17 /utf-8 /W3 /EHsc /MT /LD /DUNICODE /D_UNICODE Sic.ShellExt.cpp /link /DEF:Sic.ShellExt.def /OUT:`"$dllOut`""
& $env:ComSpec /c "call `"$vcvars`" >nul 2>nul && cd /d `"$SrcDir`" && $cl"
if ($LASTEXITCODE -ne 0) { throw "コンパイルに失敗しました (exit $LASTEXITCODE)。" }
if (-not (Test-Path $dllOut)) { throw 'DLL が生成されませんでした。' }

# 中間生成物の掃除
Get-ChildItem $SrcDir -Include *.obj,*.exp,*.lib -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host ("OK: {0} ({1:N0} bytes)" -f $dllOut, (Get-Item $dllOut).Length) -ForegroundColor Green
