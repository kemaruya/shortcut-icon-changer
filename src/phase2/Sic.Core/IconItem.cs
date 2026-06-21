using System.Collections.Generic;

namespace Sic.Core
{
    /// <summary>1 つのアイコン候補（スターター/ユーザー ライブラリ由来）。</summary>
    public sealed class IconItem
    {
        /// <summary>ファイル名（拡張子なし）。スタイル接尾辞を含むライブラリ キー。</summary>
        public string Name { get; set; } = "";

        public string Path { get; set; } = "";

        /// <summary>zip 同梱アイコンの場合の zip 物理パス（loose ファイルなら null）。</summary>
        public string? ZipPath { get; set; }

        /// <summary>zip 同梱アイコンの場合の zip エントリ名（例 "Rocket (フラット).png"）。</summary>
        public string? ZipEntry { get; set; }

        /// <summary>"starter" もしくは "library"。</summary>
        public string Source { get; set; } = "";

        public string Extension { get; set; } = "";

        /// <summary>正規（英語）ジャンル。例: "Objects"。</summary>
        public string Category { get; set; } = "";

        public string CategoryJa { get; set; } = "";

        /// <summary>正規（日本語）色調トーン。例: "赤"。</summary>
        public IReadOnlyList<string> Colors { get; set; } = System.Array.Empty<string>();

        public IReadOnlyList<string> Keywords { get; set; } = System.Array.Empty<string>();

        /// <summary>正規（英語）スタイル。例: "3D" / "Flat" / "High Contrast"。</summary>
        public string Style { get; set; } = "";

        public string StyleJa { get; set; } = "";

        /// <summary>スタイル接尾辞を除いた英語名（表示・ローカライズの土台）。</summary>
        public string NameEnBase { get; set; } = "";

        /// <summary>日本語の固有名（任意。無ければ英語へフォールバック）。</summary>
        public string? NameJa { get; set; }
    }
}
