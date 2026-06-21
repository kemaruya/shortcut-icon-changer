using System;
using System.Windows;
using Sic.App.Localization;
using Sic.App.ViewModels;
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

            // ピッカー UI
            // 体感改善: UI パスと判定でき次第すぐにスプラッシュを表示し、ViewModel/ウィンドウ
            // 構築や初回描画の待ち時間を覆う。スプラッシュはウィンドウの初回描画
            // （ContentRendered）で短いフェードと共に閉じる。
            var splash = new SplashScreen("Assets/splash.png");
            splash.Show(autoClose: false);
            bool splashClosed = false;
            void CloseSplash()
            {
                if (splashClosed) return;
                splashClosed = true;
                splash.Close(TimeSpan.FromMilliseconds(250));
            }

            var settings = AppSettings.Load();
            var vm = new MainViewModel(settings, hasLnk: lnk != null);
            var win = new MainWindow(vm);

            // 初回描画後: スプラッシュを閉じ、残りのタイルの背景投入を開始する。
            win.ContentRendered += (_, __) => { CloseSplash(); vm.StartDeferredFill(); };

            try { win.ShowDialog(); }
            finally { CloseSplash(); }

            var r = win.Result;
            if (r == null || r.Kind == PickKind.Cancel) return;
            if (lnk == null) return; // ショートカット未指定 → プレビューのみ

            if (r.Kind == PickKind.Reset)
                ShortcutService.ResetIcon(lnk);
            else if (r.Kind == PickKind.Apply && !string.IsNullOrEmpty(r.IconPath))
                ShortcutService.SetIcon(lnk, r.IconPath!);
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
