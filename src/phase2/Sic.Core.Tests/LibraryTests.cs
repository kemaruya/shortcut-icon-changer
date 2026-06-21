using System.IO;
using System.IO.Compression;
using System.Linq;
using Sic.Core;
using Sic.Core.Localization;
using Xunit;

namespace Sic.Core.Tests
{
    /// <summary>リポジトリ同梱の 900 種スターターを使った統合テスト（assets が見つからなければ skip）。</summary>
    public class LibraryTests
    {
        [Fact]
        public void Enumerate_RealStarterSet_HasStylesAndMetadata()
        {
            var assets = TestHelpers.RepoAssets();
            Assert.True(assets != null, "リポジトリの assets\\starter-icons が見つかりません。");

            SicPaths.StarterPathOverride = assets;
            try
            {
                var lib = IconLibrary.Enumerate();

                // 既定では 3D / フラットを表示（ハイコントラストは非表示）。各 300 種想定。
                Assert.True(lib.Count >= 400, $"想定より少ない: {lib.Count}");

                var styles = lib.Select(i => i.StyleJa).Where(s => !string.IsNullOrEmpty(s))
                                .Distinct().ToList();
                Assert.Contains("3D", styles);
                Assert.Contains("フラット", styles);

                // ハイコントラストは既定で非表示（アセットは残るがアプリには出さない）。
                Assert.DoesNotContain("ハイコントラスト", styles);
                Assert.DoesNotContain(lib, i => i.Style == "High Contrast");

                // メタデータ付与（ジャンル日本語・色調）
                Assert.Contains(lib, i => !string.IsNullOrEmpty(i.CategoryJa));
                Assert.Contains(lib, i => i.Colors.Count > 0);

                // スタイル接尾辞の除去（Flat/HC 項目は NameEnBase が短い）
                var flat = lib.FirstOrDefault(i => i.StyleJa == "フラット");
                Assert.NotNull(flat);
                Assert.DoesNotContain("フラット", flat!.NameEnBase);
                Assert.Contains("フラット", flat.Name);
            }
            finally { SicPaths.StarterPathOverride = null; }
        }

        [Fact]
        public void Enumerate_FromZip_SetsZipFields_AndHidesHiddenStyles()
        {
            // icons.zip 同梱レイアウトを合成し、zip 列挙・適用時の取り出し・非表示スタイル除外を検証。
            var dir = Path.Combine(Path.GetTempPath(), "sic_zip_" + System.Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            var prevOverride = SicPaths.StarterPathOverride;
            try
            {
                var rocket3d = "Rocket.png";
                var rocketFlat = "Rocket (フラット).png";
                var glyphHc = "Glyph (ハイコントラスト).png";

                var zipPath = Path.Combine(dir, "icons.zip");
                using (var zip = ZipFile.Open(zipPath, ZipArchiveMode.Create))
                {
                    foreach (var name in new[] { rocket3d, rocketFlat, glyphHc })
                    {
                        var entry = zip.CreateEntry(name, CompressionLevel.NoCompression);
                        using var es = entry.Open();
                        var png = File.ReadAllBytes(TestHelpers.CreateTempPng());
                        es.Write(png, 0, png.Length);
                    }
                }

                // 最小 index（style メタを与える。HC は除外対象）
                File.WriteAllText(Path.Combine(dir, "icons-index.json"),
                    "{ \"version\": 3, \"icons\": {" +
                    "  \"Rocket\": { \"category\": \"Travel & Places\", \"style\": \"3D\", \"styleJa\": \"3D\", \"nameEn\": \"Rocket\", \"nameJa\": \"ロケット\", \"colors\": [\"赤\"], \"keywords\": [] }," +
                    "  \"Rocket (フラット)\": { \"category\": \"Travel & Places\", \"style\": \"Flat\", \"styleJa\": \"フラット\", \"nameEn\": \"Rocket\", \"nameJa\": \"ロケット\", \"colors\": [\"赤\"], \"keywords\": [] }," +
                    "  \"Glyph (ハイコントラスト)\": { \"category\": \"Objects\", \"style\": \"High Contrast\", \"styleJa\": \"ハイコントラスト\", \"nameEn\": \"Glyph\", \"nameJa\": \"グリフ\", \"colors\": [\"黒\"], \"keywords\": [] }" +
                    "} }", new System.Text.UTF8Encoding(false));

                SicPaths.StarterPathOverride = dir;

                var lib = IconLibrary.Enumerate();

                // 既定: 3D / フラットは出る。ハイコントラストは非表示。
                Assert.Contains(lib, i => i.Name == "Rocket");
                Assert.Contains(lib, i => i.Name == "Rocket (フラット)");
                Assert.DoesNotContain(lib, i => i.Style == "High Contrast");

                // zip 由来エントリは ZipPath/ZipEntry を持ち、Path は空。
                var flat = lib.First(i => i.Name == "Rocket (フラット)");
                Assert.Equal(zipPath, flat.ZipPath);
                Assert.Equal(rocketFlat, flat.ZipEntry);
                Assert.True(string.IsNullOrEmpty(flat.Path));

                // 適用時は実ファイルへ取り出される（GetCachedIcon が実体を要求するため）。
                var real = SicAssets.ResolveForApply(flat);
                Assert.True(File.Exists(real), $"取り出した実ファイルが無い: {real}");
                Assert.Equal(rocketFlat, Path.GetFileName(real));

                // HiddenStyles を一時的に外すと HC が戻る＝アセット/インデックスは健在（除外しているだけ）。
                var saved = IconLibrary.HiddenStyles.ToList();
                IconLibrary.HiddenStyles.Clear();
                try
                {
                    var all = IconLibrary.Enumerate();
                    Assert.Contains(all, i => i.Style == "High Contrast");
                    Assert.True(all.Count > lib.Count, $"HC を戻すと増えるはず: {all.Count} > {lib.Count}");
                }
                finally
                {
                    IconLibrary.HiddenStyles.Clear();
                    foreach (var s in saved) IconLibrary.HiddenStyles.Add(s);
                }
            }
            finally
            {
                SicPaths.StarterPathOverride = prevOverride;
                try { Directory.Delete(dir, true); } catch { /* 後始末失敗は無視 */ }
            }
        }

        [Fact]
        public void IconIndex_Load_HasEntries()
        {
            var assets = TestHelpers.RepoAssets();
            Assert.True(assets != null);
            SicPaths.StarterPathOverride = assets;
            try
            {
                var idx = IconIndex.Load();
                Assert.True(idx.Count > 100, $"index エントリが少ない: {idx.Count}");
                Assert.Contains(idx.Values, m => !string.IsNullOrEmpty(m.Category));
                Assert.Contains(idx.Values, m => !string.IsNullOrEmpty(m.Style));
            }
            finally { SicPaths.StarterPathOverride = null; }
        }

        [Fact]
        public void DisplayName_JapaneseNames_AreLocalizedWithStyleSuffix()
        {
            var assets = TestHelpers.RepoAssets();
            Assert.True(assets != null, "リポジトリの assets\\starter-icons が見つかりません。");

            SicPaths.StarterPathOverride = assets;
            try
            {
                var lib = IconLibrary.Enumerate();

                // index v3: ほぼ全エントリに日本語固有名 (nameJa) が付与されている。
                var withJa = lib.Count(i => !string.IsNullOrEmpty(i.NameJa));
                Assert.True(withJa >= lib.Count * 0.9,
                    $"nameJa の付与が少ない: {withJa}/{lib.Count}");

                // 3D「Rocket」: 接尾辞なし。EN=Rocket / JA=ロケット。
                var rocket3d = lib.First(i => i.Name == "Rocket");
                Assert.Equal("ロケット", rocket3d.NameJa);
                Assert.Equal("Rocket", Loc.DisplayName(rocket3d, ja: false));
                Assert.Equal("ロケット", Loc.DisplayName(rocket3d, ja: true));

                // フラット「Rocket (フラット)」: EN=Rocket (Flat) / JA=ロケット（フラット）。
                var rocketFlat = lib.First(i => i.Name == "Rocket (フラット)");
                Assert.Equal("ロケット", rocketFlat.NameJa);
                Assert.Equal("Rocket (Flat)", Loc.DisplayName(rocketFlat, ja: false));
                Assert.Equal("ロケット（フラット）", Loc.DisplayName(rocketFlat, ja: true));

                // 日本語名が無い項目は英語ベース名へフォールバックする（例外を出さない）。
                var noJa = new IconItem { Name = "Custom", NameEnBase = "Custom", Style = "3D", StyleJa = "3D" };
                Assert.Equal("Custom", Loc.DisplayName(noJa, ja: true));
            }
            finally { SicPaths.StarterPathOverride = null; }
        }
    }
}
