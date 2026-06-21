using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace Sic.Core.Localization
{
    /// <summary>
    /// 言語解決と表示名のローカライズ。既定はユーザー表示言語に追従し、日本語環境のみ日本語、
    /// それ以外は英語へフォールバックする。
    /// </summary>
    public static class Loc
    {
        /// <summary>設定値と現在カルチャから、実効的に日本語表示かどうかを決める。</summary>
        public static bool IsJapanese(AppLanguage pref, CultureInfo? culture = null)
        {
            switch (pref)
            {
                case AppLanguage.Japanese: return true;
                case AppLanguage.English: return false;
                default:
                    var c = culture ?? CultureInfo.CurrentUICulture;
                    return c.TwoLetterISOLanguageName.Equals("ja", StringComparison.OrdinalIgnoreCase);
            }
        }

        // 色調トーン（日本語正規キー）→ 英語表示。
        public static readonly IReadOnlyDictionary<string, string> ToneEn =
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["赤"] = "Red",
                ["橙"] = "Orange",
                ["黄"] = "Yellow",
                ["緑"] = "Green",
                ["青"] = "Blue",
                ["紫"] = "Purple",
                ["桃"] = "Pink",
                ["茶"] = "Brown",
                ["白"] = "White",
                ["灰"] = "Gray",
                ["黒"] = "Black",
                ["多色"] = "Multicolor",
            };

        public static string ColorLabel(string toneJa, bool ja)
        {
            if (ja) return toneJa;
            return ToneEn.TryGetValue(toneJa, out var en) ? en : toneJa;
        }

        public static string CategoryLabel(IconItem item, bool ja) =>
            ja ? (string.IsNullOrEmpty(item.CategoryJa) ? item.Category : item.CategoryJa) : item.Category;

        public static string StyleLabel(string styleCanonical, string styleJa, bool ja) =>
            ja ? (string.IsNullOrEmpty(styleJa) ? styleCanonical : styleJa) : styleCanonical;

        /// <summary>アイコンの表示名。例 EN "Rocket (Flat)" / JA "ロケット（フラット）"。3D は接尾辞なし。</summary>
        public static string DisplayName(IconItem item, bool ja)
        {
            if (ja)
            {
                var baseName = string.IsNullOrEmpty(item.NameJa) ? item.NameEnBase : item.NameJa!;
                var suffix = (string.IsNullOrEmpty(item.StyleJa) || item.StyleJa == "3D")
                    ? "" : "（" + item.StyleJa + "）";
                return baseName + suffix;
            }
            else
            {
                var baseName = item.NameEnBase;
                var suffix = (string.IsNullOrEmpty(item.Style) || item.Style == "3D")
                    ? "" : " (" + item.Style + ")";
                return baseName + suffix;
            }
        }

        /// <summary>名前検索の対象テキスト（言語に応じた表示名＋ジャンル＋スタイル＋キーワード）。</summary>
        public static string SearchHaystack(IconItem item, bool ja)
        {
            var parts = new List<string>
            {
                DisplayName(item, ja),
                item.Name,
                item.NameEnBase,
                CategoryLabel(item, ja),
                StyleLabel(item.Style, item.StyleJa, ja),
            };
            if (!string.IsNullOrEmpty(item.NameJa)) parts.Add(item.NameJa!);
            parts.AddRange(item.Keywords);
            parts.AddRange(item.Colors.Select(c => ColorLabel(c, ja)));
            return string.Join("\n", parts.Where(p => !string.IsNullOrEmpty(p)));
        }
    }
}
