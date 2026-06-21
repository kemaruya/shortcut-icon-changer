namespace Sic.App
{
    public enum PickKind { Cancel, Apply, Reset }

    public sealed class PickResult
    {
        public PickKind Kind { get; set; } = PickKind.Cancel;
        public string? IconPath { get; set; }
    }
}
