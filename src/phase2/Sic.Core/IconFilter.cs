using System.Collections.Generic;
using System.Linq;

namespace Sic.Core
{
    /// <summary>
    /// ファセット絞り込み（IconPicker.ps1 buildItems を移植）。
    /// facet 内 OR・facet 間 AND。スタイル未設定（ユーザー追加）の項目はスタイル facet を常に通過。
    /// チップは正規キー（Style=英語 / Category=英語 / Color=日本語トーン）を保持して照合する。
    /// 名前検索は表示言語依存のため ViewModel 側で行い、ここには含めない。
    /// </summary>
    public static class IconFilter
    {
        public static List<IconItem> ByFacets(
            IEnumerable<IconItem> items,
            ISet<string>? styles = null,
            ISet<string>? categories = null,
            ISet<string>? colors = null)
        {
            IEnumerable<IconItem> q = items;

            if (styles != null && styles.Count > 0)
                q = q.Where(i => string.IsNullOrEmpty(i.Style) || styles.Contains(i.Style));

            if (categories != null && categories.Count > 0)
                q = q.Where(i => !string.IsNullOrEmpty(i.Category) && categories.Contains(i.Category));

            if (colors != null && colors.Count > 0)
                q = q.Where(i => i.Colors.Any(colors.Contains));

            return q.ToList();
        }
    }
}
