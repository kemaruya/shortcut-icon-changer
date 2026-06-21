using System.Collections.Generic;
using System.Globalization;
using System.IO;
using Sic.Core;
using Sic.Core.Localization;
using Xunit;

namespace Sic.Core.Tests
{
    public class CoreTests
    {
        [Fact]
        public void ConvertToIco_ProducesMultiFrameIco()
        {
            var png = TestHelpers.CreateTempPng();
            var ico = TestHelpers.TempPath(".ico");
            try
            {
                IconConverter.ConvertToIco(png, ico, new[] { 16, 32, 48, 256 });
                using var br = new BinaryReader(File.OpenRead(ico));
                Assert.Equal(0, br.ReadUInt16());       // reserved
                Assert.Equal(1, br.ReadUInt16());       // type = icon
                Assert.Equal(4, br.ReadUInt16());       // count

                var dims = new List<byte>();
                for (int i = 0; i < 4; i++)
                {
                    byte w = br.ReadByte();
                    br.ReadByte();                       // height
                    br.ReadBytes(2);                     // colorcount + reserved
                    Assert.Equal(1, br.ReadUInt16());    // planes
                    Assert.Equal(32, br.ReadUInt16());   // bitcount
                    br.ReadUInt32();                     // length
                    br.ReadUInt32();                     // offset
                    dims.Add(w);
                }
                Assert.Contains((byte)16, dims);
                Assert.Contains((byte)32, dims);
                Assert.Contains((byte)48, dims);
                Assert.Contains((byte)0, dims);          // 256 => 0
            }
            finally { File.Delete(png); if (File.Exists(ico)) File.Delete(ico); }
        }

        [Fact]
        public void GetCachedIcon_IcoReturnedAsIs_PngCachedAndReused()
        {
            // .ico はそのまま返る
            var png = TestHelpers.CreateTempPng();
            var ico = TestHelpers.TempPath(".ico");
            IconConverter.ConvertToIco(png, ico);
            Assert.Equal(Path.GetFullPath(ico), IconConverter.GetCachedIcon(ico));

            // .png はキャッシュへ変換され、再呼び出しで同一パスを再利用
            var cached1 = IconConverter.GetCachedIcon(png);
            Assert.True(File.Exists(cached1));
            Assert.EndsWith(".ico", cached1);
            var firstWrite = File.GetLastWriteTimeUtc(cached1);
            var cached2 = IconConverter.GetCachedIcon(png);
            Assert.Equal(cached1, cached2);
            Assert.Equal(firstWrite, File.GetLastWriteTimeUtc(cached2)); // 再変換していない

            File.Delete(png); File.Delete(ico);
        }

        [Fact]
        public void ConvertToIco_SvgThrows()
        {
            var svg = TestHelpers.TempPath(".svg");
            File.WriteAllText(svg, "<svg/>");
            try
            {
                Assert.ThrowsAny<System.Exception>(() =>
                    IconConverter.ConvertToIco(svg, TestHelpers.TempPath(".ico")));
            }
            finally { File.Delete(svg); }
        }

        [Fact]
        public void Filter_FacetWithinOr_AcrossAnd_UntaggedStylePasses()
        {
            var items = new List<IconItem>
            {
                new IconItem { Name = "RedApple", Category = "Food & Drink", Style = "3D",   Colors = new[] { "赤" } },
                new IconItem { Name = "RedCar",   Category = "Travel & Places", Style = "Flat", Colors = new[] { "赤" } },
                new IconItem { Name = "BlueApple",Category = "Food & Drink", Style = "3D",   Colors = new[] { "青" } },
                new IconItem { Name = "UserIco",  Category = "",            Style = "",     Colors = new string[0] },
            };

            // 色=赤 AND ジャンル=食べ物 → RedApple のみ
            var r = IconFilter.ByFacets(items,
                colors: new HashSet<string> { "赤" },
                categories: new HashSet<string> { "Food & Drink" });
            Assert.Single(r);
            Assert.Equal("RedApple", r[0].Name);

            // スタイル=Flat → Flat 項目 ＋ 未設定(UserIco) が通過
            var s = IconFilter.ByFacets(items, styles: new HashSet<string> { "Flat" });
            Assert.Contains(s, x => x.Name == "RedCar");
            Assert.Contains(s, x => x.Name == "UserIco");
            Assert.DoesNotContain(s, x => x.Name == "RedApple");
        }

        [Theory]
        [InlineData("Rocket (フラット)", "フラット", "Rocket")]
        [InlineData("Rocket (ハイコントラスト)", "ハイコントラスト", "Rocket")]
        [InlineData("Rocket", "3D", "Rocket")]
        [InlineData("Rocket", "", "Rocket")]
        public void StripStyleSuffix_Works(string name, string styleJa, string expected)
        {
            Assert.Equal(expected, IconLibrary.StripStyleSuffix(name, styleJa));
        }

        [Fact]
        public void Maps_TranslateCategoryAndStyle()
        {
            Assert.Equal("物", SicMaps.ToCategoryJa("Objects"));
            Assert.Equal("食べ物", SicMaps.ToCategoryJa("Food & Drink"));
            Assert.Equal("フラット", SicMaps.ToStyleJa("Flat"));
            Assert.Equal("3D", SicMaps.ToStyleJa("3D"));
            Assert.Equal("Unknown", SicMaps.ToCategoryJa("Unknown")); // 未知はそのまま
        }

        [Fact]
        public void Loc_IsJapanese_RespectsPrefAndCulture()
        {
            Assert.True(Loc.IsJapanese(AppLanguage.Japanese, CultureInfo.GetCultureInfo("en-US")));
            Assert.False(Loc.IsJapanese(AppLanguage.English, CultureInfo.GetCultureInfo("ja-JP")));
            Assert.True(Loc.IsJapanese(AppLanguage.Auto, CultureInfo.GetCultureInfo("ja-JP")));
            Assert.False(Loc.IsJapanese(AppLanguage.Auto, CultureInfo.GetCultureInfo("en-US")));
            Assert.False(Loc.IsJapanese(AppLanguage.Auto, CultureInfo.GetCultureInfo("fr-FR")));
        }

        [Fact]
        public void Loc_DisplayName_EnglishAndJapanese()
        {
            var flat = new IconItem
            {
                Name = "Rocket (フラット)", NameEnBase = "Rocket", NameJa = "ロケット",
                Style = "Flat", StyleJa = "フラット",
            };
            Assert.Equal("Rocket (Flat)", Loc.DisplayName(flat, ja: false));
            Assert.Equal("ロケット（フラット）", Loc.DisplayName(flat, ja: true));

            var threeD = new IconItem
            {
                Name = "Rocket", NameEnBase = "Rocket", NameJa = "ロケット",
                Style = "3D", StyleJa = "3D",
            };
            Assert.Equal("Rocket", Loc.DisplayName(threeD, ja: false));
            Assert.Equal("ロケット", Loc.DisplayName(threeD, ja: true));

            // NameJa 欠落時は英語ベースへフォールバック
            var noJa = new IconItem { NameEnBase = "Rocket", Style = "Flat", StyleJa = "フラット" };
            Assert.Equal("Rocket（フラット）", Loc.DisplayName(noJa, ja: true));
        }

        [Fact]
        public void Loc_ColorLabel_EnglishFallback()
        {
            Assert.Equal("Red", Loc.ColorLabel("赤", ja: false));
            Assert.Equal("赤", Loc.ColorLabel("赤", ja: true));
            Assert.Equal("Multicolor", Loc.ColorLabel("多色", ja: false));
        }
    }
}
