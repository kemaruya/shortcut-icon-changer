namespace Sic.App
{
    public enum PickKind { Cancel, Apply, Reset }

    public sealed class PickResult
    {
        public PickKind Kind { get; set; } = PickKind.Cancel;
        public string? IconPath { get; set; }

        /// <summary>適用対象の .lnk。ピッカー内で選択/確定した対象を呼び出し元へ返す。</summary>
        public string? TargetLnk { get; set; }
    }
}
