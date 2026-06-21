# shortcut-icon-changer

Windows のショートカット (`.lnk`) のアイコンを、右クリックメニューから手軽に・カラフルに変更するツールです。OS 標準アイコン (imageres.dll / shell32.dll) は色調が統一されていて数も限られるため、内容を見た目で判断しづらいという課題を解決します。

> 状態: **Phase 1 実装中**（Windows 11 標準機能のみ・追加ランタイム/ビルド/署名は不要）

## 特長

- 右クリック →「アイコンを変更」だけで `.lnk` のアイコンを変更
- カラフルなアイコン源として **Microsoft Fluent UI Emoji (3D, MIT)** 約 1,300 種を利用（PNG ラスター）
- ユーザー独自の `.ico` / `.png`（Phase 1.5 で `.svg`）も指定可能（PNG はその場で `.ico` 化）
- **追加ランタイム不要**: Windows 11 同梱の Windows PowerShell 5.1 / .NET Framework 4.8 (WPF, System.Drawing) / WScript.Shell COM のみで動作
- 管理者権限不要（`HKCU` にユーザー単位で登録）

## 動作要件

- Windows 11（21H2 以降）
- 追加インストール不要（Windows 同梱機能のみ）

## インストール（Phase 1）

### A. 配布パッケージから（推奨・検証 VM 向け）

ビルド済みパッケージ（`dist/`）を使うと、リポジトリのパスに依存せず導入できます。

- **自己解凍インストーラー**: `shortcut-icon-changer-phase1-vX.Y.Z-installer.exe` をダブルクリック。`%LOCALAPPDATA%\Programs\ShortcutIconChanger` に展開し、右クリックメニューを登録します（管理者権限不要）。
  - 署名なし EXE のため、初回は SmartScreen の警告が出ます（「詳細情報」→「実行」）。警告を避けたい場合は下記 ZIP を利用してください。
- **ZIP**: `shortcut-icon-changer-phase1-vX.Y.Z.zip` を任意の場所に展開し、同梱の `Install.cmd` を実行（または `powershell.exe -ExecutionPolicy Bypass -File .\Install.ps1`）。

パッケージは次のコマンドで生成できます。

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\build\Build-Package.ps1
# → dist\shortcut-icon-changer-phase1-vX.Y.Z.zip と ...-installer.exe を出力
```

### B. リポジトリから（開発者向け）

```powershell
# リポジトリを取得
git clone https://github.com/kemaruya/shortcut-icon-changer.git
cd shortcut-icon-changer

# 右クリックメニューに登録（HKCU・管理者権限不要）
powershell.exe -ExecutionPolicy Bypass -File .\src\phase1\Install.ps1

# （任意）Fluent UI Emoji の全アイコンをライブラリに取得
powershell.exe -ExecutionPolicy Bypass -File .\tools\Fetch-FluentEmoji.ps1
```

登録後、任意の `.lnk` を右クリック →「その他のオプションを表示」→「アイコンを変更」を選ぶとピッカーが開きます。

> Phase 1 の項目は Windows 11 のレガシー (「その他のオプションを表示」) メニューに表示されます。トップレベルのモダンメニュー対応は Phase 2 で追加します。

## アンインストール

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\src\phase1\Uninstall.ps1
```

## コマンドラインでの利用（UI なし）

```powershell
Import-Module .\src\phase1\SicCore.psm1
Set-ShortcutIcon -LnkPath "C:\path\to\App.lnk" -IconPath "C:\path\to\icon.png"
```

## アーキテクチャ / 設計

[docs/architecture.md](docs/architecture.md) を参照してください。Phase 2（.NET Native AOT による `IExplorerCommand` モダンメニュー対応）の設計もここにまとめます。

## ライセンス

- 本リポジトリのコード: [MIT](LICENSE)
- 同梱・取得するアイコン: Microsoft Fluent UI Emoji (MIT)。[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) を参照。
