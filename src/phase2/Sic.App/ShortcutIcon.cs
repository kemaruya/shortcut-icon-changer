using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Sic.Core;

namespace Sic.App
{
    /// <summary>対象 .lnk の「現在のアイコン」を ImageSource として読み込む（ヘッダーのプレビュー用）。</summary>
    internal static class ShortcutIcon
    {
        /// <summary>
        /// 現在のアイコンを返す。カスタム アイコン設定時はその実体を抽出し、
        /// 既定（未設定）なら .lnk のシェル アイコン（リンク オーバーレイ込み）を返す。失敗時は null。
        /// </summary>
        public static ImageSource? LoadCurrentIcon(string? lnk)
        {
            if (string.IsNullOrEmpty(lnk) || !File.Exists(lnk)) return null;
            try
            {
                var (path, index) = ShortcutService.ReadIconLocation(lnk!);
                return TryExtract(path, index) ?? TryShellIcon(lnk!);
            }
            catch { return null; }
        }

        private static ImageSource? TryExtract(string path, int index)
        {
            if (string.IsNullOrWhiteSpace(path)) return null;
            var expanded = Environment.ExpandEnvironmentVariables(path);
            if (!File.Exists(expanded)) return null;

            var large = new IntPtr[1];
            uint n = ExtractIconEx(expanded, index, large, null, 1);
            if (n == 0 || large[0] == IntPtr.Zero) return null;
            try { return FromHIcon(large[0]); }
            finally { DestroyIcon(large[0]); }
        }

        private static ImageSource? TryShellIcon(string lnk)
        {
            var info = new SHFILEINFO();
            var r = SHGetFileInfo(lnk, 0, ref info, (uint)Marshal.SizeOf(info), SHGFI_ICON | SHGFI_LARGEICON);
            if (r == IntPtr.Zero || info.hIcon == IntPtr.Zero) return null;
            try { return FromHIcon(info.hIcon); }
            finally { DestroyIcon(info.hIcon); }
        }

        private static ImageSource FromHIcon(IntPtr hIcon)
        {
            var src = Imaging.CreateBitmapSourceFromHIcon(hIcon, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            src.Freeze();
            return src;
        }

        // --- interop ---
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern uint ExtractIconEx(string lpszFile, int nIconIndex, IntPtr[]? phiconLarge, IntPtr[]? phiconSmall, uint nIcons);

        [DllImport("user32.dll")]
        private static extern bool DestroyIcon(IntPtr hIcon);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr SHGetFileInfo(string pszPath, uint dwFileAttributes, ref SHFILEINFO psfi, uint cbFileInfo, uint uFlags);

        private const uint SHGFI_ICON = 0x000000100;
        private const uint SHGFI_LARGEICON = 0x000000000;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct SHFILEINFO
        {
            public IntPtr hIcon;
            public int iIcon;
            public uint dwAttributes;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szDisplayName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string szTypeName;
        }
    }
}
