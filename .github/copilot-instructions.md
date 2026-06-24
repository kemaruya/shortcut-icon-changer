# Copilot instructions — shortcut-icon-changer

Repo-wide guidance for GitHub Copilot sessions working in this repository.

## Documentation is bilingual (English + Japanese) / ドキュメントは英日 2 言語

The app is localized in **Japanese and English**, so its user-facing documentation must be maintained in **both languages and kept in sync**. When you add or edit any user-facing doc, update **both** language versions in the same change. Do not let one language drift from the other.

アプリは日本語・英語にローカライズされています。ユーザー向けドキュメントは**英日両方で整備し、常に同期**させてください。ドキュメントを追加・編集するときは、同じ変更の中で**両言語**を更新します。一方だけ更新して片方を古いままにしないこと。

### Primary language and file layout

English is the **primary** language (it is what GitHub shows by default and maximizes international / Microsoft Store reach). Each user-facing doc has an English primary file and a Japanese counterpart, cross-linked with a language switcher on the first line.

| Doc | English (primary) | Japanese |
| --- | --- | --- |
| README | `README.md` | `README.ja.md` |
| Architecture | `docs/architecture.md` | `docs/architecture.ja.md` |
| Privacy policy | `docs/privacy.md` (single bilingual file: EN then JA) | same file |
| Third-party notices | `THIRD-PARTY-NOTICES.md` (EN license text is canonical; short JA intro) | same file |

### Conventions

- **Language switcher**: put it on the very first line of each split doc.
  - In the English file: `**English** | [日本語](README.ja.md)`
  - In the Japanese file: `[English](README.md) | **日本語**`
  - Point the link at the matching counterpart (e.g., `architecture.md` ↔ `architecture.ja.md`).
- **`privacy.md`** stays a single bilingual file (English section, then Japanese), because it is used as one external privacy-policy URL for the Microsoft Store. Keep the in-page `#en` / `#ja` jump links and update both sections together.
- **`THIRD-PARTY-NOTICES.md`**: license texts (e.g., MIT) are legal notices — keep them in the **original English** as the canonical version; a brief Japanese intro line is fine, but do not translate the license body.
- **Screenshots**: the README screenshots are language-specific. English README (`README.md`) uses `docs/images/en/` (English-UI window screenshots); Japanese README (`README.ja.md`) uses `docs/images/` (Japanese-UI). When you update one language's screenshots, capture/update the other language's set too so they stay in sync. Store-listing screenshots live separately under `installer/store/listing/screenshots-en` and `screenshots-ja` (full 1920×1080 with caption/background); the README uses clean window-only crops, not the store-framed images.
- **License-neutral files** (`LICENSE`, `VERSION`) need no translation.
- When you change product behavior, update the relevant section in **both** the English and Japanese docs (README features/changelog, architecture, etc.).
- New user-facing docs: create `<name>.md` (English) + `<name>.ja.md` (Japanese) with the switcher, following the same pattern.

### Scope

- **In scope (must be bilingual)**: user-facing docs — `README*`, everything under `docs/` that documents the product, `THIRD-PARTY-NOTICES.md`.
- **Out of scope (Japanese-only is fine)**: internal operational records under `installer/store/` (e.g., `STORE-SUBMISSION.md`, `SUBMISSION-LOG.md`) — these are owner/operator process notes. Translate them only if explicitly requested.

## Other notes

- The app targets **.NET Framework 4.8 / WPF (C#)** and ships as a per-user MSI (with an optional self-signed sparse MSIX for the Windows 11 modern context menu) and a full MSIX for the Microsoft Store.
- UI strings and icon display names are localized for JA/EN; when adding user-visible strings, provide both locales.
