using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Sic.App
{
    /// <summary>
    /// シェル右クリック動詞（.lnk の「アイコンを変更」）の表示名・アイコン・コマンドを、
    /// 実行中の exe に合わせて自己修復する。キーの作成/削除は MSI が所有し、ここでは
    /// 「キーが既に存在する場合のみ」値を上書きする（未インストール環境では何もしない）。
    /// 古い登録やシェルのアイコン キャッシュの残骸で右クリック アイコンが化けるのを直す目的で、
    /// 値を更新したときはアイコン キャッシュの更新をシェルへ通知する。
    /// </summary>
    internal static class ContextMenu
    {
        private const string VerbKey = @"Software\Classes\lnkfile\shell\sic.changeicon";

        public static void TryRepair(bool ja)
        {
            try
            {
                var exe = Process.GetCurrentProcess().MainModule?.FileName;
                if (string.IsNullOrEmpty(exe)) return;

                using var k = Registry.CurrentUser.OpenSubKey(VerbKey, writable: true);
                if (k == null) return; // 未インストール（MSI 未導入）時は何もしない

                bool changed = false;

                var label = ja ? "アイコンを変更(&I)" : "Change icon\u2026";
                if ((k.GetValue(null) as string) != label) { k.SetValue(null, label); changed = true; }

                // 引用符付きで指定し、ユーザー名に空白を含むパスでも壊れないようにする。
                var icon = "\"" + exe + "\",0";
                if ((k.GetValue("Icon") as string) != icon) { k.SetValue("Icon", icon); changed = true; }

                using (var cmd = k.CreateSubKey("command"))
                {
                    var command = "\"" + exe + "\" \"%1\"";
                    if (cmd != null && (cmd.GetValue(null) as string) != command)
                    {
                        cmd.SetValue(null, command);
                        changed = true;
                    }
                }

                if (changed) NotifyShell();
            }
            catch { /* 修復失敗は無視（本体機能には影響しない） */ }
        }

        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);

        /// <summary>関連付け変更をシェルへ通知し、古い右クリック アイコンのキャッシュを破棄させる。</summary>
        private static void NotifyShell()
        {
            const int SHCNE_ASSOCCHANGED = 0x08000000;
            const uint SHCNF_IDLIST = 0x0000;
            try { SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, IntPtr.Zero, IntPtr.Zero); }
            catch { /* 通知失敗は無視 */ }
        }
    }
}
