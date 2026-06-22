using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Sic.Core
{
    /// <summary>
    /// PNG→マルチサイズ ICO 変換とキャッシュ（SicCore.psm1 の Convert-ToIco / Write-IcoFile /
    /// Get-SicCachedIcon を移植）。System.Drawing(GDI+) のみ使用、外部依存なし。
    /// </summary>
    public static class IconConverter
    {
        private static readonly int[] DefaultSizes = { 16, 32, 48, 256 };

        public static string ConvertToIco(string sourcePath, string destPath, int[]? sizes = null)
        {
            if (!File.Exists(sourcePath))
                throw new FileNotFoundException("ソース画像が見つかりません: " + sourcePath);

            var ext = Path.GetExtension(sourcePath).ToLowerInvariant();
            if (ext == ".ico")
            {
                File.Copy(sourcePath, destPath, true);
                return destPath;
            }
            if (ext == ".svg")
                throw new NotSupportedException("SVG はサポートされていません。.ico または .png を指定してください。");

            var useSizes = (sizes ?? DefaultSizes).Distinct().OrderBy(s => s).ToArray();
            var images = new List<byte[]>(useSizes.Length);

            using (var src = new Bitmap(sourcePath))
            {
                foreach (var size in useSizes)
                {
                    using var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
                    using (var g = Graphics.FromImage(bmp))
                    {
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.SmoothingMode = SmoothingMode.HighQuality;
                        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                        g.CompositingQuality = CompositingQuality.HighQuality;
                        g.Clear(Color.Transparent);
                        g.DrawImage(src, 0, 0, size, size);
                    }
                    using var ms = new MemoryStream();
                    bmp.Save(ms, ImageFormat.Png);
                    images.Add(ms.ToArray());
                }
            }

            WriteIco(destPath, images, useSizes);
            return destPath;
        }

        /// <summary>PNG フレーム列を ICO コンテナとして書き出す（各フレームは PNG 圧縮で格納）。</summary>
        public static void WriteIco(string destPath, IReadOnlyList<byte[]> pngImages, int[] sizes)
        {
            int count = pngImages.Count;
            using var fs = new FileStream(destPath, FileMode.Create, FileAccess.Write);
            using var bw = new BinaryWriter(fs);

            // ICONDIR
            bw.Write((ushort)0); // reserved
            bw.Write((ushort)1); // type = icon
            bw.Write((ushort)count);

            int dataOffset = 6 + 16 * count;
            for (int i = 0; i < count; i++)
            {
                int size = sizes[i];
                var bytes = pngImages[i];
                byte dim = (byte)(size >= 256 ? 0 : size); // 256 は 0 で表現

                // ICONDIRENTRY
                bw.Write(dim);            // width
                bw.Write(dim);            // height
                bw.Write((byte)0);        // color count
                bw.Write((byte)0);        // reserved
                bw.Write((ushort)1);      // planes
                bw.Write((ushort)32);     // bit count
                bw.Write((uint)bytes.Length);
                bw.Write((uint)dataOffset);
                dataOffset += bytes.Length;
            }

            foreach (var bytes in pngImages) bw.Write(bytes);
            bw.Flush();
        }

        /// <summary>
        /// .ico/.exe/.dll はそのまま、それ以外は内容シグネチャ(SHA1)でキャッシュした .ico を返す。
        /// </summary>
        public static string GetCachedIcon(string sourcePath)
        {
            var full = Path.GetFullPath(sourcePath);
            var ext = Path.GetExtension(full).ToLowerInvariant();
            if (ext == ".ico" || ext == ".exe" || ext == ".dll") return full;

            var fi = new FileInfo(full);
            var sig = $"{full}|{fi.Length}|{fi.LastWriteTimeUtc.Ticks}";

            string hash;
            using (var sha = SHA1.Create())
            {
                var hb = sha.ComputeHash(Encoding.UTF8.GetBytes(sig));
                var sb = new StringBuilder(hb.Length * 2);
                foreach (var b in hb) sb.Append(b.ToString("x2"));
                hash = sb.ToString();
            }

            var dest = Path.Combine(SicPaths.CachePath(), hash + ".ico");
            if (!File.Exists(dest)) ConvertToIco(full, dest);
            return ResolveRealPath(dest);
        }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern uint GetFinalPathNameByHandleW(
            SafeFileHandle hFile, StringBuilder lpszFilePath, uint cchFilePath, uint dwFlags);

        /// <summary>
        /// 与えられたパスのファイルを開き、OS が解決した「実体パス」を返す。
        /// パッケージ(スパース MSIX)の ID を持つプロセスから %LOCALAPPDATA% へ書くと、書き込みは
        /// Packages\&lt;PFN&gt;\LocalCache\... へ透過リダイレクトされるが、パス文字列は非リダイレクト形のまま
        /// になる。.lnk の IconLocation に非リダイレクト形を書くと、ID を持たない Explorer が実ファイルを
        /// 見つけられず白く表示される。そこで実際に書かれた物理パスを取得して .lnk へ記録する。
        /// ID 無し(通常起動)の場合は通常の %LOCALAPPDATA% パスがそのまま返り、いずれの経路でも整合する。
        /// </summary>
        private static string ResolveRealPath(string path)
        {
            try
            {
                using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read,
                                               FileShare.ReadWrite | FileShare.Delete))
                {
                    const uint FILE_NAME_NORMALIZED = 0x0;
                    var sb = new StringBuilder(600);
                    uint len = GetFinalPathNameByHandleW(fs.SafeFileHandle, sb, (uint)sb.Capacity, FILE_NAME_NORMALIZED);
                    if (len == 0) return path;
                    if (len > sb.Capacity)
                    {
                        sb = new StringBuilder((int)len + 1);
                        len = GetFinalPathNameByHandleW(fs.SafeFileHandle, sb, (uint)sb.Capacity, FILE_NAME_NORMALIZED);
                        if (len == 0) return path;
                    }
                    var real = sb.ToString();
                    if (real.StartsWith(@"\\?\UNC\", StringComparison.Ordinal))
                        real = @"\\" + real.Substring(8);
                    else if (real.StartsWith(@"\\?\", StringComparison.Ordinal))
                        real = real.Substring(4);
                    return real;
                }
            }
            catch
            {
                return path;
            }
        }
    }
}
