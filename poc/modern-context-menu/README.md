# Windows 11 モダン コンテキスト メニュー PoC

`.lnk` を右クリックしたとき、**Windows 11 のモダン メニュー(第一階層)** に「アイコンを変更 / Change icon」を出すための実証実験(PoC)です。

## なぜ別実装が必要か

Windows 11 のコンテキスト メニューは 2 階層構造です。

| 階層 | 出し方 | 本リポジトリの状態 |
|------|--------|--------------------|
| **レガシー**(「その他のオプションを表示」配下 / Shift+F10) | レジストリ動詞(HKCU `lnkfile\shell\...`) | **MSI で導入済み**(`installer\wix\Package.wxs`) |
| **モダン**(第一階層) | `IExplorerCommand` COM ハンドラ + **パッケージ(スパース MSIX)** 登録 | **本 PoC** |

レジストリ動詞はモダン階層には**仕様上絶対に出ません**。モダン階層に出すには、COM ハンドラをパッケージ アプリ経由で登録する必要があります。

## 構成

| ファイル | 役割 |
|----------|------|
| `Sic.ShellExt.cpp` | `IExplorerCommand` + `IClassFactory` の生 COM 実装(WRL/ATL 非依存)。タイトルは UI 言語で「アイコンを変更/Change icon」。単一 `.lnk` 選択時のみ表示。Invoke で隣の `ShortcutIconChanger.exe "<lnk>"` を起動 |
| `Sic.ShellExt.def` | COM サーバーのエクスポート定義 |
| `AppxManifest.xml` | スパース パッケージ マニフェスト。`desktop4/5:FileExplorerContextMenus` でハンドラ CLSID をモダン メニューへ結線。`com:SurrogateServer` で DLL をホスト |
| `Build-ShellExt.ps1` | DLL を x64 `/MT` でビルド(追加ランタイム依存なし) |
| `Register-Poc.ps1` | Release 出力 + DLL + マニフェスト + ロゴを 1 フォルダへ集約し `Add-AppxPackage -Register` で**未署名ルース登録**(開発者モード前提・署名/管理者不要) |
| `Unregister-Poc.ps1` | `Remove-AppxPackage` で解除 + ステージ削除 |

ハンドラ CLSID: `{B6E6D7EA-EEBA-4B94-84CE-E34DCF06AD5C}`

## 使い方(PoC 検証)

```powershell
# 0) 前提: 開発者モード ON / Sic.App を Release ビルド済み(build\Build-Phase2.ps1)
# 1) DLL ビルド
.\Build-ShellExt.ps1
# 2) 登録(エクスプローラー再起動込みで確実に反映)
.\Register-Poc.ps1 -RestartExplorer
# 3) 任意の .lnk を右クリック → モダン メニューに「アイコンを変更」が出れば成功
# 4) 解除
.\Unregister-Poc.ps1
```

## 配布(将来)について

PoC は**未署名 + 開発者モード**で動きますが、**配布には署名済み `.msix` が必須**です(マシン信頼された証明書)。
Azure Trusted Signing(月額 ~$10・要 3 年以上の法人実在性確認)を採用すると、SmartScreen ブロック(現状 ZIP 同梱で回避)とモダン メニューの**両方**を一度に解決できます。

## 検証結果(2026-06-22)

Windows 11 25H2 (build 26200) ホストで**実証成功**。

- `Add-AppxPackage -Register`(未署名ルース登録)→ パッケージ `Status=Ok`
- パッケージ COM クラスの `CreateInstance` 成功(DLL ロード健全)
- エクスプローラー再起動後、`.lnk` の**モダン メニュー(第一階層)に「アイコンを変更」が出現**し、クリックでアイコン ピッカーが起動することを目視確認
- 検証後はホストから登録解除(`Unregister-Poc.ps1`)・残留なし

→ 未署名 + 開発者モードのルース登録だけでモダン メニューに出せることを確認。製品化には配布署名(上記)が必要。

