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

        // 対象ショートカット バー
        public string TargetLabel { get; private set; } = "";
        public string TargetNone { get; private set; } = "";
        public string ChooseTarget { get; private set; } = "";
        public string ChangeTarget { get; private set; } = "";
        public string SelectTargetHint { get; private set; } = "";

        // ホーム
        public string HomeHeadline { get; private set; } = "";
        public string CardChangeIconTitle { get; private set; } = "";
        public string CardChangeIconDesc { get; private set; } = "";
        public string CardSettingsTitle { get; private set; } = "";
        public string CardSettingsDesc { get; private set; } = "";
        public string ViewOnGitHub { get; private set; } = "";
        public string VersionFormat { get; private set; } = "";

        // 設定
        public string SettingsTitle { get; private set; } = "";
        public string ThemeLabel { get; private set; } = "";
        public string ThemeSystem { get; private set; } = "";
        public string ThemeLight { get; private set; } = "";
        public string ThemeDark { get; private set; } = "";
        public string ShortcutFolderLabel { get; private set; } = "";
        public string FolderDesktop { get; private set; } = "";
        public string FolderStartMenu { get; private set; } = "";
        public string FolderCustom { get; private set; } = "";
        public string BrowseFolder { get; private set; } = "";
        public string CacheLabel { get; private set; } = "";
        public string CacheSizeFormat { get; private set; } = "";
        public string ClearCache { get; private set; } = "";
        public string OpenCacheFolder { get; private set; } = "";
        public string CacheClearWarning { get; private set; } = "";
        public string CacheClearedFormat { get; private set; } = "";
        public string AboutLabel { get; private set; } = "";
        public string ResetSettings { get; private set; } = "";
        public string ResetSettingsConfirm { get; private set; } = "";
        public string CloseLabel { get; private set; } = "";

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
            NoLnkNote = "No shortcut was specified. After you pick an icon (or Reset), you'll choose the target shortcut (.lnk) to apply it to.",
            OpenFileFilter = "Icon files (*.ico;*.png)|*.ico;*.png|All files (*.*)|*.*",
            ErrorTitle = "Shortcut Icon Changer",

            TargetLabel = "Target shortcut",
            TargetNone = "(none selected)",
            ChooseTarget = "Choose shortcut…",
            ChangeTarget = "Change…",
            SelectTargetHint = "First choose the shortcut (.lnk) you want to change above, then click an icon to apply it.",

            HomeHeadline = "Change a shortcut's icon",
            CardChangeIconTitle = "Change an icon",
            CardChangeIconDesc = "Pick a shortcut (.lnk), then choose an icon to apply.",
            CardSettingsTitle = "Settings",
            CardSettingsDesc = "Language, theme, default folder, cache and more.",
            ViewOnGitHub = "View on GitHub",
            VersionFormat = "Version {0}",

            SettingsTitle = "Settings",
            ThemeLabel = "Theme",
            ThemeSystem = "System",
            ThemeLight = "Light",
            ThemeDark = "Dark",
            ShortcutFolderLabel = "Default folder",
            FolderDesktop = "Desktop",
            FolderStartMenu = "Start menu",
            FolderCustom = "Custom",
            BrowseFolder = "Browse…",
            CacheLabel = "Icon cache",
            CacheSizeFormat = "Used: {0}",
            ClearCache = "Clear cache",
            OpenCacheFolder = "Open folder",
            CacheClearWarning = "Clearing the cache removes converted icon files. Shortcuts you already customized may show a blank icon until you apply them again. Continue?",
            CacheClearedFormat = "Removed {0} file(s).",
            AboutLabel = "About",
            ResetSettings = "Reset settings",
            ResetSettingsConfirm = "Reset all settings to their defaults?",
            CloseLabel = "Close",
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
            NoLnkNote = "ショートカットが指定されていません。アイコンを選ぶ（または「既定に戻す」）と、続けて対象のショートカット（.lnk）を選択して適用できます。",
            OpenFileFilter = "アイコン ファイル (*.ico;*.png)|*.ico;*.png|すべてのファイル (*.*)|*.*",
            ErrorTitle = "ショートカット アイコン変更",

            TargetLabel = "対象のショートカット",
            TargetNone = "（未選択）",
            ChooseTarget = "ショートカットを選択…",
            ChangeTarget = "変更…",
            SelectTargetHint = "まず上で、アイコンを変更したいショートカット（.lnk）を選んでください。選んでからアイコンをクリックすると適用されます。",

            HomeHeadline = "ショートカットのアイコンを変更",
            CardChangeIconTitle = "アイコンを変更",
            CardChangeIconDesc = "ショートカット（.lnk）を選び、適用するアイコンを選択します。",
            CardSettingsTitle = "設定",
            CardSettingsDesc = "言語・テーマ・既定のフォルダー・キャッシュなど。",
            ViewOnGitHub = "GitHub で見る",
            VersionFormat = "バージョン {0}",

            SettingsTitle = "設定",
            ThemeLabel = "テーマ",
            ThemeSystem = "システム",
            ThemeLight = "ライト",
            ThemeDark = "ダーク",
            ShortcutFolderLabel = "既定のフォルダー",
            FolderDesktop = "デスクトップ",
            FolderStartMenu = "スタート メニュー",
            FolderCustom = "カスタム",
            BrowseFolder = "参照…",
            CacheLabel = "アイコン キャッシュ",
            CacheSizeFormat = "使用量: {0}",
            ClearCache = "キャッシュを削除",
            OpenCacheFolder = "フォルダーを開く",
            CacheClearWarning = "キャッシュを削除すると、変換済みのアイコン ファイルが削除されます。すでにカスタム アイコンを適用したショートカットは、再度適用するまでアイコンが表示されなくなる場合があります。続行しますか？",
            CacheClearedFormat = "{0} 個のファイルを削除しました。",
            AboutLabel = "情報",
            ResetSettings = "設定を初期化",
            ResetSettingsConfirm = "すべての設定を既定値に戻しますか？",
            CloseLabel = "閉じる",
        };
    }
}
