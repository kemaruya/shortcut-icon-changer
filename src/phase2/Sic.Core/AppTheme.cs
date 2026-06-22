namespace Sic.Core
{
    /// <summary>アプリの外観テーマ。System は OS のライト/ダーク設定に追従する。</summary>
    public enum AppTheme
    {
        System = 0,
        Light = 1,
        Dark = 2,
    }

    /// <summary>単体起動時に「アイコンを変更するショートカット」を選ぶ既定フォルダー。</summary>
    public enum ShortcutFolderMode
    {
        Desktop = 0,
        StartMenu = 1,
        Custom = 2,
    }
}
