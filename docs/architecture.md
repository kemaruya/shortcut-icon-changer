# アーキテクチャと設計

`.lnk`（Windows ショートカット）のアイコンを右クリックから手軽に・カラフルに変更するツールの設計をまとめます。

## 要件

| # | 要件 | 由来 |
|---|------|------|
| R1 | `.lnk` のアイコンを右クリックメニューから変更できる | 元相談 |
| R2 | カラフルなアイコンを多数から選べる | 元相談（OS 標準は色調統一・数不足）|
| R3 | ユーザー独自の `.ico` / `.png` /（将来）`.svg` も指定可能 | 設計合意 |
| R4 | Windows 11 の**新（モダン）コンテキストメニュー**に対応 | 設計合意 |
| R5 | なるべく**新しいツールセット**で実装 | 追加要望 |
| R6 | **追加ランタイムのインストール不要・Windows 11 標準機能のみ**で動作（可能であれば）| 追加要望（最重要）|

R4 と R6 はトレードオフがある（モダンメニューは `IExplorerCommand` + パッケージ化が必須で、ビルド・自己署名・サイドロードを伴う）。このため **段階実装** を採用する。

## アイコンの基本原理

`.lnk` 自体は「アイコンの場所 (IconLocation)」への参照を持つだけ。書き換えは COM 1 行で完結する。

```powershell
$sh  = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut($lnkPath)
$lnk.IconLocation = "$icoPath,0"   # "<ファイル>,<アイコン索引>"
$lnk.Save()
```

`IconLocation` が指せるのはアイコンを含むファイル（`.ico` / `.exe` / `.dll`）。PNG は直接指せないため、選択された PNG はその場で `.ico` に変換してキャッシュする。

## アイコン源

- **同梱/取得ライブラリ**: Microsoft Fluent UI Emoji（3D スタイル, PNG ラスター, MIT, 約 1,300 種）。色彩豊かで「内容を絵で判断」する用途に最適。
  - Phase 1 は in-box に SVG ラスタライザが無いため、PNG が提供される **3D スタイル**を採用（Flat/Color/High Contrast は SVG のみ）。
  - リポジトリには少数のスターターセット (`assets/starter-icons/`) のみ同梱。
  - 全種は `tools/Fetch-FluentEmoji.ps1` で `%LOCALAPPDATA%\ShortcutIconChanger\library` に取得。
- **カスタム**: ユーザー指定の `.ico` / `.png`（Phase 1.5 で `.svg`）。PNG/SVG はその場で `.ico` 化。

## Phase 1 — Windows 11 標準機能のみ（追加ランタイム/ビルド/署名なし）

R1・R2・R3・R6 を満たす「今すぐ動く版」。R4（モダンメニュー）は満たさず、レガシー（「その他のオプションを表示」）メニューに表示される。

### 構成

```
.lnk 右クリック
  └─ HKCU\Software\Classes\lnkfile\shell\sic.ChangeIcon\command
        └─ powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass
               -File Launch-IconPicker.ps1 -LnkPath "%1"
                 ├─ IconPicker.ps1  … WPF グリッドで選択（同梱 .NET FW 4.8）
                 └─ SicCore.psm1    … Convert-ToIco / Set-ShortcutIcon / SHChangeNotify
```

### 標準機能のみで成立する根拠（R6）

| 必要機能 | 利用するもの | 追加インストール |
|---|---|---|
| スクリプト実行 | **Windows PowerShell 5.1**（`powershell.exe`, OS 同梱）| 不要 |
| ピッカー UI | **.NET Framework 4.8 の WPF**（PresentationFramework, OS 同梱）| 不要 |
| 画像変換 | **System.Drawing**（GDI+, OS 同梱）| 不要 |
| `.lnk` 書き換え | **WScript.Shell COM**（OS 同梱）| 不要 |
| メニュー登録 | レジストリ `HKCU`（管理者権限不要）| 不要 |

> 重要: 起動は PowerShell 7 (`pwsh.exe`, 別途インストール) ではなく **`powershell.exe`（5.1）** を使う。素の Windows 11 に同梱されるのは 5.1 のため。スクリプトは 5.1 互換で書く（WPF は STA 必須 → 5.1 既定の STA で動作）。

### PNG → ICO 変換

`System.Drawing` で複数サイズ（16/32/48/256）にリサイズし、ICO コンテナを自前生成（各エントリは PNG エンコードで格納。Windows 11 は PNG 圧縮エントリを読める）。生成物は `%LOCALAPPDATA%\ShortcutIconChanger\cache` にハッシュ名でキャッシュ。

### アイコンキャッシュ更新

書き換え後、`SHChangeNotify(SHCNE_ASSOCCHANGED)` を P/Invoke で呼び、シェルに反映を促す。

## Phase 2 — モダンメニュー対応（追加ランタイム不要のまま）

R4 を満たす。R5・R6 を保つため **.NET 10 Native AOT** で実装する（Native AOT は自己完結ネイティブ DLL を生成し、.NET ランタイムの別途インストールが不要）。

### 構成

- `IExplorerCommand` を実装する COM サーバ（C#, **Native AOT**, `PublishAot=true`）。
- **スパース MSIX** パッケージで `com.microsoft...`... の登録（`Package.appxmanifest` の `desktop4:FileExplorerContextMenus` / `com:ComServer`）。
- 自己署名証明書でサイドロード（MSIX 署名・サイドロードは Windows 11 標準機能。ランタイムの追加ではない）。
- アイコンの変換/適用/ライブラリ列挙ロジックは Phase 1 のコアと等価のものを C# 側に実装、または共通仕様として共有。

### ビルド ツールチェーン

- .NET SDK 10（確認済み）
- `makeappx` / `signtool`: 未導入のため `Microsoft.Windows.SDK.BuildTools`（NuGet, 軽量）で用意（開発者側のビルド時のみ。エンドユーザーには不要）。

## 既知の制限 / TODO

- SVG ラスタライズは in-box に存在しないため Phase 1 は `.ico` / `.png` のみ対応。SVG は Phase 1.5 で対応（候補: 取得済み Fluent の PNG を使う / WIC / 軽量変換）。
- Phase 1 のメニューはレガシー側に表示（モダンメニューは Phase 2）。
- マルチ言語表示名・アイコン索引（`,N`）対応は今後検討。
