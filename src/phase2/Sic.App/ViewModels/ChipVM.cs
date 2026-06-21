using System;
using System.ComponentModel;
using System.Windows.Media;

namespace Sic.App.ViewModels
{
    /// <summary>ファセットの 1 タグ（チップ）。Key は正規値、Label はローカライズ済み表示。</summary>
    public sealed class ChipVM : INotifyPropertyChanged
    {
        private readonly Action _onToggle;

        public string Key { get; }
        public string Label { get; }
        public int Count { get; }
        public double FontSize { get; }
        public bool IsColor { get; }
        public Brush? Swatch { get; }
        public string Display => $"{Label} ({Count})";

        private bool _isChecked;
        public bool IsChecked
        {
            get => _isChecked;
            set
            {
                if (_isChecked != value)
                {
                    _isChecked = value;
                    OnPropertyChanged(nameof(IsChecked));
                    _onToggle();
                }
            }
        }

        public ChipVM(string key, string label, int count, double fontSize, Action onToggle,
                      bool isColor = false, Brush? swatch = null)
        {
            Key = key;
            Label = label;
            Count = count;
            FontSize = fontSize;
            _onToggle = onToggle;
            IsColor = isColor;
            Swatch = swatch;
        }

        /// <summary>イベントを発火せずチェック状態だけ戻す（一括クリア用）。</summary>
        public void SetCheckedSilently(bool value)
        {
            if (_isChecked != value)
            {
                _isChecked = value;
                OnPropertyChanged(nameof(IsChecked));
            }
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged(string n) =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));
    }
}
