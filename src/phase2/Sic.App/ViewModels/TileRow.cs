using System.Collections.Generic;

namespace Sic.App.ViewModels
{
    /// <summary>
    /// 仮想化リスト（行単位）で 1 行分のタイル群を保持する。WPF の in-box 仮想化は
    /// 縦リストのみ対応のため、平坦なタイル列を列数 K ごとに行へ束ね、外側の仮想化 ListBox に
    /// 行をバインドする（可視行のタイルだけが実体化・デコードされ、起動が総数に依存しなくなる）。
    /// </summary>
    public sealed class TileRow
    {
        public IReadOnlyList<IconTileVM> Tiles { get; }
        public TileRow(IReadOnlyList<IconTileVM> tiles) { Tiles = tiles; }
    }
}
