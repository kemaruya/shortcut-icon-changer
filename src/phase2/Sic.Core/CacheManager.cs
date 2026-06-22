using System.Collections.Generic;
using System.IO;

namespace Sic.Core
{
    /// <summary>
    /// 変換済みアイコン キャッシュ（%LOCALAPPDATA%\ShortcutIconChanger\cache および
    /// starter-extracted）の使用量算出と削除。これらのファイルは適用済み .lnk から参照されることが
    /// あるため、削除すると適用中のカスタム アイコンが既定へ戻る点に注意（呼び出し側で警告する）。
    /// </summary>
    public static class CacheManager
    {
        private static IEnumerable<string> CacheDirs()
        {
            yield return SicPaths.CachePath();
            yield return SicPaths.ExtractedPath();
        }

        /// <summary>キャッシュの合計サイズ（バイト）。</summary>
        public static long GetCacheSizeBytes()
        {
            long total = 0;
            foreach (var dir in CacheDirs())
            {
                if (!Directory.Exists(dir)) continue;
                foreach (var f in Directory.EnumerateFiles(dir, "*", SearchOption.AllDirectories))
                {
                    try { total += new FileInfo(f).Length; } catch { /* 個別失敗は無視 */ }
                }
            }
            return total;
        }

        /// <summary>キャッシュ ファイルを削除し、削除できたファイル数を返す。ディレクトリ自体は残す。</summary>
        public static int ClearCache()
        {
            int removed = 0;
            foreach (var dir in CacheDirs())
            {
                if (!Directory.Exists(dir)) continue;
                foreach (var f in Directory.EnumerateFiles(dir, "*", SearchOption.AllDirectories))
                {
                    try { File.Delete(f); removed++; } catch { /* ロック中などは無視 */ }
                }
            }
            return removed;
        }

        /// <summary>サイズの人間可読表記（B / KB / MB）。</summary>
        public static string FormatSize(long bytes)
        {
            if (bytes < 1024) return bytes + " B";
            double kb = bytes / 1024.0;
            if (kb < 1024) return kb.ToString("0.0") + " KB";
            double mb = kb / 1024.0;
            return mb.ToString("0.0") + " MB";
        }
    }
}
