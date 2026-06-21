using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;

namespace Sic.Core
{
    /// <summary>
    /// スターター アイコンを束ねた読み取り専用 zip への共有アクセス。
    /// 1 つの <see cref="ZipArchive"/> を開きっぱなしにし（エントリ列挙はメタデータのみで軽量）、
    /// サムネイル/適用時に該当エントリのバイト列を取り出す。
    /// <see cref="ZipArchive"/> は同時読み取り非対応のため、読み取りはロックで直列化する。
    /// バイト列はキャッシュしない（サムネイルはデコード後に破棄され、各タイル 1 回だけ読むため）。
    /// </summary>
    public static class SicAssetZip
    {
        private static readonly object _lock = new object();
        private static string? _zipPath;
        private static ZipArchive? _archive;
        private static Dictionary<string, ZipArchiveEntry>? _entries;

        private static void EnsureOpen(string zipPath)
        {
            if (_archive != null &&
                string.Equals(_zipPath, zipPath, StringComparison.OrdinalIgnoreCase))
                return;

            _archive?.Dispose();
            _archive = ZipFile.OpenRead(zipPath);
            _zipPath = zipPath;
            _entries = new Dictionary<string, ZipArchiveEntry>(StringComparer.Ordinal);
            foreach (var e in _archive.Entries) _entries[e.FullName] = e;
        }

        /// <summary>zip 内の全エントリ名（ディレクトリ エントリは含まない）。</summary>
        public static IReadOnlyList<string> EntryNames(string zipPath)
        {
            lock (_lock)
            {
                EnsureOpen(zipPath);
                return _entries!.Keys
                    .Where(n => !n.EndsWith("/", StringComparison.Ordinal))
                    .ToList();
            }
        }

        /// <summary>エントリのバイト列を返す（存在しなければ null）。</summary>
        public static byte[]? ReadEntry(string zipPath, string entryName)
        {
            lock (_lock)
            {
                EnsureOpen(zipPath);
                if (!_entries!.TryGetValue(entryName, out var entry)) return null;
                using var s = entry.Open();
                using var ms = new MemoryStream();
                s.CopyTo(ms);
                return ms.ToArray();
            }
        }

        /// <summary>
        /// エントリを <paramref name="destDir"/> に実ファイルとして取り出し、そのパスを返す。
        /// 既に同じサイズで存在すれば書き直さない（適用時のアイコン キャッシュを安定させる）。
        /// </summary>
        public static string? Materialize(string zipPath, string entryName, string destDir)
        {
            var bytes = ReadEntry(zipPath, entryName);
            if (bytes == null) return null;
            Directory.CreateDirectory(destDir);
            var dest = Path.Combine(destDir, entryName);
            try
            {
                if (!File.Exists(dest) || new FileInfo(dest).Length != bytes.Length)
                    File.WriteAllBytes(dest, bytes);
            }
            catch (IOException)
            {
                // 取り出し済みファイルが他プロセスで使用中等。既存をそのまま使う。
                if (!File.Exists(dest)) throw;
            }
            return dest;
        }
    }
}
