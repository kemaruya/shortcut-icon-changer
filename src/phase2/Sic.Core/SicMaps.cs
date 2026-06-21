using System;
using System.Collections.Generic;

namespace Sic.Core
{
    /// <summary>ジャンル/色調/スタイルの日本語対訳と表示順（SicCore.psm1 のマップを移植）。</summary>
    public static class SicMaps
    {
        public static readonly IReadOnlyDictionary<string, string> CategoryJa =
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["Smileys & Emotion"] = "顔・感情",
                ["People & Body"] = "人・体",
                ["Animals & Nature"] = "動物・自然",
                ["Food & Drink"] = "食べ物",
                ["Travel & Places"] = "旅行・場所",
                ["Activities"] = "アクティビティ",
                ["Objects"] = "物",
                ["Symbols"] = "記号",
                ["Flags"] = "旗",
                ["Component"] = "部品",
            };

        public static readonly string[] ToneOrder =
            { "赤", "橙", "黄", "緑", "青", "紫", "桃", "茶", "白", "灰", "黒", "多色" };

        public static readonly IReadOnlyDictionary<string, string> StyleJa =
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["3D"] = "3D",
                ["Flat"] = "フラット",
                ["High Contrast"] = "ハイコントラスト",
            };

        public static readonly string[] StyleOrder = { "3D", "フラット", "ハイコントラスト" };

        public static string ToCategoryJa(string group) =>
            !string.IsNullOrEmpty(group) && CategoryJa.TryGetValue(group, out var v) ? v : group;

        public static string ToStyleJa(string style) =>
            !string.IsNullOrEmpty(style) && StyleJa.TryGetValue(style, out var v) ? v : style;

        /// <summary>色調トーンの表示順インデックス（未知は末尾）。</summary>
        public static int ToneIndex(string tone)
        {
            var i = Array.IndexOf(ToneOrder, tone);
            return i < 0 ? ToneOrder.Length : i;
        }

        /// <summary>スタイルの表示順インデックス（未知は末尾）。</summary>
        public static int StyleIndex(string styleJa)
        {
            var i = Array.IndexOf(StyleOrder, styleJa);
            return i < 0 ? StyleOrder.Length : i;
        }
    }
}
