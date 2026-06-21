using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

namespace Sic.Core.Tests
{
    internal static class TestHelpers
    {
        public static string? RepoAssets()
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 10 && dir != null; i++, dir = dir.Parent)
            {
                var p = Path.Combine(dir.FullName, "assets", "starter-icons");
                if (Directory.Exists(p)) return p;
            }
            return null;
        }

        public static string CreateTempPng(int w = 64, int h = 64)
        {
            var path = Path.Combine(Path.GetTempPath(), "sic_test_" + Guid.NewGuid().ToString("N") + ".png");
            using var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.Transparent);
                using var br = new SolidBrush(Color.FromArgb(255, 200, 30, 30));
                g.FillEllipse(br, 4, 4, w - 8, h - 8);
            }
            bmp.Save(path, ImageFormat.Png);
            return path;
        }

        public static string TempPath(string ext) =>
            Path.Combine(Path.GetTempPath(), "sic_test_" + Guid.NewGuid().ToString("N") + ext);
    }
}
