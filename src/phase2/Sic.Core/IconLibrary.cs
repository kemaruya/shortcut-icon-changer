using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Sic.Core
{
    /// <summary>
    /// スターター＋ユーザー ライブラリのアイコンを列挙し、icons-index.json のメタデータを付与する
    /// （SicCore.psm1 の Get-IconLibrary を移植）。ファイル名（拡張子なし）で重複排除（先勝ち）。
    /// </summary>
    public static class IconLibrary
    {
        private static readonly string[] DefaultExts = { ".ico", ".png" };

        /// <summary>
        /// 既定でアプリから非表示にするスタイル（正規＝英語キー）。アセットとインデックスは残すが、
        /// 列挙から除外して一覧・ファセット・検索のいずれにも出さない。
        /// ハイコントラストは使用率が低いため既定で非表示。
        /// </summary>
        public static readonly ISet<string> HiddenStyles =
            new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "High Contrast" };

        public static List<IconItem> Enumerate(string[]? extensions = null)
        {
            var exts = new HashSet<string>(
                (extensions ?? DefaultExts).Select(e => e.ToLowerInvariant()));

            var idx = IconIndex.Load();
            var results = new List<IconItem>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            foreach (var rec in EnumerateSources())
            {
                var ext = rec.Ext.ToLowerInvariant();
                if (!exts.Contains(ext)) continue;

                var key = rec.Key;

                idx.TryGetValue(key, out var meta);

                // 既定で非表示のスタイル（例: ハイコントラスト）はアプリから除外する。
                // アセット/インデックスは残すが、一覧・ファセット・検索のいずれにも出さない。
                var styleKey = meta?.Style ?? "";
                if (!string.IsNullOrEmpty(styleKey) && HiddenStyles.Contains(styleKey))
                    continue;

                if (!seen.Add(key)) continue; // first wins (OrdinalIgnoreCase)

                var item = new IconItem
                {
                    Name = key,
                    Path = rec.FilePath,
                    ZipPath = rec.ZipPath,
                    ZipEntry = rec.ZipEntry,
                    Source = rec.Source,
                    Extension = ext,
                    Category = meta?.Category ?? "",
                    CategoryJa = meta?.CategoryJa ?? "",
                    Colors = meta?.Colors ?? new List<string>(),
                    Keywords = meta?.Keywords ?? new List<string>(),
                    Style = meta?.Style ?? "",
                    StyleJa = meta?.StyleJa ?? "",
                    NameJa = meta?.NameJa,
                };

                if (string.IsNullOrEmpty(item.CategoryJa) && !string.IsNullOrEmpty(item.Category))
                    item.CategoryJa = SicMaps.ToCategoryJa(item.Category);
                if (string.IsNullOrEmpty(item.StyleJa) && !string.IsNullOrEmpty(item.Style))
                    item.StyleJa = SicMaps.ToStyleJa(item.Style);

                // 英語名は index の nameEn を優先、無ければファイル名からスタイル接尾辞を除去。
                item.NameEnBase = !string.IsNullOrEmpty(meta?.NameEn)
                    ? meta!.NameEn!
                    : StripStyleSuffix(key, item.StyleJa);

                results.Add(item);
            }

            return results.OrderBy(r => r.Name, StringComparer.OrdinalIgnoreCase).ToList();
        }

        /// <summary>列挙元の 1 レコード（loose ファイル または zip エントリ）。</summary>
        private readonly struct SourceRec
        {
            public readonly string Key;
            public readonly string Ext;
            public readonly string FilePath;
            public readonly string Source;
            public readonly string? ZipPath;
            public readonly string? ZipEntry;

            public SourceRec(string key, string ext, string filePath, string source,
                string? zipPath, string? zipEntry)
            {
                Key = key; Ext = ext; FilePath = filePath; Source = source;
                ZipPath = zipPath; ZipEntry = zipEntry;
            }
        }

        /// <summary>
        /// スターター（icons.zip があれば zip エントリ、無ければ loose ファイル）と
        /// ユーザー ライブラリ（常に loose ファイル）を順に列挙する。
        /// </summary>
        private static IEnumerable<SourceRec> EnumerateSources()
        {
            var starterZip = SicPaths.StarterZipPath();
            if (starterZip != null)
            {
                foreach (var entryName in SicAssetZip.EntryNames(starterZip))
                {
                    var ext = Path.GetExtension(entryName);
                    var key = Path.GetFileNameWithoutExtension(entryName);
                    yield return new SourceRec(key, ext, "", "starter", starterZip, entryName);
                }
            }
            else
            {
                var sp = SicPaths.StarterPath();
                if (!string.IsNullOrEmpty(sp) && Directory.Exists(sp))
                    foreach (var f in Directory.EnumerateFiles(sp!, "*", SearchOption.AllDirectories))
                        yield return new SourceRec(
                            Path.GetFileNameWithoutExtension(f), Path.GetExtension(f), f, "starter", null, null);
            }

            var lp = SicPaths.LibraryPath();
            if (!string.IsNullOrEmpty(lp) && Directory.Exists(lp))
                foreach (var f in Directory.EnumerateFiles(lp, "*", SearchOption.AllDirectories))
                    yield return new SourceRec(
                        Path.GetFileNameWithoutExtension(f), Path.GetExtension(f), f, "library", null, null);
        }

        /// <summary>"Rocket (フラット)" → "Rocket"。3D（接尾辞なし）はそのまま。</summary>
        public static string StripStyleSuffix(string name, string styleJa)
        {
            if (!string.IsNullOrEmpty(styleJa))
            {
                var suffix = " (" + styleJa + ")";
                if (name.EndsWith(suffix, StringComparison.Ordinal))
                    return name.Substring(0, name.Length - suffix.Length);
            }
            return name;
        }
    }
}
