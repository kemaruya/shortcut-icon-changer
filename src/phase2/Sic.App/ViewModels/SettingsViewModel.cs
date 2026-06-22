using System;
using System.ComponentModel;
using Sic.App.Localization;
using Sic.Core;
using Sic.Core.Localization;

namespace Sic.App.ViewModels
{
    /// <summary>設定画面の VM。言語・テーマ・既定フォルダー・キャッシュ・情報を扱う。</summary>
    public sealed class SettingsViewModel : INotifyPropertyChanged
    {
        private readonly AppSettings _settings;

        public UiStrings Strings { get; private set; }

        /// <summary>言語が変わったときに通知（ホーム側の文言更新用）。</summary>
        public event Action? LanguageChanged;

        public SettingsViewModel(AppSettings settings)
        {
            _settings = settings;
            Strings = Resolve();
            _language = (int)settings.Language;
            _theme = settings.Theme;
            _folder = settings.ShortcutFolder;
            _versionText = string.Format(Strings.VersionFormat, AppInfo.Version);
            RefreshCache();
        }

        // 言語（0 自動 / 1 日本語 / 2 英語）
        private int _language;
        public int LanguageChoice
        {
            get => _language;
            set { if (_language != value) { _language = value; OnChanged(nameof(LanguageChoice)); OnLanguageChanged(); } }
        }

        // テーマ
        private AppTheme _theme;
        public AppTheme Theme
        {
            get => _theme;
            set { if (_theme != value) { _theme = value; OnChanged(nameof(Theme)); OnThemeChanged(); } }
        }

        // 既定フォルダーの種別
        private ShortcutFolderMode _folder;
        public ShortcutFolderMode Folder
        {
            get => _folder;
            set
            {
                if (_folder != value)
                {
                    _folder = value;
                    _settings.ShortcutFolder = value;
                    Save();
                    OnChanged(nameof(Folder));
                    OnChanged(nameof(IsCustomFolder));
                }
            }
        }

        public bool IsCustomFolder => _folder == ShortcutFolderMode.Custom;

        public string CustomFolder
        {
            get => _settings.CustomShortcutFolder;
            set
            {
                _settings.CustomShortcutFolder = value ?? "";
                Save();
                OnChanged(nameof(CustomFolder));
            }
        }

        private string _cacheSizeText = "";
        public string CacheSizeText
        {
            get => _cacheSizeText;
            private set { _cacheSizeText = value; OnChanged(nameof(CacheSizeText)); }
        }

        private string _versionText;
        public string VersionText
        {
            get => _versionText;
            private set { _versionText = value; OnChanged(nameof(VersionText)); }
        }

        public void RefreshCache() =>
            CacheSizeText = string.Format(Strings.CacheSizeFormat,
                CacheManager.FormatSize(CacheManager.GetCacheSizeBytes()));

        /// <summary>キャッシュを削除して表示を更新する。削除ファイル数を返す。</summary>
        public int ClearCache()
        {
            int n = CacheManager.ClearCache();
            RefreshCache();
            return n;
        }

        /// <summary>すべての設定を既定値へ戻す。</summary>
        public void ResetSettings()
        {
            AppSettings.ResetToDefaults();
            _settings.Language = AppLanguage.Auto;
            _settings.Theme = AppTheme.System;
            _settings.ShortcutFolder = ShortcutFolderMode.Desktop;
            _settings.CustomShortcutFolder = "";

            _language = 0;
            _theme = AppTheme.System;
            _folder = ShortcutFolderMode.Desktop;

            Strings = Resolve();
            VersionText = string.Format(Strings.VersionFormat, AppInfo.Version);
            ThemeManager.Reapply(_settings);
            RefreshCache();

            OnChanged(nameof(LanguageChoice));
            OnChanged(nameof(Theme));
            OnChanged(nameof(Folder));
            OnChanged(nameof(IsCustomFolder));
            OnChanged(nameof(CustomFolder));
            OnChanged(nameof(Strings));
            LanguageChanged?.Invoke();
        }

        private void OnLanguageChanged()
        {
            _settings.Language = (AppLanguage)_language;
            Save();
            Strings = Resolve();
            VersionText = string.Format(Strings.VersionFormat, AppInfo.Version);
            RefreshCache();
            OnChanged(nameof(Strings));
            LanguageChanged?.Invoke();
        }

        private void OnThemeChanged()
        {
            _settings.Theme = _theme;
            Save();
            ThemeManager.Reapply(_settings);
        }

        private UiStrings Resolve() =>
            Loc.IsJapanese(_settings.Language) ? UiStrings.Japanese() : UiStrings.English();

        private void Save()
        {
            try { _settings.Save(); } catch { /* 設定保存失敗は無視 */ }
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnChanged(string n) =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));
    }
}
