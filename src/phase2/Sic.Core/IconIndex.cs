using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

namespace Sic.Core
{
    /// <summary>icons-index.json の 1 エントリ分メタデータ。</summary>
    public sealed class IconMeta
    {
        public string Category = "";
        public string CategoryJa = "";
        public string Style = "";
        public string StyleJa = "";
        public string? NameEn;
        public string? NameJa;
        public List<string> Colors = new List<string>();
        public List<string> Keywords = new List<string>();
    }

    /// <summary>
    /// スターター/ライブラリの icons-index.json を読み、ファイル名キー→メタデータ辞書を返す。
    /// in-box の JavaScriptSerializer を使用し外部 JSON ライブラリに依存しない。
    /// </summary>
    public static class IconIndex
    {
        public static Dictionary<string, IconMeta> Load()
        {
            var map = new Dictionary<string, IconMeta>(StringComparer.OrdinalIgnoreCase);

            var files = new List<string>();
            var sp = SicPaths.StarterPath();
            if (sp != null) files.Add(Path.Combine(sp, "icons-index.json"));
            files.Add(Path.Combine(SicPaths.LibraryPath(), "icons-index.json"));

            var ser = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
            foreach (var f in files)
            {
                if (!File.Exists(f)) continue;

                object? parsed;
                try { parsed = ser.DeserializeObject(File.ReadAllText(f, Encoding.UTF8)); }
                catch { continue; }

                if (parsed is not Dictionary<string, object> root) continue;
                if (!root.TryGetValue("icons", out var iconsObj) ||
                    iconsObj is not Dictionary<string, object> icons) continue;

                foreach (var kv in icons)
                {
                    if (map.ContainsKey(kv.Key)) continue; // first wins
                    if (kv.Value is not Dictionary<string, object> m) continue;
                    map[kv.Key] = ToMeta(m);
                }
            }
            return map;
        }

        private static IconMeta ToMeta(Dictionary<string, object> m)
        {
            var meta = new IconMeta();
            if (m.TryGetValue("category", out var c)) meta.Category = c?.ToString() ?? "";
            if (m.TryGetValue("categoryJa", out var cj)) meta.CategoryJa = cj?.ToString() ?? "";
            if (m.TryGetValue("style", out var s)) meta.Style = s?.ToString() ?? "";
            if (m.TryGetValue("styleJa", out var sj)) meta.StyleJa = sj?.ToString() ?? "";
            if (m.TryGetValue("nameEn", out var ne)) meta.NameEn = ne?.ToString();
            if (m.TryGetValue("nameJa", out var nj)) meta.NameJa = nj?.ToString();
            if (m.TryGetValue("colors", out var col)) meta.Colors = ToStringList(col);
            if (m.TryGetValue("keywords", out var kw)) meta.Keywords = ToStringList(kw);
            return meta;
        }

        private static List<string> ToStringList(object? o)
        {
            var list = new List<string>();
            if (o is object[] arr)
            {
                foreach (var e in arr)
                {
                    var s = e?.ToString();
                    if (!string.IsNullOrEmpty(s)) list.Add(s!);
                }
            }
            return list;
        }
    }
}
