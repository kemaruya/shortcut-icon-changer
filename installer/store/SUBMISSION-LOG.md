# Microsoft Store 申請ログ（Shortcut Icon Changer）

このファイルは Partner Center への申請の**実績記録（ログ）**です。手順そのものは [`STORE-SUBMISSION.md`](STORE-SUBMISSION.md) を、リスティングの文面（説明・検索語など）は同 §4 を正とします。ここには「いつ・どのバージョンを・どの値で提出し、何でハマったか」を提出ごとに追記します。

---

## アプリ Identity（確定値・全提出で共通）

| 項目 | 値 |
| --- | --- |
| Store ID | `9P09F3CQ5HX7` |
| Package Identity Name | `62620kemaruya.ShortcutIconChanger` |
| Publisher | `CN=32436F7F-046A-45D3-AFAB-BCA722A88C2E` |
| Publisher Display Name | `Kenichi Maruyama` |
| Package Family Name (PFN) | `62620kemaruya.ShortcutIconChanger_a43rhmf9187gj` |

> これらは `STORE-SUBMISSION.md` §2/§3 の「控える 3 値」の確定版です。`Build-Store.ps1` に渡す `-IdentityName` / `-Publisher` / `-PublisherDisplay` は上記を完全一致で使用します（プレースホルダー例ではなくこの値が正）。

---

## Submission 1 — 2026/06/24 提出（認定待ち）

| 項目 | 内容 |
| --- | --- |
| ステータス | 提出済み（「送信して認定を受ける」完了）。**認定待ち** |
| 最終変更日 | 2026/06/24 |
| 提出パッケージ | `dist\ShortcutIconChanger-Store-0.8.2.0.msix`（Partner Center 上で Validated） |
| バージョン | 0.8.2.0（リポジトリの `VERSION` = 0.8.2 由来） |
| リスティング言語 | en-us / ja-jp の両方が **Complete** |

提出時に「完了」にした section（すべて完了で送信ボタンが有効化され提出）:

- ストアの掲載情報（en-us / ja-jp とも Complete）
- 価格と提供（無料 / 提供市場）
- 年齢区分（IARC アンケート）
- 申請オプション

---

## ナレッジ: Partner Center「登録情報のインポート」CSV のハマりどころ

将来のリスティング更新で**再発しやすい**ので必ず参照すること。

### 結論（再現性のある成功手順）

- **画像は一切触らず、テキストのみを単一 CSV で取り込む**のが確実。en-us 側で既にアップロード済みの画像 URL をそのまま維持し、**空欄セルへの追記のみ**を行う。
- 取り込み方式は **「.csv のアップロード（単一ファイル）」** を使う。

### 失敗パターン（フォルダーアップロード + 画像の相対パス参照）

- 「フォルダーのアップロード」+ CSV 内で画像を相対パス参照する方式は Web UI で**失敗した（3 回再現）**。
- エラー文言: 「次の言語の一覧をインポートできませんでした」「この .csv ファイルを処理できませんでした。登録情報をもう一度エクスポートしてください」
- エラー詳細リストは**空欄**（Partner Center の既知の不親切挙動で、UI から原因が分からない）。

### 成功パターン（テキストのみ・単一 CSV）

- ja-jp の Description / ShortDescription / Feature1–6 / Caption1–3、および日英の SearchTerm を**空欄セルに追記のみ**。
- 画像は変更しない（英語 URL をそのまま維持）。

### CSV フォーマット要件（エクスポート元と完全一致させること。ずれると上記の処理失敗になる）

- エンコーディング: **UTF-8 with BOM**
- 列: `Field,ID,Type (種類),default,en-us,ja-jp`
- クォート: **最小クォート**（カンマ / 引用符 / 改行を含むフィールドのみ引用。PowerShell の `ConvertTo-Csv -UseQuotes AsNeeded` 相当。全フィールド一律クォートは NG）
- レコード区切り: **CRLF**
- 複数行フィールド内部の改行: **LF のみ**
- 末尾改行: **なし**（EOF に余計な改行を付けない）

### 環境メモ

- 実行環境: PowerShell 7.6.3。
- `Export-Csv -Encoding UTF8` は BOM を付けないため、`[System.Text.UTF8Encoding]::new($true)` を使い `[System.IO.File]::WriteAllText` で書き出す必要がある。

### 作業用 CSV の所在（リポジトリ外）

- 成功した取り込みファイル: `C:\Users\kemaruya\Downloads\listingData-9P09F3CQ5HX7-TEXTONLY.csv`
- 元のエクスポート: `C:\Users\kemaruya\Downloads\listingData-9P09F3CQ5HX7-1152921505701289700.csv`
- 必要なら `installer/store/listing/` にコピーして残すことを検討（任意・未実施）。

---

## 要確認 / フォローアップ

- **ja-jp スクリーンショットの添付状況（未確認）**: 日本語スクショ 3 枚（`installer/store/listing/screenshots-ja/01-home.png` / `02-picker.png` / `03-settings.png`、リポジトリには存在を確認済み）が **ja-jp リスティングに添付されているか**は未確認。今回のインポートは英語 URL 維持・日本語画像なしで通っているため、付いていなければ Partner Center UI から手動アップロードが必要。ただし **Submission 提出後の変更は次の Submission（Submission 2）になる**点に留意。
- 認定結果（合格 / 要修正）を受領したら本ファイルに追記する。
