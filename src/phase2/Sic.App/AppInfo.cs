using System.Reflection;

namespace Sic.App
{
    /// <summary>アプリのメタ情報（バージョン・リポジトリ URL）。About 表示などで共有する。</summary>
    internal static class AppInfo
    {
        public const string GitHubUrl = "https://github.com/kemaruya/shortcut-icon-changer";

        /// <summary>アセンブリ バージョンの x.y.z 表記。</summary>
        public static string Version
        {
            get
            {
                try
                {
                    var v = Assembly.GetExecutingAssembly().GetName().Version;
                    return v == null ? "" : $"{v.Major}.{v.Minor}.{v.Build}";
                }
                catch { return ""; }
            }
        }
    }
}
