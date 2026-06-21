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

            var sources = new (string? Path, string Source)[]
            {
                (SicPaths.StarterPath(), "starter"),
                (SicPaths.LibraryPath(), "library"),
            };

            foreach (var (path, source) in sources)
            {
                if (string.IsNullOrEmpty(path) || !Directory.Exists(path)) continue;

                foreach (var file in Directory.EnumerateFiles(path!, "*", SearchOption.AllDirectories))
                {
                    var ext = Path.GetExtension(file).ToLowerInvariant();
                    if (!exts.Contains(ext)) continue;

                    var key = Path.GetFileNameWithoutExtension(file);

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
                        Path = file,
                        Source = source,
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
            }

            return results.OrderBy(r => r.Name, StringComparer.OrdinalIgnoreCase).ToList();
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
