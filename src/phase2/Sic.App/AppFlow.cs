using System;
using System.Windows;
using Sic.App.ViewModels;
using Sic.Core;

namespace Sic.App
{
    /// <summary>ピッカー表示と .lnk への適用フロー。コンテキスト メニュー起動とホームの両方から使う。</summary>
    internal static class AppFlow
    {
        // ピッカーが描画されるまでこの時間を超えたときだけスプラッシュを出す（コールド起動の合図）。
        private const int SplashDelayMs = 350;

        /// <summary>アイコン ピッカーを表示し、選択結果を返す。targetLnk が null なら対象未選択で開く。
        /// enableSplash が true のとき（右クリックのコールド起動）だけ遅延ゲート付きスプラッシュを使う。
        /// ホームからのウォーム起動は false にして点滅を出さない。</summary>
        public static PickResult? ShowPicker(AppSettings settings, string? targetLnk, bool enableSplash)
        {
            var splash = enableSplash ? new DelayedSplash(SplashDelayMs) : null;
            splash?.Begin();

            var vm = new MainViewModel(settings, targetLnk);
            var win = new MainWindow(vm);
            if (splash != null)
                win.ContentRendered += (_, __) => splash.Done();
            try { win.ShowDialog(); }
            finally { splash?.Done(); }
            return win.Result;
        }

        /// <summary>ピッカーの選択結果を、結果に含まれる対象 .lnk へ適用する。</summary>
        public static void Apply(PickResult? r)
        {
            if (r == null || r.Kind == PickKind.Cancel) return;
            var lnk = r.TargetLnk;
            if (string.IsNullOrEmpty(lnk)) return;
            if (r.Kind == PickKind.Reset)
                ShortcutService.ResetIcon(lnk!);
            else if (r.Kind == PickKind.Apply && !string.IsNullOrEmpty(r.IconPath))
                ShortcutService.SetIcon(lnk!, r.IconPath!);
        }
    }
}
