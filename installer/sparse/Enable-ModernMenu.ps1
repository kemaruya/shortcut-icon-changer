#requires -Version 5.1
<#
.SYNOPSIS
  Windows 11 のモダン コンテキスト メニュー(第一階層)に「アイコンを変更」を登録する。

.DESCRIPTION
  自己署名スパース MSIX をエンド ユーザー機へ登録するヘルパー。MSI の終了ダイアログで
  「有効にする」を選んだ場合に呼ばれる(オプトイン)。次の 2 段で構成する:

    1) 証明書の信頼(管理者が必要): 同梱 .cer を LocalMachine の
       Root と TrustedPeople に取り込む。この部分のみ UAC 昇格する。
    2) パッケージ登録(ユーザー コンテキスト): Add-AppxPackage -ExternalLocation で
       MSI 導入先(アプリ本体)を外部参照して sparse パッケージを登録する。

  per-user の Add-AppxPackage は対話ユーザーで実行する必要があるため、昇格は
  「証明書取り込みの子プロセス」だけに限定し、本体はユーザーのまま登録する。

.PARAMETER InstallDir
  アプリ導入先(.cer / .msix / exe / dll がある場所)。既定はこのスクリプトの場所。

.PARAMETER CerPath
  取り込む公開鍵 .cer。既定 <InstallDir>\sic-codesign.cer。

.PARAMETER MsixPath
  登録する .msix。既定は <InstallDir> 内の最新 ShortcutIconChanger-ModernMenu-*.msix。

.PARAMETER ImportCertOnly
  内部用。昇格した子プロセスが証明書取り込みだけを行うためのスイッチ。

.PARAMETER NoRestartExplorer
  反映のための explorer 再起動を抑止する。
#>
[CmdletBinding()]
param(
    [string]$InstallDir = $PSScriptRoot,
    [string]$CerPath,
    [string]$MsixPath,
    [switch]$ImportCertOnly,
    [switch]$NoRestartExplorer
)

$ErrorActionPreference = 'Stop'
if (-not $CerPath)  { $CerPath  = Join-Path $InstallDir 'sic-codesign.cer' }
$LogPath = Join-Path $env:TEMP 'sic-modern-menu-setup.log'
function Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

# ------- 昇格側: 証明書取り込みのみ -------
if ($ImportCertOnly) {
    try {
        Log "ImportCertOnly: $CerPath"
        Import-Certificate -FilePath $CerPath -CertStoreLocation Cert:\LocalMachine\Root        | Out-Null
        Import-Certificate -FilePath $CerPath -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
        Log "証明書を Root / TrustedPeople に取り込みました。"
        exit 0
    } catch {
        Log "ERROR(ImportCertOnly): $_"
        exit 1
    }
}

# ------- ユーザー側 -------
try {
    Log "Enable-ModernMenu 開始 InstallDir=$InstallDir"

    # モダン コンテキスト メニュー(IExplorerCommand 第一階層) は Windows 11 専用。
    # Windows 10 以前では何もせず正常終了する(レガシー メニューの「アイコンを変更」は MSI が登録済み)。
    $build = [Environment]::OSVersion.Version.Build
    if ($build -lt 22000) {
        Log "モダン コンテキスト メニューは Windows 11 (build >= 22000) 専用です。build=$build のためスキップします。"
        exit 0
    }

    if (-not $MsixPath) {
        $MsixPath = Get-ChildItem (Join-Path $InstallDir 'ShortcutIconChanger-ModernMenu-*.msix') -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1 | ForEach-Object FullName
    }
    if (-not $MsixPath -or -not (Test-Path $MsixPath)) { throw ".msix が見つかりません ($InstallDir)" }
    if (-not (Test-Path $CerPath)) { throw ".cer が見つかりません ($CerPath)" }
    Log "msix=$MsixPath"

    # 証明書が信頼済みかを .cer の拇印で確認
    $cer = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CerPath)
    $thumb = $cer.Thumbprint
    $trusted = Test-Path (Join-Path 'Cert:\LocalMachine\TrustedPeople' $thumb)
    if (-not $trusted) {
        Log "証明書未信頼。昇格して取り込みます (UAC)。"
        $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",
                  '-ImportCertOnly','-CerPath',"`"$CerPath`"")
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "証明書の取り込みに失敗しました (exit $($p.ExitCode))。" }
        Log "証明書取り込み完了。"
    } else {
        Log "証明書は既に信頼済み。"
    }

    # ユーザー コンテキストで sparse パッケージ登録(外部参照)
    Log "Add-AppxPackage -ExternalLocation ..."
    Add-AppxPackage -Path $MsixPath -ExternalLocation $InstallDir -ForceApplicationShutdown
    $pkg = Get-AppxPackage -Name 'kemaruya.ShortcutIconChanger' -ErrorAction SilentlyContinue
    if (-not $pkg) { throw "登録後にパッケージが見つかりません。" }
    Log "登録成功: $($pkg.PackageFullName)"

    if (-not $NoRestartExplorer) {
        Log "explorer を再起動して反映します。"
        $ids = (Get-Process explorer -ErrorAction SilentlyContinue).Id
        if ($ids) { Stop-Process -Id $ids -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 800 }
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    }
    Log "Enable-ModernMenu 完了。"
    exit 0
} catch {
    Log "ERROR: $_"
    exit 1
}
