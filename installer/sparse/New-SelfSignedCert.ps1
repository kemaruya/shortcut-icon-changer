#requires -Version 5.1
<#
.SYNOPSIS
  モダン コンテキスト メニュー用スパース MSIX に署名する自己署名コード署名証明書を生成する。

.DESCRIPTION
  個人開発者向けの自己署名証明書 (CN=kemaruya) を CurrentUser\My に作成し、
  公開鍵 (.cer) を installer\sparse\sic-codesign.cer へ、秘密鍵付き (.pfx) を
  リポジトリ外 (%USERPROFILE%\.sic-signing) へエクスポートする。

  - .cer は配布物に同梱し、エンド ユーザー機で LocalMachine の信頼ストアへ取り込む(公開鍵のみ・安全)。
  - .pfx はバックアップ/可搬用。署名自体は CurrentUser\My のストア上の証明書を
    拇印で参照して行うため(Build-Sparse.ps1)、通常 pfx は不要。
  - Publisher は manifest の Publisher 属性と完全一致する必要がある (= "CN=kemaruya")。

  将来 Azure Trusted Signing が日本で利用可能になったら、本自己署名は置き換える(TODO)。

.PARAMETER Subject
  証明書のサブジェクト DN。manifest の Publisher と一致させること。既定 "CN=kemaruya"。

.PARAMETER Years
  有効期限(年)。既定 6。

.PARAMETER PfxPath
  秘密鍵付きエクスポート先 .pfx。既定 %USERPROFILE%\.sic-signing\sic-codesign.pfx。

.PARAMETER CerPath
  公開鍵エクスポート先 .cer。既定 installer\sparse\sic-codesign.cer (コミット可)。

.PARAMETER Force
  既存の同サブジェクト証明書があっても新規作成する。
#>
[CmdletBinding()]
param(
    [string]$Subject = 'CN=kemaruya',
    [int]$Years = 6,
    [string]$PfxPath = (Join-Path $env:USERPROFILE '.sic-signing\sic-codesign.pfx'),
    [string]$CerPath = (Join-Path $PSScriptRoot 'sic-codesign.cer'),
    [securestring]$PfxPassword,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$codeSignOid = '1.3.6.1.5.5.7.3.3'
$existing = Get-ChildItem Cert:\CurrentUser\My | Where-Object {
    $_.Subject -eq $Subject -and $_.HasPrivateKey -and
    ($_.EnhancedKeyUsageList.ObjectId -contains $codeSignOid)
}
if ($existing -and -not $Force) {
    $cert = $existing | Sort-Object NotAfter -Descending | Select-Object -First 1
    Write-Host "既存の証明書を使用します (拇印 $($cert.Thumbprint))。新規作成は -Force。" -ForegroundColor Yellow
} else {
    Write-Host "コード署名証明書を作成します: $Subject (有効 $Years 年)"
    $cert = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject $Subject `
        -CertStoreLocation Cert:\CurrentUser\My `
        -KeyExportPolicy Exportable `
        -KeyUsage DigitalSignature `
        -KeyAlgorithm RSA -KeyLength 2048 `
        -NotAfter (Get-Date).AddYears($Years) `
        -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3','2.5.29.19={text}')
}

# 公開鍵 (.cer, DER) — 配布/信頼取り込み用
New-Item -ItemType Directory -Force -Path (Split-Path $CerPath) | Out-Null
Export-Certificate -Cert $cert -FilePath $CerPath -Type CERT -Force | Out-Null
Write-Host "公開鍵を書き出しました: $CerPath"

# 秘密鍵付き (.pfx) — バックアップ用(任意)。失敗しても署名はストア上の証明書で行えるため致命的でない
New-Item -ItemType Directory -Force -Path (Split-Path $PfxPath) | Out-Null
try {
    if ($PfxPassword) {
        Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $PfxPassword -Force | Out-Null
    } else {
        Export-PfxCertificate -Cert $cert -FilePath $PfxPath -ProtectTo "$env:USERDOMAIN\$env:USERNAME" -Force | Out-Null
    }
    Write-Host "秘密鍵バックアップを書き出しました: $PfxPath (リポジトリ外)"
} catch {
    Write-Warning "秘密鍵バックアップ(.pfx)の書き出しをスキップしました: $($_.Exception.Message)"
    Write-Warning "証明書は CurrentUser\My に保存済みで署名は可能です。可搬バックアップが必要なら -PfxPassword を指定して再実行してください。"
}

# 拇印を Build-Sparse 用に控える(任意・gitignore 対象)
$thumbFile = Join-Path $PSScriptRoot '.signing-thumbprint.txt'
Set-Content -Path $thumbFile -Value $cert.Thumbprint -Encoding ASCII
Write-Host ""
Write-Host "拇印: $($cert.Thumbprint)" -ForegroundColor Green
Write-Host "Publisher(manifest と一致させる): $($cert.Subject)" -ForegroundColor Green
