using System;
using System.IO;
using System.Runtime.InteropServices;
using Sic.Core;
using Xunit;

namespace Sic.Core.Tests
{
    /// <summary>WScript.Shell COM 経由の .lnk アイコン設定/既定化を検証。</summary>
    public class ShortcutTests
    {
        private static string CreateTempLnk()
        {
            var lnk = TestHelpers.TempPath(".lnk");
            var t = Type.GetTypeFromProgID("WScript.Shell");
            object? sh = Activator.CreateInstance(t!);
            dynamic wsh = sh!;
            dynamic sc = wsh.CreateShortcut(lnk);
            sc.TargetPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
            sc.Save();
            Marshal.FinalReleaseComObject(sc);
            Marshal.FinalReleaseComObject(sh);
            return lnk;
        }

        private static string ReadIconLocation(string lnk)
        {
            var t = Type.GetTypeFromProgID("WScript.Shell");
            object? sh = Activator.CreateInstance(t!);
            dynamic wsh = sh!;
            dynamic sc = wsh.CreateShortcut(lnk);
            string loc = sc.IconLocation;
            Marshal.FinalReleaseComObject(sc);
            Marshal.FinalReleaseComObject(sh);
            return loc;
        }

        [Fact]
        public void SetIcon_Then_ResetIcon()
        {
            var lnk = CreateTempLnk();
            var png = TestHelpers.CreateTempPng();
            try
            {
                var setRes = ShortcutService.SetIcon(lnk, png, 0);
                Assert.EndsWith(".ico", setRes.IconPath);
                var loc = ReadIconLocation(lnk);
                Assert.Contains(",0", loc);
                Assert.False(loc.StartsWith(","), "アイコン パスが空です: " + loc);

                var resetRes = ShortcutService.ResetIcon(lnk);
                Assert.True(resetRes.IsReset);
                Assert.Equal(",0", ReadIconLocation(lnk));
            }
            finally { File.Delete(lnk); File.Delete(png); }
        }

        [Fact]
        public void SetIcon_RejectsNonLnk()
        {
            var txt = TestHelpers.TempPath(".txt");
            File.WriteAllText(txt, "x");
            var png = TestHelpers.CreateTempPng();
            try
            {
                Assert.Throws<ArgumentException>(() => ShortcutService.SetIcon(txt, png));
            }
            finally { File.Delete(txt); File.Delete(png); }
        }
    }
}
