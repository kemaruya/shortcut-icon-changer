using System;
using System.IO;
using System.Runtime.InteropServices;

namespace Sic.Core
{
    public sealed class ShortcutResult
    {
        public string LnkPath = "";
        public string IconPath = "";
        public int Index;
        public bool IsReset;
    }

    /// <summary>
    /// .lnk のアイコンを WScript.Shell COM 経由で設定/既定化（SicCore.psm1 の
    /// Set-ShortcutIcon / Reset-ShortcutIcon を移植）。適用後 SHChangeNotify で Explorer へ通知。
    /// </summary>
    public static class ShortcutService
    {
        public static ShortcutResult SetIcon(string lnkPath, string iconPath, int index = 0)
        {
            var lnkFull = ValidateLnk(lnkPath);
            if (!File.Exists(iconPath))
                throw new FileNotFoundException("アイコンファイルが見つかりません: " + iconPath);

            var resolved = IconConverter.GetCachedIcon(iconPath);
            WriteIconLocation(lnkFull, resolved + "," + index);
            NotifyShell();
            return new ShortcutResult { LnkPath = lnkFull, IconPath = resolved, Index = index };
        }

        /// <summary>既定に戻す。空文字は COM が拒否するため ",0"（空パス・索引0）を書き込む。</summary>
        public static ShortcutResult ResetIcon(string lnkPath)
        {
            var lnkFull = ValidateLnk(lnkPath);
            WriteIconLocation(lnkFull, ",0");
            NotifyShell();
            return new ShortcutResult { LnkPath = lnkFull, IconPath = "", Index = 0, IsReset = true };
        }

        /// <summary>
        /// .lnk の現在の IconLocation を (パス, 索引) で読み取る。プレビュー表示用。
        /// 既定（未設定）の場合はパスが空文字になる。読み取り失敗時は ("", 0)。
        /// </summary>
        public static (string Path, int Index) ReadIconLocation(string lnkPath)
        {
            var lnkFull = ValidateLnk(lnkPath);
            var type = Type.GetTypeFromProgID("WScript.Shell");
            if (type == null) return ("", 0);

            object? shell = null;
            try
            {
                shell = Activator.CreateInstance(type);
                dynamic wsh = shell!;
                dynamic sc = wsh.CreateShortcut(lnkFull);
                string loc = sc.IconLocation as string ?? "";
                Marshal.FinalReleaseComObject(sc);

                int comma = loc.LastIndexOf(',');
                if (comma < 0) return (loc.Trim(), 0);
                var path = loc.Substring(0, comma).Trim();
                int.TryParse(loc.Substring(comma + 1).Trim(), out var idx);
                return (path, idx);
            }
            catch { return ("", 0); }
            finally { if (shell != null) Marshal.FinalReleaseComObject(shell); }
        }

        private static string ValidateLnk(string lnkPath)
        {
            if (!File.Exists(lnkPath))
                throw new FileNotFoundException("ショートカットが見つかりません: " + lnkPath);
            var full = Path.GetFullPath(lnkPath);
            if (!string.Equals(Path.GetExtension(full), ".lnk", StringComparison.OrdinalIgnoreCase))
                throw new ArgumentException("対象は .lnk ファイルではありません: " + full);
            return full;
        }

        private static void WriteIconLocation(string lnkFull, string iconLocation)
        {
            var type = Type.GetTypeFromProgID("WScript.Shell");
            if (type == null)
                throw new InvalidOperationException("WScript.Shell を生成できません。");

            object? shell = null;
            try
            {
                shell = Activator.CreateInstance(type);
                dynamic wsh = shell!;
                dynamic sc = wsh.CreateShortcut(lnkFull);
                sc.IconLocation = iconLocation;
                sc.Save();
                Marshal.FinalReleaseComObject(sc);
            }
            finally
            {
                if (shell != null) Marshal.FinalReleaseComObject(shell);
            }
        }

        private static void NotifyShell()
        {
            NativeMethods.SHChangeNotify(
                NativeMethods.SHCNE_ASSOCCHANGED, NativeMethods.SHCNF_IDLIST,
                IntPtr.Zero, IntPtr.Zero);
        }
    }
}
