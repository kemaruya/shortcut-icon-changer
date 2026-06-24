[English](architecture.md) | **日本語**

# アーキテクチャと設計

本書は **Shortcut Icon Changer**（Windows のショートカット `.lnk` のアイコンを、コンテキスト メニューから手早く・カラフルに変更するツール）の設計をまとめたものです。現行の実装（v0.8.x）を反映しています。すなわち、**ネイティブな WPF デスクトップ アプリ**と、任意で導入する**ネイティブ（C++）のモダン メニュー ハンドラー**から成り、**ユーザー単位の MSI**（および準備中の Microsoft Store 用 MSIX）で配布します。動作には Windows 10 / 11 に**標準同梱**されるフレームワークのみを使い、**追加ランタイムのインストールは不要**です。

> 経緯: 本プロジェクトは Windows PowerShell 製のプロトタイプとして始まりました（`src/phase1` に参考として残しています）。実際に配布する製品は `src/phase2` のネイティブ アプリで、本書はそれを説明します。初期の設計メモにあった「.NET 10 Native AOT」ハンドラーの構想に対し、モダン メニュー ハンドラーは **C++** で実装し、アプリ本体は標準同梱の **.NET Framework 4.8** を対象にしています。

## 設計目標

| # | 目標 | 現在の実現方法 |
|---|------|----------------|
| R1 | `.lnk` のアイコンをコンテキスト メニューから変更する | `lnkfile\shell` 配下の従来動詞 + 任意の Windows 11 モダン メニュー |
| R2 | 多数のカラフルなアイコンから選べる | Microsoft Fluent UI Emoji 約 2,570 個（3D + Flat）を `icons.zip` に同梱 |
| R3 | ユーザー所有の `.ico` / `.png` も使える | 選んだファイルをその場で `.ico` に変換（SVG は非対応） |
| R4 | Windows 11 の**モダン** コンテキスト メニューに対応する | ネイティブ `IExplorerCommand` ハンドラー（任意導入） |
| R5 | 近代的なツールセットを使う | ネイティブ WPF アプリ + WiX 6 MSI + C++ COM ハンドラー |
| R6 | **追加ランタイム不要** — Windows 標準機能のみ | 標準同梱の .NET Framework 4.8（WPF, System.Drawing）を対象。MSI は msiexec で導入 |

R4 と R6 は両立が難しい関係にあります（モダン メニューには `IExplorerCommand` とパッケージ化＝ビルド・自己署名・サイドロードが必要なため）。そこでモダン メニューは**任意導入（オプトイン）**とし、基本機能はそれ無しで動作します。

## アイコン変更の仕組み

`.lnk` は「アイコンの場所」への参照（`IconLocation` = `"<ファイル>,<番号>"`）を持つだけです。これを書き換えるのは `WScript.Shell` 経由のごく小さな COM 操作です。

```csharp
var shell = (dynamic)Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
var sc = shell.CreateShortcut(lnkPath);
sc.IconLocation = icoPath + ",0";   // "<ファイル>,<アイコン番号>"
sc.Save();
```

`IconLocation` が指せるのはアイコンを含むファイル（`.ico` / `.exe` / `.dll`）だけです。PNG を直接は指せないため、選択した PNG はその場で `.ico` に変換してキャッシュします。書き込み後は `SHChangeNotify(SHCNE_ASSOCCHANGED)` でシェルに更新を促します。

## ソリューション構成

```
src/phase2/
  Sic.Core/          net48 クラス ライブラリ — アイコン/ショートカットのロジック一式（UI なし）
  Sic.App/           net48 WPF アプリ — ShortcutIconChanger.exe（UI + CLI）
  Sic.Core.Tests/    Sic.Core の xUnit テスト
src/shellext/        Sic.ShellExt.cpp — C++ COM IExplorerCommand（モダン メニュー）
src/phase1/          旧 Windows PowerShell プロトタイプ（参考用）
installer/wix/       WiX 6 ユーザー単位 MSI（Package.wxs）
installer/sparse/    モダン メニューを登録する sparse MSIX（AppxManifest.xml）
installer/store/     Microsoft Store 配布用のフル MSIX
assets/starter-icons/  icons.zip + icons-index.json（同梱アイコン セット）
tools/               アセット パイプライン（取得 / ラスタライズ / セット生成）
build/               ビルド スクリプト（Build-Phase2.ps1 = ネイティブ / Build-Package.ps1 = 旧版）
```

### コア（`Sic.Core`、.NET Framework 4.8）

UI を持たないクラス ライブラリで、**標準同梱のフレームワーク アセンブリのみ**（`System.Drawing` / GDI+、JSON 用に `System.Web.Extensions` の `JavaScriptSerializer`、`System.IO.Compression`）で実装しています。サードパーティ NuGet パッケージは使いません。

| 型 | 役割 |
|----|------|
| `ShortcutService` | `.lnk` の `IconLocation` を `WScript.Shell` COM で 読み取り / 設定 / リセット し、`SHChangeNotify` でシェルに通知。 |
| `IconConverter` | PNG → 複数サイズ `.ico`（16/32/48/256、各フレームを PNG 圧縮）に変換。SHA-1 の内容シグネチャで `…\cache` にキャッシュ。`GetFinalPathNameByHandle` で**実体パス**を解決し、sparse MSIX のパス リダイレクトに左右されないようにする。 |
| `IconLibrary` / `IconIndex` / `IconItem` | 同梱（`icons.zip`）とユーザー ライブラリのアイコンを列挙し、`icons-index.json` のメタデータ（カテゴリ・スタイル・色・キーワード・日英の名前）を付与。High Contrast は既定で非表示。 |
| `IconFilter` | ピッカー用のファセット絞り込み — ファセット内は OR（スタイル / ジャンル / 色）、ファセット間は AND。名前/キーワード検索は ViewModel 側で実施。 |
| `SicAssetZip` | 同梱 `icons.zip` への共有・ロック直列化された読み取りアクセス（開いたまま保持し、エントリは都度読み出し）。 |
| `SicPaths` | `%LOCALAPPDATA%\ShortcutIconChanger` 配下のユーザー単位データ配置を解決。 |
| `AppSettings` / `AppTheme` / `CacheManager` / `SicMaps` / `NativeMethods` | 設定（`settings.json`）、テーマ列挙、キャッシュ管理、日英ラベル対応、P/Invoke。 |

### アプリ（`Sic.App`、WPF、`ShortcutIconChanger.exe`）

`WinExe`・`net48`・`UseWPF` + `UseWindowsForms`。エントリ ポイント（`App.xaml.cs`）が引数を解析して分岐します。

- `-Reset`、または `-IconPath <ファイル>`（`-Lnk <ファイル>` か末尾の `.lnk` 指定とともに）→ **UI なし**で直接適用（コンテキスト メニューやスクリプトから利用）。
- `.lnk` 引数のみ → その対象向けに**ピッカー**を開き、結果を適用。
- 引数なし → **ホーム** ハブを開く。

UI の構成:

- `HomeWindow` — スタート メニュー的なハブ（アイコン変更 / 設定）。
- `MainWindow` — アイコン ピッカー: `.lnk` と現在のアイコンを示す**対象バー**、行ごとに単一選択（スタイル / ジャンル / 色）で行間は AND の**タグ クラウド**、**キーワード検索ボックス**、そして大規模カタログでも起動を速く保つ**行単位の UI 仮想化**。
- `SettingsWindow` — 言語、テーマ、ホームから対象を選ぶ際の既定フォルダー（デスクトップ / スタート メニュー / カスタム）、キャッシュ管理。
- `ThemeManager` / `AppTheme` — アプリ全体の ライト / ダーク / システムに従う。
- `DelayedSplash` — 初回描画が実際に遅いときだけスプラッシュを表示（遅延ゲート）。暖機済みの起動ではちらつかせない。
- `ContextMenu.TryRepair` — 起動時に右クリック動詞（アイコン / ラベル / コマンド）を実行中の exe に合わせて**自己修復**し、古い登録やシェル アイコン キャッシュの破損（特に Windows 10）を是正。キーが既に存在する場合のみ更新するため、未インストール環境で勝手に登録することはない。

UI は英語・日本語にローカライズされています。

### モダン コンテキスト メニュー ハンドラー（`Sic.ShellExt`、C++）

`Sic.ShellExt.cpp` は `IExplorerCommand` を実装する軽量なネイティブ COM サーバーです。素の COM（WRL/ATL 不使用）で、CRT を静的リンク（`/MT`）しているため追加ランタイムは要りません。単一の `.lnk` に対してのみ Windows 11 の**トップレベル** メニューに「アイコンを変更」を追加し（`Type="*"` で登録し、`.lnk` 以外の選択時は `GetState` で自身を非表示にする）、クリック時に隣接する `ShortcutIconChanger.exe` を選択パス付きで起動します。

登録は **sparse MSIX**（`installer/sparse/AppxManifest.xml`）で行います。`desktop4` / `desktop5:FileExplorerContextMenus` が動詞を宣言し、`com:SurrogateServer` が DLL を `dllhost` でホストします。`AllowExternalContent` により、パッケージは実体のペイロードを MSI のインストール先ディレクトリから参照でき、コピー不要です。パッケージは**自己署名証明書**（`CN=kemaruya`）で署名してサイドロードします。

注意点が 1 つあります。パッケージ化されたサロゲートから起動した子プロセスはパッケージ ID を継承するため、`%LOCALAPPDATA%` への書き込みが `…\Packages\<PFN>\LocalCache\…` へリダイレクトされます。これを 2 つのビルドで別々に扱います。

- **GitHub / MSI（sparse）ビルド — 既定:** ハンドラーはアプリを **`explorer.exe` に親付け替え**して `DESKTOP_APP_BREAKAWAY` で起動し、パッケージ ID を外します。これで書き込みは本来の `%LOCALAPPDATA%` に行き、`.lnk` に書き込むパスと一致します（さもないと Explorer がアイコン ファイルを見つけられず、ショートカットが白く表示されます）。
- **Store（フル MSIX）ビルド — `SIC_STORE`:** コンテナー ID を保持します（Store 審査では自然な形）。代わりにアプリ側が `.lnk` 書き込み前に実体パスを解決（`IconConverter` の `GetFinalPathNameByHandle`）するため、アイコンは正しく解決されます。

## パッケージ化と配布

- **ユーザー単位 MSI**（`installer/wix/Package.wxs`、WiX 6）: `Scope="perUser"`・`WixUI_Minimal`。`%LOCALAPPDATA%\Programs\ShortcutIconChanger` に**管理者権限なし / UAC なし**で導入します。従来の `.lnk` 動詞を `HKCU\Software\Classes\lnkfile\shell\sic.changeicon` に登録します。完了画面には**オプトインのチェックボックス**（既定オフ）があり、チェックするとモダン メニューを有効化します（`Enable-ModernMenu.ps1` が一度だけ昇格して、証明書の信頼と sparse MSIX の登録を行う）。
- **Microsoft Store MSIX**（`installer/store`）: Store 署名のフル MSIX。**配布は準備中**です（`installer/store/STORE-SUBMISSION.md`・`SUBMISSION-LOG.md` を参照）。

### ビルド スクリプト

- `build/Build-Phase2.ps1` — 主ビルド: `Sic.App` を MSBuild（Release）→ 任意で xUnit テスト（`-RunTests`）→ `Sic.ShellExt.dll` と署名済み sparse MSIX をビルド → `exe` + `Sic.Core.dll` + `assets\starter-icons`（+ モダン メニュー ファイル）をステージ → WiX で `dist\ShortcutIconChanger-X.Y.Z-perUser.msi` を生成。Visual Studio の MSBuild と WiX 6 グローバル ツールが必要ですが、エンド ユーザーには不要です。
- `installer/store/Build-Store.ps1` — フルの Store MSIX をビルド。
- `build/Build-Package.ps1` — **旧 Phase 1** の PowerShell プロトタイプを ZIP 化（参考用に維持）。

## アイコン ライブラリとアセット パイプライン

同梱アイコンは **Microsoft Fluent UI Emoji（MIT）** で、ほぼ全セットを 2 スタイル、**3D と Flat（約 2,570 個）**で単一の `assets/starter-icons/icons.zip` に格納しています。インターネット接続なしで選べるようにするためです。`icons-index.json` が各アイコンのメタデータ（カテゴリ / スタイル / 色 / キーワードと日英の名前）を持ち、High Contrast は既定で除外します。セットは `tools/` パイプラインで生成します: `Fetch-FluentEmoji.ps1`（ダウンロード）、`rasterize.js`（resvg による SVG→PNG）、`Build-StarterSet.ps1`（zip + index の組み立て）、`Build-NamesJa.ps1`（日本語名）。ユーザーは自分の `.ico` / `.png` を `%LOCALAPPDATA%\ShortcutIconChanger\library` に置くことも、任意の `.ico` / `.png` を直接選ぶこともできます。

## ユーザー単位のデータ配置

```
%LOCALAPPDATA%\ShortcutIconChanger\
  library\             ユーザー追加アイコン（+ 任意の icons-index.json）
  cache\               生成された .ico（SHA-1 内容シグネチャで命名）
  starter-extracted\   適用時に必要に応じて展開される同梱アイコン
  settings.json        言語 / テーマ / 既定フォルダー など
```

## 動作要件

- **エンド ユーザー:** Windows 10 バージョン 22H2、または Windows 11。**インストール不要**（標準同梱の .NET Framework 4.8）。「アイコンを変更」動詞は Windows 10 / 11 の両方で動作しますが、**モダンなトップレベル メニューは Windows 11 のみ**です。
- **開発者（ビルド）:** Visual Studio 2022/2026 の MSBuild、WiX 6 グローバル ツール（`dotnet tool install --global wix`）、`Sic.ShellExt` 用の C++ ビルド ツール、xUnit テスト用の .NET テスト SDK。

## テスト

`Sic.Core.Tests`（xUnit）がコアを検証します: `CoreTests`・`LibraryTests`・`ShortcutTests`。`dotnet test`、または `build/Build-Phase2.ps1 -RunTests` で実行します。

## 既知の制限 / TODO

- **SVG は非対応** — `.ico` と `.png` のみ（PNG はその場で変換）。
- **モダン メニューは自己署名証明書の信頼が必要**（初回のみ管理者昇格）なため、オプトインです。従来動詞は管理者権限不要です。
- **High Contrast** の Fluent アイコンは既定で非表示です（アセット/index には保持しつつ、一覧・ファセット・検索からは除外）。
