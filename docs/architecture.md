**English** | [日本語](architecture.ja.md)

# Architecture and design

This document summarizes the design of a tool for changing the icon of a `.lnk` (Windows shortcut) quickly and colorfully from the context menu.

## Requirements

| # | Requirement | Origin |
|---|------|------|
| R1 | Change a `.lnk`'s icon from the context menu | Original request |
| R2 | Choose from many colorful icons | Original request (the OS set is uniform in color and limited in number) |
| R3 | Also allow user-supplied `.ico` / `.png` / (future) `.svg` | Design agreement |
| R4 | Support the Windows 11 **new (modern) context menu** | Design agreement |
| R5 | Implement with a **modern toolset** where possible | Additional request |
| R6 | Run with **no extra runtime to install — using only built-in Windows 11 features** (if possible) | Additional request (highest priority) |

R4 and R6 are in tension (the modern menu requires `IExplorerCommand` + packaging, which entails building, self-signing, and sideloading). For this reason a **phased implementation** is adopted.

## Basic principle of icons

A `.lnk` itself only holds a reference to an "icon location" (IconLocation). Rewriting it is a one-line COM operation.

```powershell
$sh  = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut($lnkPath)
$lnk.IconLocation = "$icoPath,0"   # "<file>,<icon index>"
$lnk.Save()
```

`IconLocation` can only point to a file that contains an icon (`.ico` / `.exe` / `.dll`). PNG cannot be pointed to directly, so a selected PNG is converted to `.ico` on the fly and cached.

## Icon sources

- **Bundled / fetched library**: Microsoft Fluent UI Emoji (3D style, PNG raster, MIT, ~1,300 icons). Rich in color and ideal for "judging contents by a picture".
  - Phase 1 has no in-box SVG rasterizer, so it uses the **3D style**, which is provided as PNG (Flat / Color / High Contrast are SVG only).
  - The repository bundles only a small starter set (`assets/starter-icons/`).
  - The full set is fetched by `tools/Fetch-FluentEmoji.ps1` into `%LOCALAPPDATA%\ShortcutIconChanger\library`.
- **Custom**: user-supplied `.ico` / `.png` (`.svg` in Phase 1.5). PNG / SVG are converted to `.ico` on the fly.

## Phase 1 — built-in Windows 11 features only (no extra runtime / build / signing)

A "works right now" version that satisfies R1, R2, R3, and R6. It does not satisfy R4 (modern menu) and appears in the legacy menu ("Show more options").

### Structure

```
.lnk right-click
  └─ HKCU\Software\Classes\lnkfile\shell\sic.ChangeIcon\command
        └─ powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass
               -File Launch-IconPicker.ps1 -LnkPath "%1"
                 ├─ IconPicker.ps1  … select via WPF grid (bundled .NET FW 4.8)
                 └─ SicCore.psm1    … Convert-ToIco / Set-ShortcutIcon / SHChangeNotify
```

### Why it works with built-in features only (R6)

| Capability needed | What it uses | Extra install |
|---|---|---|
| Script execution | **Windows PowerShell 5.1** (`powershell.exe`, ships with the OS) | Not required |
| Picker UI | **WPF in .NET Framework 4.8** (PresentationFramework, ships with the OS) | Not required |
| Image conversion | **System.Drawing** (GDI+, ships with the OS) | Not required |
| `.lnk` rewriting | **WScript.Shell COM** (ships with the OS) | Not required |
| Menu registration | Registry `HKCU` (no administrator rights) | Not required |

> Important: launch via **`powershell.exe` (5.1)**, not PowerShell 7 (`pwsh.exe`, installed separately), because what ships with a plain Windows 11 is 5.1. Scripts are written to be 5.1-compatible (WPF requires STA → it works under 5.1's default STA).

### PNG → ICO conversion

`System.Drawing` resizes to multiple sizes (16/32/48/256) and an ICO container is generated in-house (each entry is stored as PNG-encoded; Windows 11 can read PNG-compressed entries). The result is cached under `%LOCALAPPDATA%\ShortcutIconChanger\cache` with a hash-based name.

### Refreshing the icon cache

After rewriting, `SHChangeNotify(SHCNE_ASSOCCHANGED)` is called via P/Invoke to prompt the shell to reflect the change.

## Phase 2 — modern menu support (still no extra runtime)

Satisfies R4. To keep R5 and R6, it is implemented with **.NET 10 Native AOT** (Native AOT produces a self-contained native DLL, so a separate .NET runtime install is not required).

### Structure

- A COM server implementing `IExplorerCommand` (C#, **Native AOT**, `PublishAot=true`).
- Registration via a **sparse MSIX** package (`desktop4:FileExplorerContextMenus` / `com:ComServer` in `Package.appxmanifest`).
- Sideloaded with a self-signed certificate (MSIX signing / sideloading are built-in Windows 11 features, not an added runtime).
- The icon conversion / application / library-enumeration logic is implemented on the C# side equivalently to the Phase 1 core, or shared as a common specification.

### Build toolchain

- .NET SDK 10 (confirmed)
- `makeappx` / `signtool`: not installed, so provided via `Microsoft.Windows.SDK.BuildTools` (NuGet, lightweight) — only at the developer's build time; not needed by end users.

## Known limitations / TODO

- SVG rasterization does not exist in-box, so Phase 1 supports only `.ico` / `.png`. SVG is targeted for Phase 1.5 (candidates: use the already-fetched Fluent PNGs / WIC / a lightweight converter).
- The Phase 1 menu appears on the legacy side (the modern menu is Phase 2).
- Multi-language display names and icon index (`,N`) support are to be considered later.
