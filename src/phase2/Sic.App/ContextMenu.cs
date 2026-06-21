using Microsoft.Win32;

namespace Sic.App
{
    /// <summary>
    /// シェル右クリック動詞（.lnk の「アイコンを変更」）のラベルを表示言語に合わせて更新する。
    /// キーの作成/削除は MSI が所有し、ここでは存在する場合のみ表示名を上書きする。
    /// </summary>
    internal static class ContextMenu
    {
        private const string VerbKey = @"Software\Classes\lnkfile\shell\sic.changeicon";

        public static void TryUpdateLabel(bool ja)
        {
            try
            {
                using var k = Registry.CurrentUser.OpenSubKey(VerbKey, writable: true);
                if (k == null) return; // 未インストール時は何もしない
                k.SetValue(null, ja ? "アイコンを変更(&I)" : "Change icon\u2026");
            }
            catch { /* ラベル更新失敗は無視 */ }
        }
    }
}
