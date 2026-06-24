# Microsoft Store 申請手順（Shortcut Icon Changer）

Shortcut Icon Changer を Microsoft Store で配布するための手順です。GitHub 配布の MSI（自己署名スパース MSIX 同梱）とは別に、**完全（自己完結）MSIX** を Partner Center にアップロードし、Microsoft が信頼された証明書で再署名する経路を使います。自己署名は不要になります。

ビルド インフラ（`Build-Store.ps1` / `AppxManifest.xml`）は整備済みです。残るのは **Partner Center 側の手作業**（アカウント登録・アプリ名予約・Identity 取得）と、その値を使った**未署名 MSIX のビルド**、および**ストア リスティングの入力**です。

---

## 0. 前提と全体像

| 項目 | 値 |
| --- | --- |
| アプリ表示名 | Shortcut Icon Changer |
| 最小 OS | Windows 10.0.22000.0（Windows 11 21H2） |
| 検証済み上限 | 10.0.26100.0（Windows 11 24H2） |
| アーキテクチャ | x64 |
| 機能 | `runFullTrust`（Win32 デスクトップ アプリ） |
| コンテキスト メニュー CLSID | `B6E6D7EA-EEBA-4B94-84CE-E34DCF06AD5C` |
| パッケージ内 exe | `ShortcutIconChanger.exe`（mediumIL / win32App） |

フロー: **アカウント登録 → アプリ名予約 → Identity 取得 → 未署名 MSIX ビルド → リスティング入力 → アップロード → 審査 → 公開**。

---

## 1. Partner Center 開発者アカウント（ユーザー作業・一度きり）

1. <https://partner.microsoft.com/dashboard> で **Windows & Xbox（Microsoft Store）** の開発者として登録する。
2. 個人アカウントは一度きりの登録料が必要（企業アカウントは別手続き）。
3. 登録後、ダッシュボードで **新しいアプリ（Create a new app）** を作成できる状態にする。

> Azure Trusted Signing が日本で利用可能になれば GitHub 配布側の自己署名も置き換えられますが、それとは独立に Store 配布は進められます（Store は独自に再署名するため）。

---

## 2. アプリ名の予約と Identity の取得（ユーザー作業）

1. Partner Center → **アプリとゲーム → 新しい製品 → アプリ** で **Shortcut Icon Changer** を予約する（同名が取得できない場合は近い名前に）。
2. 予約したアプリの **製品 ID（Product identity）** ページで、次の 3 つを控える。これらが MSIX マニフェストに入る値です。
   - **パッケージ/ID/名前（Package/Identity/Name）** … 例 `1234ABCDEF.ShortcutIconChanger`
   - **パッケージ/ID/発行者（Package/Identity/Publisher）** … 例 `CN=ABCDEF01-2345-6789-ABCD-EF0123456789`
   - **パッケージ/ID/発行者表示名（Publisher display name）** … 例 `Taro Yamada`

> この 3 値は **完全一致**でマニフェストに埋め込む必要があります。1 文字でも違うとアップロード検証で拒否されます。

---

## 3. 未署名 Store MSIX のビルド（Identity 確定後）

控えた 3 値を渡してビルドします。**`-SelfSign` は付けません**（未署名のまま。Store がアップロード後に再署名します）。

```powershell
# 例: Partner Center の値を渡す（実値に置換）
pwsh installer\store\Build-Store.ps1 `
  -IdentityName    "1234ABCDEF.ShortcutIconChanger" `
  -Publisher       "CN=ABCDEF01-2345-6789-ABCD-EF0123456789" `
  -PublisherDisplay "Taro Yamada"
# → dist\ShortcutIconChanger-Store-0.8.0.0.msix（未署名）を出力
```

- バージョンは `VERSION` から `x.y.z.0` で自動決定されます（明示する場合は `-Version 0.8.0.0`）。
- 生成物は `dist\ShortcutIconChanger-Store-<version>.msix`。これを Partner Center にアップロードします。
- マニフェストの `Version` は **リビジョン（4 桁目）を 0 以外**にして再提出する運用も可能です（同一バージョン再アップロード不可のため、リジェクト後の差し替えは 4 桁目を上げる）。

### ローカル/VM で事前検証したい場合（任意）

`-SelfSign` を付けると自己署名され、サイドロードで動作確認できます（Publisher は署名サブジェクトと一致が必須）。これは検証専用で、Store には未署名版を出します。

```powershell
pwsh installer\store\Build-Store.ps1 -SelfSign   # 既定 CN=kemaruya で署名（検証用）
```

---

## 4. ストア リスティング（入力内容のひな型）

Partner Center の **ストアの掲載情報** に入力します。日本語・英語の両方を用意すると到達性が上がります。

### カテゴリ
- **ユーティリティとツール（Utilities & tools）**

### 検索語（最大 7）
`shortcut, icon, lnk, emoji, customize, fluent, ショートカット`

### 説明（日本語）
```
Shortcut Icon Changer は、Windows のショートカット（.lnk）のアイコンを右クリックから手軽に変更できるツールです。

・右クリック →「アイコンを変更」だけで .lnk のアイコンを変更
・Microsoft Fluent UI Emoji（3D・フラットの計 約 2,570 種）を同梱、ネット接続不要
・スタイル/ジャンル/色のタグとキーワード検索で目的のアイコンをすばやく発見
・ワンクリックで元のアイコンに戻せます
・ライト/ダーク/システム追従のテーマに対応
・追加ランタイム不要（Windows 11 同梱の .NET Framework 4.8 で動作）

スタート メニューから起動するとホーム画面が開き、「アイコンを変更」または「設定」を選べます。エクスプローラーで .lnk を右クリックすれば、その場でアイコンを変更できます。
```

### 説明（英語）
```
Shortcut Icon Changer lets you change the icon of any Windows shortcut (.lnk) right from the context menu.

- Right-click > "Change icon" to set a new icon on a .lnk
- Bundles Microsoft Fluent UI Emoji (~2,570 icons across 3D and Flat styles) - no internet required
- Find icons fast with style/genre/color tags and keyword search
- Reset to the original icon in one click
- Light / Dark / System theme support
- No extra runtime required (runs on the .NET Framework 4.8 that ships with Windows 11)

Launch from the Start menu to open the Home screen ("Change icon" / "Settings"), or right-click a .lnk in File Explorer to change its icon in place.
```

### スクリーンショット（必須・1〜10 枚）
- 推奨サイズ 1366×768 以上（最大 3840×2160）。最低 1 枚必要。
- 撮るべき画面: ①ホーム画面（2 カード）②ピッカー（タグクラウド＋アイコン一覧＋対象バー）③設定画面（テーマ切り替え）④右クリック メニューから「アイコンを変更」。

### プライバシー ポリシー
- ネットワーク送信・テレメトリ・個人データ収集は**なし**。その旨を明記した短いプライバシー ステートメントの URL を用意します（例: リポジトリの `docs/privacy.md` を GitHub Pages 等で公開）。
- 「このアプリが収集するデータ」は **収集しない** を選択。

### 年齢レーティング（IARC アンケート）
- 暴力・性的表現・ユーザー間通信・位置情報・課金 … **すべてなし**。→ 全年齢（3+）になります。

### 価格と提供
- **無料**。提供市場は全市場（または日本＋必要地域）。

---

## 5. アップロードと審査

1. Partner Center → 対象アプリ → **パッケージ** で `dist\ShortcutIconChanger-Store-<version>.msix` をアップロード。
2. 検証エラー（Identity 不一致・機能・API）が出たら本書 §2/§3 を見直す。`runFullTrust` を使うため、用途説明を求められたら「ショートカット（.lnk）のアイコン書き換えに Win32 API を使用」と回答。
3. すべての section（プロパティ・掲載情報・年齢レーティング・パッケージ）を完了して**審査に提出**。
4. 審査通過後に公開。以後の更新は **VERSION を上げ → 未署名 MSIX を再ビルド → 同じ製品にアップロード**。

---

## 6. メモ / TODO

- **ロゴ**: `Build-Store.ps1` が簡易ロゴ（青地＋白菱形）を自動生成します。審査は通りますが、Store 映えを狙うなら専用アイコンに差し替え推奨（`New-Logo` 部分、または事前生成した PNG を `Assets\` に配置してスクリプトを調整）。
- **GitHub 配布（MSI＋自己署名スパース MSIX）は併存**: Store 版は完全 MSIX、GitHub 版はオプトインのモダン メニュー。CLSID は共通のため**同時インストールは想定しません**（どちらか一方）。
- **Azure Trusted Signing**: 日本提供後に GitHub 配布側の署名を移行する TODO は別途継続。Store 配布とは独立。
