namespace Sic.App.Localization
{
    /// <summary>UI 表示文字列（英語/日本語）。コードベース対訳で in-box ビルドのみで完結させる。</summary>
    public sealed class UiStrings
    {
        public string WindowTitle { get; private set; } = "";
        public string FilterLabel { get; private set; } = "";
        public string SearchPlaceholder { get; private set; } = "";
        public string StyleFacet { get; private set; } = "";
        public string GenreFacet { get; private set; } = "";
        public string ColorFacet { get; private set; } = "";
        public string ClearTags { get; private set; } = "";
        public string ResetToDefault { get; private set; } = "";
        public string Custom { get; private set; } = "";
        public string Cancel { get; private set; } = "";
        public string LanguageLabel { get; private set; } = "";
        public string LangAuto { get; private set; } = "";
        public string LangJa { get; private set; } = "";
        public string LangEn { get; private set; } = "";
        public string CountFormat { get; private set; } = "";
        public string NoLnkNote { get; private set; } = "";
        public string OpenFileFilter { get; private set; } = "";
        public string ErrorTitle { get; private set; } = "";

        public static UiStrings English() => new UiStrings
        {
            WindowTitle = "Shortcut Icon Changer",
            FilterLabel = "Filter",
            SearchPlaceholder = "Type to filter by name, genre, color or keyword…",
            StyleFacet = "Style",
            GenreFacet = "Genre",
            ColorFacet = "Color",
            ClearTags = "Clear tags",
            ResetToDefault = "Reset to default",
            Custom = "Custom…",
            Cancel = "Cancel",
            LanguageLabel = "Language",
            LangAuto = "Auto",
            LangJa = "日本語",
            LangEn = "English",
            CountFormat = "{0} icons",
            NoLnkNote = "No shortcut was specified. Choosing an icon will only preview it.",
            OpenFileFilter = "Icon files (*.ico;*.png)|*.ico;*.png|All files (*.*)|*.*",
            ErrorTitle = "Shortcut Icon Changer",
        };

        public static UiStrings Japanese() => new UiStrings
        {
            WindowTitle = "ショートカット アイコン変更",
            FilterLabel = "絞り込み",
            SearchPlaceholder = "名前・ジャンル・色・キーワードで絞り込み…",
            StyleFacet = "スタイル",
            GenreFacet = "ジャンル",
            ColorFacet = "色調",
            ClearTags = "タグをクリア",
            ResetToDefault = "既定に戻す",
            Custom = "参照…",
            Cancel = "キャンセル",
            LanguageLabel = "言語",
            LangAuto = "自動",
            LangJa = "日本語",
            LangEn = "English",
            CountFormat = "{0} 件",
            NoLnkNote = "ショートカットが指定されていません。アイコンを選んでもプレビューのみとなります。",
            OpenFileFilter = "アイコン ファイル (*.ico;*.png)|*.ico;*.png|すべてのファイル (*.*)|*.*",
            ErrorTitle = "ショートカット アイコン変更",
        };
    }
}
