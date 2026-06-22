using System;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;
using System.Collections.Generic;
using Sic.Core.Localization;

namespace Sic.Core
{
    /// <summary>言語・テーマなど UI の永続設定（%LOCALAPPDATA%\ShortcutIconChanger\settings.json）。</summary>
    public sealed class AppSettings
    {
        public AppLanguage Language { get; set; } = AppLanguage.Auto;
        public AppTheme Theme { get; set; } = AppTheme.System;

        /// <summary>単体起動時に対象 .lnk を選ぶ既定フォルダーの種別。</summary>
        public ShortcutFolderMode ShortcutFolder { get; set; } = ShortcutFolderMode.Desktop;

        /// <summary><see cref="ShortcutFolderMode.Custom"/> のときの実フォルダー パス。</summary>
        public string CustomShortcutFolder { get; set; } = "";

        public static AppSettings Load()
        {
            var path = SicPaths.SettingsPath();
            if (!File.Exists(path)) return new AppSettings();
            try
            {
                var ser = new JavaScriptSerializer();
                var root = ser.DeserializeObject(File.ReadAllText(path, Encoding.UTF8))
                           as Dictionary<string, object>;
                var s = new AppSettings();
                if (root != null)
                {
                    if (root.TryGetValue("language", out var lang))
                        s.Language = ParseLanguage(lang?.ToString());
                    if (root.TryGetValue("theme", out var theme))
                        s.Theme = ParseTheme(theme?.ToString());
                    if (root.TryGetValue("shortcutFolder", out var sf))
                        s.ShortcutFolder = ParseFolderMode(sf?.ToString());
                    if (root.TryGetValue("customShortcutFolder", out var cf))
                        s.CustomShortcutFolder = cf?.ToString() ?? "";
                }
                return s;
            }
            catch { return new AppSettings(); }
        }

        public void Save()
        {
            var path = SicPaths.SettingsPath();
            // JavaScriptSerializer を使い、Windows パスのバックスラッシュ等を正しくエスケープする。
            var dict = new Dictionary<string, object>
            {
                ["language"] = ToToken(Language),
                ["theme"] = ThemeToken(Theme),
                ["shortcutFolder"] = FolderModeToken(ShortcutFolder),
                ["customShortcutFolder"] = CustomShortcutFolder ?? "",
            };
            var json = new JavaScriptSerializer().Serialize(dict);
            File.WriteAllText(path, json, new UTF8Encoding(false));
        }

        /// <summary>設定の既定値に戻し、settings.json を削除する。</summary>
        public static void ResetToDefaults()
        {
            try
            {
                var path = SicPaths.SettingsPath();
                if (File.Exists(path)) File.Delete(path);
            }
            catch { /* 削除失敗は無視 */ }
        }

        /// <summary>現在の設定から、対象 .lnk を選ぶ初期フォルダーの実パスを解決する。</summary>
        public string ResolveShortcutFolder()
        {
            try
            {
                switch (ShortcutFolder)
                {
                    case ShortcutFolderMode.StartMenu:
                        return Environment.GetFolderPath(Environment.SpecialFolder.Programs);
                    case ShortcutFolderMode.Custom:
                        if (!string.IsNullOrEmpty(CustomShortcutFolder) && Directory.Exists(CustomShortcutFolder))
                            return CustomShortcutFolder;
                        break;
                }
            }
            catch { /* 解決失敗は Desktop へフォールバック */ }
            return Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        }

        public static AppLanguage ParseLanguage(string? token)
        {
            switch ((token ?? "").Trim().ToLowerInvariant())
            {
                case "ja": case "japanese": return AppLanguage.Japanese;
                case "en": case "english": return AppLanguage.English;
                default: return AppLanguage.Auto;
            }
        }

        public static string ToToken(AppLanguage lang) => lang switch
        {
            AppLanguage.Japanese => "ja",
            AppLanguage.English => "en",
            _ => "auto",
        };

        public static AppTheme ParseTheme(string? token)
        {
            switch ((token ?? "").Trim().ToLowerInvariant())
            {
                case "light": return AppTheme.Light;
                case "dark": return AppTheme.Dark;
                default: return AppTheme.System;
            }
        }

        public static string ThemeToken(AppTheme theme) => theme switch
        {
            AppTheme.Light => "light",
            AppTheme.Dark => "dark",
            _ => "system",
        };

        public static ShortcutFolderMode ParseFolderMode(string? token)
        {
            switch ((token ?? "").Trim().ToLowerInvariant())
            {
                case "startmenu": return ShortcutFolderMode.StartMenu;
                case "custom": return ShortcutFolderMode.Custom;
                default: return ShortcutFolderMode.Desktop;
            }
        }

        public static string FolderModeToken(ShortcutFolderMode mode) => mode switch
        {
            ShortcutFolderMode.StartMenu => "startmenu",
            ShortcutFolderMode.Custom => "custom",
            _ => "desktop",
        };
    }
}
