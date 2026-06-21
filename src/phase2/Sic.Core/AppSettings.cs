using System;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;
using System.Collections.Generic;
using Sic.Core.Localization;

namespace Sic.Core
{
    /// <summary>言語設定など UI の永続設定（%LOCALAPPDATA%\ShortcutIconChanger\settings.json）。</summary>
    public sealed class AppSettings
    {
        public AppLanguage Language { get; set; } = AppLanguage.Auto;

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
                if (root != null && root.TryGetValue("language", out var lang))
                    s.Language = ParseLanguage(lang?.ToString());
                return s;
            }
            catch { return new AppSettings(); }
        }

        public void Save()
        {
            var path = SicPaths.SettingsPath();
            var json = "{\"language\":\"" + ToToken(Language) + "\"}";
            File.WriteAllText(path, json, new UTF8Encoding(false));
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
    }
}
