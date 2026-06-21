namespace Sic.Core
{
    /// <summary>アイコンの「適用に使える実ファイル パス」を解決する。</summary>
    public static class SicAssets
    {
        /// <summary>
        /// 適用用に実ファイル パスへ解決する。zip 同梱アイコンは展開先へ取り出して
        /// その実パスを返す（<see cref="IconConverter.GetCachedIcon"/> が実ファイルを要求するため）。
        /// loose ファイルのアイコンやユーザー独自アイコンはそのまま <see cref="IconItem.Path"/> を返す。
        /// </summary>
        public static string ResolveForApply(IconItem item)
        {
            if (!string.IsNullOrEmpty(item.ZipPath) && !string.IsNullOrEmpty(item.ZipEntry))
            {
                var dest = SicAssetZip.Materialize(item.ZipPath!, item.ZipEntry!, SicPaths.ExtractedPath());
                if (!string.IsNullOrEmpty(dest)) return dest!;
            }
            return item.Path;
        }
    }
}
