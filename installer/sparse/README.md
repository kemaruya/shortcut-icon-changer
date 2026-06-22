# モダン コンテキスト メニュー (Windows 11) — 自己署名スパース MSIX

Windows 11 の**モダン(第一階層)右クリック メニュー**に「アイコンを変更」を出すための
スパース MSIX とヘルパー一式。レガシー動詞(「その他のオプションを表示」配下)は MSI 本体が
登録済みで、こちらは**オプトイン**の追加機能。

## なぜ別パッケージなのか
モダン メニューは `IExplorerCommand` COM ハンドラを**パッケージ アプリ(MSIX)**経由で登録した
場合のみ表示される(レジストリ動詞では不可)。本体(exe/dll/assets)は MSI 導入先に置き、
スパース パッケージから**外部参照**(`AllowExternalContent` + `Add-AppxPackage -ExternalLocation`)する。

## 構成
- `New-SelfSignedCert.ps1` — 自己署名コード署名証明書(CN=kemaruya)を作成し `.cer`(公開鍵)/`.pfx`(バックアップ)を書き出す
- `AppxManifest.xml` — スパース パッケージ マニフェスト(`__VERSION__` はビルド時に置換)
- `Build-Sparse.ps1` — ロゴ生成 → pack(makeappx)→ 署名(signtool)。署名なし `.msix` を生成
- `Enable-ModernMenu.ps1` — `.cer` を信頼(昇格)し `.msix` をユーザー登録(オプトイン時に MSI が起動)
- `Disable-ModernMenu.ps1` — 登録解除(＋証明書削除)
- `sic-codesign.cer` — 配布用公開鍵(コミット可)。`.pfx`/`.msix` は gitignore

## ビルド手順(開発機)
```powershell
# 1) 証明書(初回のみ)
installer\sparse\New-SelfSignedCert.ps1
# 2) ハンドラ DLL
src\shellext\Build-ShellExt.ps1
# 3) スパース MSIX(署名済み)
installer\sparse\Build-Sparse.ps1
```
`Build-Phase2.ps1` はこれらをステージし MSI に同梱する。

## 自己署名の制約
- 署名済み `.msix` のサイドロードは **LocalMachine** の信頼ストア検証 → **証明書信頼に管理者が一度必要**。
  そのためモダン メニューはオプトイン＋昇格。MSI 本体(perUser)は昇格不要のまま。
- ダウンロード時の SmartScreen 警告は自己署名では消えない。将来 **Azure Trusted Signing**
  (日本提供後)へ置き換えれば SmartScreen とモダン メニューを同時解決できる(TODO)。

## 検証
動作確認は**クリーン VM**で行う(`/memories/verification-environment.md`)。
署名 `.msix` の信頼取り込み・登録・右クリック確認は昇格セッションが必要。
