using System.Linq;
using Sic.Core;
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

                // 3D / フラット / ハイコントラスト 各 300 種（計 900）
                Assert.True(lib.Count >= 600, $"想定より少ない: {lib.Count}");

                var styles = lib.Select(i => i.StyleJa).Where(s => !string.IsNullOrEmpty(s))
                                .Distinct().ToList();
                Assert.Contains("3D", styles);
                Assert.Contains("フラット", styles);
                Assert.Contains("ハイコントラスト", styles);

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
    }
}
