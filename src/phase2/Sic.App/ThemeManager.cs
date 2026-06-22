using System;
using System.Linq;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Sic.App.Interop;
using Sic.Core;

namespace Sic.App
{
    /// <summary>
    /// アプリ全体のテーマ（ライト/ダーク）を司る。ブラシ辞書をコードで構築して
    /// Application.Resources に差し込み、各ウィンドウは <c>{DynamicResource Sic.*}</c> で参照する。
    /// テーマ変更時は辞書を差し替えるだけで開いている全ウィンドウへ即時反映される。
    /// </summary>
    internal static class ThemeManager
    {
        private const string Tag = "Sic.ThemeTag";

        public static bool CurrentIsDark { get; private set; }

        /// <summary>設定値と OS 設定から、実効的にダークかどうかを決める。</summary>
        public static bool EffectiveDark(AppSettings s) => s.Theme switch
        {
            AppTheme.Light => false,
            AppTheme.Dark => true,
            _ => DwmHelper.IsSystemDark(),
        };

        /// <summary>テーマ ブラシ辞書を構築して Application.Resources に適用する。</summary>
        public static void Apply(AppSettings s)
        {
            var app = Application.Current;
            if (app == null) return;
            var dark = EffectiveDark(s);
            var dict = Build(dark);

            var existing = app.Resources.MergedDictionaries.FirstOrDefault(d => d.Contains(Tag));
            if (existing != null) app.Resources.MergedDictionaries.Remove(existing);
            app.Resources.MergedDictionaries.Insert(0, dict);
            CurrentIsDark = dark;
        }

        /// <summary>テーマ変更を即時反映（辞書差し替え＋開いている全ウィンドウのタイトルバー）。</summary>
        public static void Reapply(AppSettings s)
        {
            Apply(s);
            var app = Application.Current;
            if (app == null) return;
            foreach (Window w in app.Windows) ApplyTitleBar(w);
        }

        /// <summary>ウィンドウのタイトルバーを現在の実効テーマに合わせる（OnSourceInitialized から呼ぶ）。</summary>
        public static void ApplyTitleBar(Window w)
        {
            try
            {
                var hwnd = new WindowInteropHelper(w).Handle;
                if (hwnd != IntPtr.Zero)
                    DwmHelper.TryApplyDarkTitleBar(hwnd, CurrentIsDark);
            }
            catch { /* 外観の微調整失敗は無視 */ }
        }

        private static ResourceDictionary Build(bool dark)
        {
            var d = new ResourceDictionary { [Tag] = true };
            void B(string key, string light, string darkHex) => d[key] = Frozen(dark ? darkHex : light);

            //         key                    light      dark
            B("Sic.Window",        "#F3F3F3", "#202020");
            B("Sic.Panel",         "#FFFFFF", "#2B2B2B");
            B("Sic.PanelBorder",   "#E2E2E2", "#3C3C3C");
            B("Sic.Text",          "#202020", "#F0F0F0");
            B("Sic.TextSecondary", "#606060", "#B4B4B4");
            B("Sic.Subtle",        "#9AA0A6", "#8A8F94");
            B("Sic.Accent",        "#0067C0", "#2D7FD3");
            B("Sic.AccentText",    "#FFFFFF", "#FFFFFF");
            B("Sic.ControlBg",     "#FFFFFF", "#333333");
            B("Sic.ControlBorder", "#CCCCCC", "#4A4A4A");
            B("Sic.ChipBg",        "#ECECEC", "#3A3A3A");
            B("Sic.ChipBgHover",   "#E0E0E0", "#464646");
            B("Sic.ChipBorder",    "#DADADA", "#4A4A4A");
            B("Sic.ChipText",      "#202020", "#E8E8E8");
            B("Sic.TileHover",     "#FFFFFF", "#3A3A3A");
            B("Sic.NoteBg",        "#FFF4E5", "#3A2F1A");
            B("Sic.NoteBorder",    "#F0C77A", "#6B5320");
            B("Sic.NoteText",      "#8A5A00", "#E5C07B");
            B("Sic.ButtonBg",      "#FDFDFD", "#333333");
            B("Sic.ButtonBgHover", "#F0F0F0", "#3E3E3E");
            B("Sic.ButtonBorder",  "#D0D0D0", "#4A4A4A");
            B("Sic.CardBgHover",   "#F5F9FF", "#343A42");
            return d;
        }

        private static SolidColorBrush Frozen(string hex)
        {
            var c = (Color)ColorConverter.ConvertFromString(hex)!;
            var b = new SolidColorBrush(c);
            b.Freeze();
            return b;
        }
    }
}
