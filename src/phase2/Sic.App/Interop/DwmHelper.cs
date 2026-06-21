using System;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Sic.App.Interop
{
    /// <summary>Win11 のモダン外観（ダーク タイトルバー）をベストエフォートで適用する。</summary>
    internal static class DwmHelper
    {
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

        public static bool IsSystemDark()
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                var v = key?.GetValue("AppsUseLightTheme");
                if (v is int i) return i == 0;
            }
            catch { }
            return false;
        }

        public static void TryApplyDarkTitleBar(IntPtr hwnd, bool dark)
        {
            try
            {
                int val = dark ? 1 : 0;
                DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ref val, sizeof(int));
            }
            catch { }
        }
    }
}
