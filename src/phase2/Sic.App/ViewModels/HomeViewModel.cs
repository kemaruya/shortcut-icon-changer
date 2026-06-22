using System.ComponentModel;
using Sic.App.Localization;
using Sic.Core;
using Sic.Core.Localization;

namespace Sic.App.ViewModels
{
    /// <summary>ホーム ハブの表示用 VM（文言とバージョン）。操作はウィンドウ側で行う。</summary>
    public sealed class HomeViewModel : INotifyPropertyChanged
    {
        private readonly AppSettings _settings;

        public UiStrings Strings { get; private set; }
        public string VersionText { get; private set; }

        public HomeViewModel(AppSettings settings)
        {
            _settings = settings;
            Strings = Resolve(settings);
            VersionText = string.Format(Strings.VersionFormat, AppInfo.Version);
        }

        /// <summary>設定（言語）変更後に文言を更新する。</summary>
        public void Refresh()
        {
            Strings = Resolve(_settings);
            VersionText = string.Format(Strings.VersionFormat, AppInfo.Version);
            OnPropertyChanged(nameof(Strings));
            OnPropertyChanged(nameof(VersionText));
        }

        private static UiStrings Resolve(AppSettings s) =>
            Loc.IsJapanese(s.Language) ? UiStrings.Japanese() : UiStrings.English();

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged(string n) =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));
    }
}
