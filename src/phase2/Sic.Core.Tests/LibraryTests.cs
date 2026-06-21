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
        public void Enumerate_HidesHighContrastByDefault_ButAssetsRemain()
        {
            var assets = TestHelpers.RepoAssets();
            Assert.True(assets != null, "リポジトリの assets\\starter-icons が見つかりません。");

            SicPaths.StarterPathOverride = assets;
            try
            {
                // 既定: ハイコントラストは列挙されない（アプリから不可視）。
                var visible = IconLibrary.Enumerate();
                Assert.DoesNotContain(visible, i => i.Style == "High Contrast");

                // HiddenStyles を一時的に外すとハイコントラストが戻る
                // ＝ アセット/インデックスは削除しておらず健在であることの証明。
                var saved = IconLibrary.HiddenStyles.ToList();
                IconLibrary.HiddenStyles.Clear();
                try
                {
                    var all = IconLibrary.Enumerate();
                    Assert.Contains(all, i => i.Style == "High Contrast");
                    Assert.True(all.Count > visible.Count,
                        $"ハイコントラストを戻すと増えるはず: {all.Count} > {visible.Count}");
                }
                finally
                {
                    IconLibrary.HiddenStyles.Clear();
                    foreach (var s in saved) IconLibrary.HiddenStyles.Add(s);
                }
            }
            finally { SicPaths.StarterPathOverride = null; }
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
