# shortcut-icon-changer

Windows のショートカット (`.lnk`) のアイコンを、右クリックメニューから手軽に・カラフルに変更するツールです。OS 標準アイコン (imageres.dll / shell32.dll) は色調が統一されていて数も限られるため、内容を見た目で判断しづらいという課題を解決します。

> 状態: **Phase 1 リリース済み**（v0.4.0・Windows 11 標準機能のみ・追加ランタイム/ビルド/署名は不要）／**Phase 2 ネイティブアプリ + MSI 追加**（v0.5.2・下記参照）

## 特長

- 右クリック →「アイコンを変更」だけで `.lnk` のアイコンを変更
- カラフルなアイコン源として **Microsoft Fluent UI Emoji (MIT)** 約 1,300 種を利用。**3D / フラット / ハイコントラスト** の 3 スタイルを同梱（**既定では 3D・フラットの 2 スタイルを表示**。ハイコントラストはアセットとして同梱しつつ既定で非表示）
- **約 900 種のスターターアイコンを同梱**（3D・フラット・ハイコントラスト 各 300 種、SVG はビルド時に PNG へラスタライズ）— ネット接続なしですぐ選べます。**アプリ上は既定で 3D・フラットの計 600 種を表示**します
- **スタイル・ジャンル・色調のタグクラウドで絞り込み** — ピッカー上部のタグをクリックして ON にすると一致するアイコンだけを表示（同種タグは OR、種別をまたぐと AND）。件数の多いタグほど大きく表示
- **上部のキーワード検索ボックス**（注釈付き）で名前・ジャンル・スタイル・キーワードを横断検索（タグクラウドと併用可）
- **「既定に戻す」** ワンクリックで元の（ターゲット本来の）アイコンに戻せます
- ユーザー独自の `.ico` / `.png`（Phase 1.5 で `.svg`）も指定可能（PNG はその場で `.ico` 化）
- **追加ランタイム不要**: Windows 11 同梱の Windows PowerShell 5.1 / .NET Framework 4.8 (WPF, System.Drawing) / WScript.Shell COM のみで動作
- 管理者権限不要（`HKCU` にユーザー単位で登録）

## 動作要件

- Windows 11（21H2 以降）
- 追加インストール不要（Windows 同梱機能のみ）

## インストール（Phase 1）

### A. 配布パッケージ（ZIP）から（推奨・検証 VM 向け）

リポジトリのパスに依存せず導入できます。[Releases](https://github.com/kemaruya/shortcut-icon-changer/releases) から `shortcut-icon-changer-phase1-vX.Y.Z.zip` を入手してください。

1. ダウンロードした ZIP を右クリック →「プロパティ」→「許可する (Unblock)」にチェックして OK（任意。ブラウザ/SmartScreen の警告を減らせます）
2. ZIP を任意の場所に展開
3. 同梱の `Install.cmd` をダブルクリック（または `powershell.exe -ExecutionPolicy Bypass -File .\Install.ps1`）

`%LOCALAPPDATA%\Programs\ShortcutIconChanger` に導入され、右クリックメニューに「アイコンを変更」が登録されます（管理者権限不要）。

> **EXE インストーラーは提供しません。** IExpress 製の自己解凍 EXE は署名が無いと Microsoft Defender に「ウイルス」と誤検知され、ブラウザのダウンロード段階でブロックされるためです。配布は ZIP を使用します。

パッケージは次のコマンドで生成できます。

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\build\Build-Package.ps1
# → dist\shortcut-icon-changer-phase1-vX.Y.Z.zip を出力
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

# アイコンを適用
Set-ShortcutIcon -LnkPath "C:\path\to\App.lnk" -IconPath "C:\path\to\icon.png"

# アイコンを既定（ターゲット本来）に戻す
Reset-ShortcutIcon -LnkPath "C:\path\to\App.lnk"
```

右クリックメニューから既定に戻す場合は、ピッカーの「既定に戻す」ボタンを使うか、`Launch-IconPicker.ps1 -LnkPath <.lnk> -Reset` を実行します。

## Phase 2: ネイティブアプリ + MSI インストーラー（v0.5.2）

Phase 1 の PowerShell + WPF 実装を、**C# のネイティブ WPF アプリ（.NET Framework 4.8）** と **WiX 製のユーザー単位 MSI インストーラー** に刷新したものです。Phase 1 と同じく **追加ランタイムは不要**（.NET Framework 4.8 は Windows 11 に同梱）で、検証 VM での「前提インストール不要」という性質を保っています。

### Phase 2 の追加点

- **ネイティブ アプリ化**: 起動を `powershell.exe` ではなく単一の `ShortcutIconChanger.exe`（WPF）に変更。同じ 900 種スターターアイコン・タグクラウド絞り込み・キーワード検索・「既定に戻す」を備えます
- **多言語対応（日本語 / 英語）**: UI 文言・アイコン表示名を日本語/英語で切り替え。**既定はユーザーの表示言語に追従**し、**日本語環境では日本語、それ以外の環境では英語へフォールバック**します。アイコン名は Unicode CLDR の日本語注釈から生成した固有名（例: `Rocket` →「ロケット」、`Rocket (フラット)` →「ロケット（フラット）」）を内蔵
- **MSI インストーラー（WiX 6）**: 管理者権限不要の **ユーザー単位 MSI**。右クリック動詞の登録/解除をインストーラーが管理し、アンインストールで残留物を残しません
- **起動の体感改善（v0.5.1）**: クリック直後に**スプラッシュ スクリーン**を表示し、ウィンドウ表示までの待ち時間を覆います。アイコン一覧は**先頭分だけ即時表示し残りを背景で逐次読み込む**ため、一覧の準備完了を待たずにウィンドウが開きます
- **既定スタイルの最適化（v0.5.2）**: 使用率の低い**ハイコントラストを既定で非表示**にしました（アプリ上は 3D・フラットの計 600 種を表示）。アセットとインデックスは同梱したまま残すため、必要になれば再表示できます

### インストール（MSI）

[Releases](https://github.com/kemaruya/shortcut-icon-changer/releases) から `ShortcutIconChanger-X.Y.Z-perUser.msi` を入手し、ダブルクリック（またはサイレント `msiexec /i ShortcutIconChanger-0.5.2-perUser.msi /qn`）でインストールします。管理者権限・UAC は不要です。`%LOCALAPPDATA%\Programs\ShortcutIconChanger` に導入され、`.lnk` の右クリックメニューに「アイコンを変更」が登録されます。

アンインストールは「アプリと機能」から、またはサイレントに `msiexec /x ShortcutIconChanger-0.5.2-perUser.msi /qn` で行えます。

### ビルド（開発者向け）

```powershell
# スターターアイコンの日本語名を生成（index を v3 化・要ネットワーク。通常は同梱済みのため不要）
powershell.exe -ExecutionPolicy Bypass -File .\tools\Build-NamesJa.ps1

# Release ビルド → ステージング → WiX で MSI 生成
powershell.exe -ExecutionPolicy Bypass -File .\build\Build-Phase2.ps1
# → dist\ShortcutIconChanger-X.Y.Z-perUser.msi を出力（-RunTests で Core テストも実行）
```

> ビルドには Visual Studio 2022/2026（MSBuild）と WiX 6 グローバル ツール（`dotnet tool install --global wix`）が必要です。エンドユーザーの実行環境には不要です。

## アーキテクチャ / 設計

[docs/architecture.md](docs/architecture.md) を参照してください。Phase 2（ネイティブ WPF アプリ + WiX ユーザー単位 MSI + 日本語/英語 i18n）の構成もここにまとめます。

## ライセンス

- 本リポジトリのコード: [MIT](LICENSE)
- 同梱・取得するアイコン: Microsoft Fluent UI Emoji (MIT)。[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) を参照。
