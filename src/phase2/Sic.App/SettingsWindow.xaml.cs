using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using Sic.App.ViewModels;
using Sic.Core;

namespace Sic.App
{
    public partial class SettingsWindow : Window
    {
        private readonly AppSettings _settings;
        private readonly SettingsViewModel _vm;

        public SettingsWindow(AppSettings settings)
        {
            InitializeComponent();
            _settings = settings;
            _vm = new SettingsViewModel(settings);
            DataContext = _vm;
        }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            ThemeManager.ApplyTitleBar(this);
        }

        private void Browse_Click(object sender, RoutedEventArgs e)
        {
            using var dlg = new System.Windows.Forms.FolderBrowserDialog
            {
                Description = _vm.Strings.ShortcutFolderLabel,
                SelectedPath = string.IsNullOrEmpty(_vm.CustomFolder)
                    ? Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)
                    : _vm.CustomFolder,
            };
            if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK)
                _vm.CustomFolder = dlg.SelectedPath;
        }

        private void ClearCache_Click(object sender, RoutedEventArgs e)
        {
            var s = _vm.Strings;
            var ok = MessageBox.Show(this, s.CacheClearWarning, s.SettingsTitle,
                MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No);
            if (ok != MessageBoxResult.Yes) return;
            int n = _vm.ClearCache();
            MessageBox.Show(this, string.Format(s.CacheClearedFormat, n), s.SettingsTitle,
                MessageBoxButton.OK, MessageBoxImage.Information);
        }

        private void OpenCache_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                var path = SicPaths.CachePath();
                Directory.CreateDirectory(path);
                Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
            }
            catch { /* エクスプローラー起動失敗は無視 */ }
        }

        private void GitHub_Click(object sender, RoutedEventArgs e)
        {
            try { Process.Start(new ProcessStartInfo(AppInfo.GitHubUrl) { UseShellExecute = true }); }
            catch { /* ブラウザ起動失敗は無視 */ }
        }

        private void ResetSettings_Click(object sender, RoutedEventArgs e)
        {
            var s = _vm.Strings;
            var ok = MessageBox.Show(this, s.ResetSettingsConfirm, s.SettingsTitle,
                MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No);
            if (ok != MessageBoxResult.Yes) return;
            _vm.ResetSettings();
        }

        private void Close_Click(object sender, RoutedEventArgs e) => Close();
    }
}
