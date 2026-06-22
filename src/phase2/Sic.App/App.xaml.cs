using System;
using System.Windows;
using Sic.App.Localization;
using Sic.Core;
using Sic.Core.Localization;

namespace Sic.App
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            try
            {
                Run(e.Args);
            }
            catch (Exception ex)
            {
                var s = ResolveStrings();
                MessageBox.Show(ex.Message, s.ErrorTitle, MessageBoxButton.OK, MessageBoxImage.Error);
            }
            Shutdown(0);
        }

        private static bool Is(string a, string flag) =>
            a.Equals(flag, StringComparison.OrdinalIgnoreCase);

        private void Run(string[] args)
        {
            string? lnk = null;
            string? iconPath = null;
            bool reset = false;

            for (int i = 0; i < args.Length; i++)
            {
                var a = args[i];
                if (Is(a, "-Reset") || Is(a, "/Reset")) reset = true;
                else if (Is(a, "-IconPath") || Is(a, "/IconPath")) { if (i + 1 < args.Length) iconPath = args[++i]; }
                else if (Is(a, "-Lnk") || Is(a, "/Lnk")) { if (i + 1 < args.Length) lnk = args[++i]; }
                else if (a.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase)) lnk = a;
            }

            // UI を介さない直接適用（コンテキスト メニュー/スクリプト用）
            if (reset)
            {
                if (lnk == null) throw new ArgumentException("-Reset には対象の .lnk が必要です。");
                ShortcutService.ResetIcon(lnk);
                return;
            }
            if (iconPath != null)
            {
                if (lnk == null) throw new ArgumentException("-IconPath には対象の .lnk が必要です。");
                ShortcutService.SetIcon(lnk, iconPath);
                return;
            }

            var settings = AppSettings.Load();
            ThemeManager.Apply(settings);

            // コンテキスト メニュー起動（対象 .lnk あり）: 即ピッカーを表示して適用する。
            // 新規プロセスのコールド起動なので、遅延ゲート付きスプラッシュを有効にする。
            if (lnk != null)
            {
                var r = AppFlow.ShowPicker(settings, lnk, enableSplash: true);
                AppFlow.Apply(r);
                return;
            }

            // 単体起動（スタート メニュー/アプリ一覧/Store からの起動）: ホーム ハブを表示する。
            var home = new HomeWindow(settings);
            home.ShowDialog();
        }

        private static UiStrings ResolveStrings()
        {
            try
            {
                var s = AppSettings.Load();
                return Loc.IsJapanese(s.Language) ? UiStrings.Japanese() : UiStrings.English();
            }
            catch { return UiStrings.English(); }
        }
    }
}
