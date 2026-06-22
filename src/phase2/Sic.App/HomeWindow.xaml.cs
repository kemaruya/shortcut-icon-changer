using System;
using System.Diagnostics;
using System.Windows;
using Sic.App.ViewModels;
using Sic.Core;

namespace Sic.App
{
    public partial class HomeWindow : Window
    {
        private readonly AppSettings _settings;
        private readonly HomeViewModel _vm;

        public HomeWindow(AppSettings settings)
        {
            InitializeComponent();
            _settings = settings;
            _vm = new HomeViewModel(settings);
            DataContext = _vm;
        }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            ThemeManager.ApplyTitleBar(this);
        }

        private void ChangeIcon_Click(object sender, RoutedEventArgs e)
        {
            // 対象未選択でピッカーを開く（ヘッダー バーで対象を選んでから適用）。
            // ホームは既にプロセス稼働中（ウォーム）なのでスプラッシュは出さない。
            var r = AppFlow.ShowPicker(_settings, null, enableSplash: false);
            AppFlow.Apply(r);
        }

        private void Settings_Click(object sender, RoutedEventArgs e)
        {
            var win = new SettingsWindow(_settings) { Owner = this };
            win.ShowDialog();
            // 言語が変わっている場合に備えてホームの文言を更新（テーマは即時反映済み）。
            _vm.Refresh();
        }

        private void GitHub_Click(object sender, RoutedEventArgs e)
        {
            try { Process.Start(new ProcessStartInfo(AppInfo.GitHubUrl) { UseShellExecute = true }); }
            catch { /* ブラウザ起動失敗は無視 */ }
        }
    }
}
