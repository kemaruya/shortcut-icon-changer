using System;
using System.IO;

namespace Sic.Core
{
    /// <summary>アプリのデータ パス解決（SicCore.psm1 の Get-Sic*Path を移植）。</summary>
    public static class SicPaths
    {
        /// <summary>テストや特殊配置でスターター ディレクトリを明示する場合に設定。</summary>
        public static string? StarterPathOverride { get; set; }

        public static string Root()
        {
            var root = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "ShortcutIconChanger");
            Directory.CreateDirectory(root);
            return root;
        }

        public static string LibraryPath()
        {
            var p = Path.Combine(Root(), "library");
            Directory.CreateDirectory(p);
            return p;
        }

        public static string CachePath()
        {
            var p = Path.Combine(Root(), "cache");
            Directory.CreateDirectory(p);
            return p;
        }

        public static string SettingsPath() => Path.Combine(Root(), "settings.json");

        /// <summary>同梱スターター アイコンの場所。導入レイアウト/開発レイアウト/環境変数を順に探索。</summary>
        public static string? StarterPath()
        {
            if (!string.IsNullOrEmpty(StarterPathOverride) && Directory.Exists(StarterPathOverride))
                return Path.GetFullPath(StarterPathOverride!);

            var env = Environment.GetEnvironmentVariable("SIC_STARTER_DIR");
            if (!string.IsNullOrEmpty(env) && Directory.Exists(env))
                return Path.GetFullPath(env!);

            var baseDir = AppDomain.CurrentDomain.BaseDirectory;
            var candidates = new[]
            {
                Path.Combine(baseDir, "assets", "starter-icons"),
                Path.Combine(baseDir, "Assets", "starter-icons"),
            };
            foreach (var c in candidates)
                if (Directory.Exists(c)) return Path.GetFullPath(c);

            // 開発時: bin から上方向にリポジトリの assets を探索。
            var dir = new DirectoryInfo(baseDir);
            for (int i = 0; i < 8 && dir != null; i++, dir = dir.Parent)
            {
                var probe = Path.Combine(dir.FullName, "assets", "starter-icons");
                if (Directory.Exists(probe)) return Path.GetFullPath(probe);
            }
            return null;
        }
    }
}
