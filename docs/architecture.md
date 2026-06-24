**English** | [日本語](architecture.ja.md)

# Architecture and design

This document describes the design of **Shortcut Icon Changer**, a tool that changes the icon of a Windows shortcut (`.lnk`) quickly and colorfully from the context menu. It reflects the current implementation (v0.8.x): a **native WPF desktop app** plus an optional **native (C++) modern-menu handler**, distributed as a **per-user MSI** (and, in preparation, a Microsoft Store MSIX). It runs using only frameworks that ship in-box with Windows 10 / 11 — **no extra runtime to install**.

> History: the project began as a Windows PowerShell prototype (kept under `src/phase1` for reference). The shipping product is the native app under `src/phase2`, which this document describes. Where early design notes mentioned a planned ".NET 10 Native AOT" handler, the modern-menu handler is implemented in **C++** instead, and the app itself targets **.NET Framework 4.8** (in-box).

## Design goals

| # | Goal | How it is met today |
|---|------|---------------------|
| R1 | Change a `.lnk`'s icon from the context menu | Legacy verb under `lnkfile\shell` + optional Windows 11 modern menu |
| R2 | Choose from many colorful icons | ~2,570 Microsoft Fluent UI Emoji (3D + Flat) bundled in `icons.zip` |
| R3 | Allow user-supplied `.ico` / `.png` | Picked files are converted to `.ico` on the fly (SVG not supported) |
| R4 | Support the Windows 11 **modern** context menu | Native `IExplorerCommand` handler, opt-in |
| R5 | Use a modern toolset | Native WPF app + WiX 6 MSI + C++ COM handler |
| R6 | **No extra runtime** — built-in Windows features only | Targets in-box .NET Framework 4.8 (WPF, System.Drawing); MSI via msiexec |

R4 and R6 are in tension (the modern menu needs `IExplorerCommand` + packaging — building, self-signing and sideloading), so the modern menu is **optional / opt-in**; the base feature works without it.

## How changing an icon works

A `.lnk` only stores a reference to an "icon location" (`IconLocation` = `"<file>,<index>"`). Rewriting it is a small COM operation via `WScript.Shell`:

```csharp
var shell = (dynamic)Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
var sc = shell.CreateShortcut(lnkPath);
sc.IconLocation = icoPath + ",0";   // "<file>,<icon index>"
sc.Save();
```

`IconLocation` can only point to a file that contains an icon (`.ico` / `.exe` / `.dll`). A PNG cannot be pointed to directly, so a selected PNG is converted to `.ico` on the fly and cached. After writing, `SHChangeNotify(SHCNE_ASSOCCHANGED)` asks the shell to refresh.

## Solution structure

```
src/phase2/
  Sic.Core/          net48 class library — all icon/shortcut logic (no UI)
  Sic.App/           net48 WPF app — ShortcutIconChanger.exe (UI + CLI)
  Sic.Core.Tests/    xUnit tests for Sic.Core
src/shellext/        Sic.ShellExt.cpp — C++ COM IExplorerCommand (modern menu)
src/phase1/          legacy Windows PowerShell prototype (reference only)
installer/wix/       WiX 6 per-user MSI (Package.wxs)
installer/sparse/    sparse MSIX that registers the modern menu (AppxManifest.xml)
installer/store/     full MSIX for Microsoft Store distribution
assets/starter-icons/  icons.zip + icons-index.json (bundled icon set)
tools/               asset pipeline (fetch / rasterize / build the icon set)
build/               build scripts (Build-Phase2.ps1 = native; Build-Package.ps1 = legacy)
```

### Core (`Sic.Core`, .NET Framework 4.8)

A UI-less class library implemented with **in-box framework assemblies only** (`System.Drawing` / GDI+, the `JavaScriptSerializer` from `System.Web.Extensions` for JSON, `System.IO.Compression`) — no third-party NuGet packages.

| Type | Responsibility |
|------|----------------|
| `ShortcutService` | Read / set / reset a `.lnk`'s `IconLocation` via `WScript.Shell` COM; notify the shell with `SHChangeNotify`. |
| `IconConverter` | Convert PNG → a multi-size `.ico` (16/32/48/256, each frame PNG-compressed); cache by SHA-1 content signature under `…\cache`; resolve the **real** on-disk path (`GetFinalPathNameByHandle`) so icons survive sparse-MSIX path redirection. |
| `IconLibrary` / `IconIndex` / `IconItem` | Enumerate the bundled (`icons.zip`) and user-library icons and attach metadata from `icons-index.json` (category, style, colors, keywords, EN/JA names). High Contrast is hidden by default. |
| `IconFilter` | Facet filtering for the picker — OR within a facet (style / genre / color), AND across facets; name/keyword search is done in the view model. |
| `SicAssetZip` | Shared, lock-serialized read access to the bundled `icons.zip` (kept open; entries read on demand). |
| `SicPaths` | Resolves the per-user data layout under `%LOCALAPPDATA%\ShortcutIconChanger`. |
| `AppSettings` / `AppTheme` / `CacheManager` / `SicMaps` / `NativeMethods` | Settings (`settings.json`), theme enum, cache maintenance, EN⇄JA label maps, P/Invoke. |

### App (`Sic.App`, WPF, `ShortcutIconChanger.exe`)

`WinExe`, `net48`, `UseWPF` + `UseWindowsForms`. The entry point (`App.xaml.cs`) parses arguments and branches:

- `-Reset`, or `-IconPath <file>` (with `-Lnk <file>` or a positional `.lnk`) → apply directly, **with no UI** (used by the context menu and by scripts).
- a `.lnk` argument only → open the **picker** for that target and apply the result.
- no arguments → open the **Home** hub.

UI pieces:

- `HomeWindow` — the Start-menu hub (Change icon / Settings).
- `MainWindow` — the icon picker: a **target bar** showing the `.lnk` and its current icon; a **tag cloud** that is single-select within each row (style / genre / color) and AND across rows; a **keyword search box**; and **row-level UI virtualization** so startup stays fast over a large catalog.
- `SettingsWindow` — language, theme, the default folder used when picking a target from Home (Desktop / Start menu / custom), and cache management.
- `ThemeManager` / `AppTheme` — Light / Dark / Follow-system across the whole app.
- `DelayedSplash` — shows a splash only when first render is actually slow (a deferred gate), so warm launches don't flash.
- `ContextMenu.TryRepair` — on startup, **self-heals** the right-click verb (icon / label / command) to match the running exe, fixing stale registrations or shell icon-cache breakage (notably on Windows 10). It only updates the key if it already exists, so it never registers anything on a non-installed machine.

The UI is localized in English and Japanese.

### Modern context menu handler (`Sic.ShellExt`, C++)

`Sic.ShellExt.cpp` is a thin native COM server implementing `IExplorerCommand` — raw COM (no WRL/ATL) with the CRT statically linked (`/MT`), so it needs no extra runtime. It adds "Change icon" to the Windows 11 **top-level** menu for a single `.lnk` only (it registers for `Type="*"` and hides itself via `GetState` for non-`.lnk` selections), and on click launches the neighboring `ShortcutIconChanger.exe` with the selected path.

It is registered by a **sparse MSIX** (`installer/sparse/AppxManifest.xml`): `desktop4` / `desktop5:FileExplorerContextMenus` declares the verb, and `com:SurrogateServer` hosts the DLL in `dllhost`. `AllowExternalContent` lets the package reference the real payload in the MSI install directory instead of copying it. The package is signed with a **self-signed certificate** (`CN=kemaruya`) and sideloaded.

One subtlety: a child process launched from the packaged surrogate inherits the package identity, which redirects `%LOCALAPPDATA%` writes to `…\Packages\<PFN>\LocalCache\…`. Two builds handle this differently:

- **GitHub / MSI (sparse) build — default:** the handler launches the app **reparented to `explorer.exe`** with `DESKTOP_APP_BREAKAWAY`, stripping the package identity so writes land in the real `%LOCALAPPDATA%` and match the path written into the `.lnk`. (Otherwise Explorer can't find the icon file and the shortcut shows blank.)
- **Store (full MSIX) build — `SIC_STORE`:** it keeps the container identity (natural for Store review); instead the app resolves the real on-disk path (`GetFinalPathNameByHandle`, in `IconConverter`) before writing the `.lnk`, so the icon still resolves.

## Packaging & distribution

- **Per-user MSI** (`installer/wix/Package.wxs`, WiX 6): `Scope="perUser"`, `WixUI_Minimal`, installs to `%LOCALAPPDATA%\Programs\ShortcutIconChanger` with **no admin / no UAC**. It registers the legacy `.lnk` verb under `HKCU\Software\Classes\lnkfile\shell\sic.changeicon`. The finish screen has an **opt-in checkbox** (off by default) to enable the modern menu; checking it runs `Enable-ModernMenu.ps1`, which elevates once to trust the certificate and register the sparse MSIX.
- **Microsoft Store MSIX** (`installer/store`): a full, Store-signed MSIX. **Distribution is in preparation** (see `installer/store/STORE-SUBMISSION.md` and `SUBMISSION-LOG.md`).

### Build scripts

- `build/Build-Phase2.ps1` — the main build: MSBuild-Release `Sic.App`, optionally run the xUnit tests (`-RunTests`), build `Sic.ShellExt.dll` and the signed sparse MSIX, stage `exe` + `Sic.Core.dll` + `assets\starter-icons` (+ modern-menu files), then produce `dist\ShortcutIconChanger-X.Y.Z-perUser.msi` with WiX. Requires Visual Studio MSBuild and the WiX 6 global tool; neither is needed by end users.
- `installer/store/Build-Store.ps1` — builds the full Store MSIX.
- `build/Build-Package.ps1` — packages the **legacy Phase 1** PowerShell prototype as a ZIP (kept for reference only).

## Icon library & asset pipeline

The bundled icons are **Microsoft Fluent UI Emoji (MIT)** — nearly the whole set in two styles, **3D and Flat (~2,570 icons)** — packed into a single `assets/starter-icons/icons.zip` so a user can pick one with no internet connection. `icons-index.json` carries per-icon metadata (category / style / colors / keywords and EN/JA names); High Contrast is excluded by default. The set is produced by the `tools/` pipeline: `Fetch-FluentEmoji.ps1` (download), `rasterize.js` (SVG→PNG via resvg), `Build-StarterSet.ps1` (assemble the zip + index) and `Build-NamesJa.ps1` (Japanese names). Users can also drop their own `.ico` / `.png` into `%LOCALAPPDATA%\ShortcutIconChanger\library`, or pick any `.ico` / `.png` file directly.

## Per-user data layout

```
%LOCALAPPDATA%\ShortcutIconChanger\
  library\             user-supplied icons (+ optional icons-index.json)
  cache\               generated .ico files (named by SHA-1 content signature)
  starter-extracted\   bundled icons materialized on demand when applied
  settings.json        language / theme / default folder / etc.
```

## Requirements

- **End users:** Windows 10 version 22H2, or Windows 11; **nothing to install** (in-box .NET Framework 4.8). The "Change icon" verb works on both Windows 10 and 11; the **modern top-level menu is Windows 11 only**.
- **Developers (build):** Visual Studio 2022/2026 MSBuild, the WiX 6 global tool (`dotnet tool install --global wix`), the C++ build tools for `Sic.ShellExt`, and the .NET test SDK for the xUnit tests.

## Tests

`Sic.Core.Tests` (xUnit) covers the core: `CoreTests`, `LibraryTests`, `ShortcutTests`. Run them with `dotnet test`, or via `build/Build-Phase2.ps1 -RunTests`.

## Known limitations / TODO

- **SVG is not supported** — only `.ico` and `.png` (PNG is converted on the fly).
- The **modern menu requires trusting a self-signed certificate** (a one-time admin elevation) and is therefore opt-in; the legacy verb needs no admin.
- **High Contrast** Fluent icons are hidden by default (kept in the assets/index, excluded from the listing, facets and search).
