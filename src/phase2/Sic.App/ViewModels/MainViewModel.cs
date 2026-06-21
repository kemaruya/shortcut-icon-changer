using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using Sic.App.Localization;
using Sic.Core;
using Sic.Core.Localization;

namespace Sic.App.ViewModels
{
    public sealed class MainViewModel : INotifyPropertyChanged
    {
        private const int MaxItems = 500;

        // タイルの分割投入用。最初の 1 画面分だけ即時、残りは背景優先度で少しずつ。
        private const int FirstChunk = 48;
        private const int NextChunk = 32;
        private int _populateToken;
        private List<IconItem> _tail = new List<IconItem>();
        private bool _windowShown;

        private readonly List<IconItem> _all;
        private readonly AppSettings _settings;
        private bool _suppressRebuild;

        public ObservableCollection<ChipVM> Styles { get; } = new ObservableCollection<ChipVM>();
        public ObservableCollection<ChipVM> Genres { get; } = new ObservableCollection<ChipVM>();
        public ObservableCollection<ChipVM> Colors { get; } = new ObservableCollection<ChipVM>();
        public ObservableCollection<IconTileVM> Tiles { get; } = new ObservableCollection<IconTileVM>();

        public UiStrings Strings { get; private set; } = UiStrings.English();
        public bool IsJapanese { get; private set; }
        public bool HasLnk { get; }

        private string _searchText = "";
        public string SearchText
        {
            get => _searchText;
            set { if (_searchText != value) { _searchText = value; OnPropertyChanged(nameof(SearchText)); Rebuild(); } }
        }

        private string _countText = "";
        public string CountText
        {
            get => _countText;
            private set { _countText = value; OnPropertyChanged(nameof(CountText)); }
        }

        private string _noteText = "";
        public string NoteText
        {
            get => _noteText;
            private set { _noteText = value; OnPropertyChanged(nameof(NoteText)); }
        }

        private int _languageChoice; // 0 Auto / 1 Japanese / 2 English
        public int LanguageChoice
        {
            get => _languageChoice;
            set { if (_languageChoice != value) { _languageChoice = value; OnPropertyChanged(nameof(LanguageChoice)); OnLanguageChanged(); } }
        }

        public RelayCommand ApplyCommand { get; }
        public RelayCommand ResetCommand { get; }
        public RelayCommand CustomCommand { get; }
        public RelayCommand ClearTagsCommand { get; }

        public event Action<PickResult>? RequestClose;

        public MainViewModel(AppSettings settings, bool hasLnk)
        {
            _settings = settings;
            HasLnk = hasLnk;
            _all = IconLibrary.Enumerate();
            _languageChoice = (int)settings.Language;
            ApplyLanguageStrings();

            ApplyCommand = new RelayCommand(p =>
            {
                if (p is IconItem it)
                    RequestClose?.Invoke(new PickResult { Kind = PickKind.Apply, IconPath = it.Path });
            });
            ResetCommand = new RelayCommand(_ =>
                RequestClose?.Invoke(new PickResult { Kind = PickKind.Reset }));
            CustomCommand = new RelayCommand(_ => OnCustom());
            ClearTagsCommand = new RelayCommand(_ => ClearTags());

            BuildFacets();
            Rebuild();
        }

        private void ApplyLanguageStrings()
        {
            IsJapanese = Loc.IsJapanese((AppLanguage)_languageChoice);
            Strings = IsJapanese ? UiStrings.Japanese() : UiStrings.English();
            NoteText = HasLnk ? "" : Strings.NoLnkNote;
            ContextMenu.TryUpdateLabel(IsJapanese);
            OnPropertyChanged(nameof(Strings));
            OnPropertyChanged(nameof(IsJapanese));
        }

        private void OnLanguageChanged()
        {
            var cs = new HashSet<string>(Styles.Where(c => c.IsChecked).Select(c => c.Key));
            var cg = new HashSet<string>(Genres.Where(c => c.IsChecked).Select(c => c.Key));
            var cc = new HashSet<string>(Colors.Where(c => c.IsChecked).Select(c => c.Key));

            _settings.Language = (AppLanguage)_languageChoice;
            try { _settings.Save(); } catch { /* 設定保存失敗は無視 */ }

            ApplyLanguageStrings();
            BuildFacets(cs, cg, cc);
            Rebuild();
        }

        private static double ScaleFont(int count, int min, int max)
        {
            if (max <= min) return 13.0;
            double t = (double)(count - min) / (max - min);
            return 11.0 + t * (17.0 - 11.0);
        }

        private void BuildFacets(HashSet<string>? cs = null, HashSet<string>? cg = null, HashSet<string>? cc = null)
        {
            Styles.Clear(); Genres.Clear(); Colors.Clear();
            Action onToggle = Rebuild;

            // スタイル（正規英語キー、StyleOrder 順）
            var styleGroups = _all.Where(i => !string.IsNullOrEmpty(i.Style))
                .GroupBy(i => i.Style)
                .Select(g => new { Key = g.Key, StyleJa = g.First().StyleJa, Count = g.Count() })
                .OrderBy(g => SicMaps.StyleIndex(g.StyleJa))
                .ToList();
            FillChips(Styles,
                styleGroups.Select(g => (g.Key, Loc.StyleLabel(g.Key, g.StyleJa, IsJapanese), g.Count)).ToList(),
                onToggle, cs);

            // ジャンル（正規英語カテゴリ、件数降順）
            var genreGroups = _all.Where(i => !string.IsNullOrEmpty(i.Category))
                .GroupBy(i => i.Category)
                .Select(g => new { Key = g.Key, Item = g.First(), Count = g.Count() })
                .OrderByDescending(g => g.Count)
                .ToList();
            FillChips(Genres,
                genreGroups.Select(g => (g.Key, Loc.CategoryLabel(g.Item, IsJapanese), g.Count)).ToList(),
                onToggle, cg);

            // 色調（正規日本語トーン、ToneOrder 順、色見本付き）
            var colorCounts = new Dictionary<string, int>();
            foreach (var it in _all)
                foreach (var c in it.Colors)
                    colorCounts[c] = colorCounts.TryGetValue(c, out var n) ? n + 1 : 1;

            var colorList = colorCounts.OrderBy(kv => SicMaps.ToneIndex(kv.Key)).ToList();
            int cmin = colorList.Count > 0 ? colorList.Min(kv => kv.Value) : 0;
            int cmax = colorList.Count > 0 ? colorList.Max(kv => kv.Value) : 0;
            foreach (var kv in colorList)
            {
                var chip = new ChipVM(kv.Key, Loc.ColorLabel(kv.Key, IsJapanese), kv.Value,
                    ScaleFont(kv.Value, cmin, cmax), onToggle, isColor: true, swatch: ToneBrush(kv.Key));
                if (cc != null && cc.Contains(kv.Key)) chip.SetCheckedSilently(true);
                Colors.Add(chip);
            }
        }

        private static void FillChips(ObservableCollection<ChipVM> target,
            List<(string Key, string Label, int Count)> data, Action onToggle, HashSet<string>? checkedKeys)
        {
            int min = data.Count > 0 ? data.Min(d => d.Count) : 0;
            int max = data.Count > 0 ? data.Max(d => d.Count) : 0;
            foreach (var d in data)
            {
                var chip = new ChipVM(d.Key, d.Label, d.Count, ScaleFont(d.Count, min, max), onToggle);
                if (checkedKeys != null && checkedKeys.Contains(d.Key)) chip.SetCheckedSilently(true);
                target.Add(chip);
            }
        }

        private void ClearTags()
        {
            _suppressRebuild = true;
            foreach (var c in Styles) c.SetCheckedSilently(false);
            foreach (var c in Genres) c.SetCheckedSilently(false);
            foreach (var c in Colors) c.SetCheckedSilently(false);
            _suppressRebuild = false;
            Rebuild();
        }

        private void OnCustom()
        {
            var dlg = new OpenFileDialog { Filter = Strings.OpenFileFilter, CheckFileExists = true };
            if (dlg.ShowDialog() == true)
                RequestClose?.Invoke(new PickResult { Kind = PickKind.Apply, IconPath = dlg.FileName });
        }

        private void Rebuild()
        {
            if (_suppressRebuild) return;

            var styles = new HashSet<string>(Styles.Where(c => c.IsChecked).Select(c => c.Key));
            var genres = new HashSet<string>(Genres.Where(c => c.IsChecked).Select(c => c.Key));
            var colors = new HashSet<string>(Colors.Where(c => c.IsChecked).Select(c => c.Key));

            IEnumerable<IconItem> q = IconFilter.ByFacets(_all, styles, genres, colors);

            var term = (_searchText ?? "").Trim();
            if (term.Length > 0)
            {
                var t = term.ToLowerInvariant();
                q = q.Where(i => Loc.SearchHaystack(i, IsJapanese).ToLowerInvariant().Contains(t));
            }

            var list = q.Take(MaxItems).ToList();
            CountText = string.Format(Strings.CountFormat, list.Count);
            PopulateTiles(list);
        }

        /// <summary>
        /// タイルを分割投入する。最初の 1 画面分だけ即時に追加する。残りは:
        /// ・初回（ウィンドウ未表示）はフィールドに退避し、<see cref="StartDeferredFill"/>
        ///   （MainWindow の初回描画後に呼ばれる）まで投入を保留 → 初回描画が 48 枚で素早く完了。
        /// ・以降（フィルタ変更時）は背景優先度で逐次投入。
        /// フィルタが変わると進行中の投入は <see cref="_populateToken"/> で中断する。
        /// </summary>
        private void PopulateTiles(List<IconItem> list)
        {
            int token = ++_populateToken;
            Tiles.Clear();
            _tail = new List<IconItem>();

            int first = Math.Min(FirstChunk, list.Count);
            for (int i = 0; i < first; i++)
                Tiles.Add(new IconTileVM(list[i], Loc.DisplayName(list[i], IsJapanese)));

            if (first >= list.Count) return;
            var tail = list.GetRange(first, list.Count - first);

            var dispatcher = Application.Current?.Dispatcher;
            if (dispatcher == null)
            {
                // ディスパッチャ未取得（テスト等）は同期で全投入。
                foreach (var it in tail)
                    Tiles.Add(new IconTileVM(it, Loc.DisplayName(it, IsJapanese)));
                return;
            }

            if (!_windowShown)
            {
                // ウィンドウ初回描画を 48 枚で素早く終わらせるため、残りは保留。
                _tail = tail;
                return;
            }
            StreamTail(tail, token, dispatcher);
        }

        private void StreamTail(List<IconItem> tail, int token, Dispatcher dispatcher)
        {
            int i = 0;
            void AddMore()
            {
                if (token != _populateToken) return; // 新しいフィルタが来たので中断
                int end = Math.Min(i + NextChunk, tail.Count);
                for (; i < end; i++)
                    Tiles.Add(new IconTileVM(tail[i], Loc.DisplayName(tail[i], IsJapanese)));
                if (i < tail.Count)
                    dispatcher.BeginInvoke((Action)AddMore, DispatcherPriority.Background);
            }
            dispatcher.BeginInvoke((Action)AddMore, DispatcherPriority.Background);
        }

        /// <summary>
        /// MainWindow の初回描画完了後に呼ぶ。保留していた残りタイルの背景投入を開始する。
        /// 以降のフィルタ変更では <see cref="PopulateTiles"/> が即座に逐次投入する。
        /// </summary>
        public void StartDeferredFill()
        {
            _windowShown = true;
            var tail = _tail;
            _tail = new List<IconItem>();
            if (tail.Count == 0) return;
            var dispatcher = Application.Current?.Dispatcher;
            if (dispatcher == null) return;
            StreamTail(tail, _populateToken, dispatcher);
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged(string n) =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));

        private static Brush ToneBrush(string tone)
        {
            static Color C(byte r, byte g, byte b) => Color.FromRgb(r, g, b);
            switch (tone)
            {
                case "赤": return Frozen(C(0xE5, 0x39, 0x35));
                case "橙": return Frozen(C(0xFB, 0x8C, 0x00));
                case "黄": return Frozen(C(0xFD, 0xD8, 0x35));
                case "緑": return Frozen(C(0x43, 0xA0, 0x47));
                case "青": return Frozen(C(0x1E, 0x88, 0xE5));
                case "紫": return Frozen(C(0x8E, 0x24, 0xAA));
                case "桃": return Frozen(C(0xEC, 0x40, 0x7A));
                case "茶": return Frozen(C(0x8D, 0x6E, 0x63));
                case "白": return Frozen(C(0xFA, 0xFA, 0xFA));
                case "灰": return Frozen(C(0x9E, 0x9E, 0x9E));
                case "黒": return Frozen(C(0x21, 0x21, 0x21));
                case "多色":
                    var g = new LinearGradientBrush
                    {
                        StartPoint = new Point(0, 0),
                        EndPoint = new Point(1, 1),
                    };
                    g.GradientStops.Add(new GradientStop(C(0xE5, 0x39, 0x35), 0.0));
                    g.GradientStops.Add(new GradientStop(C(0xFD, 0xD8, 0x35), 0.33));
                    g.GradientStops.Add(new GradientStop(C(0x43, 0xA0, 0x47), 0.66));
                    g.GradientStops.Add(new GradientStop(C(0x1E, 0x88, 0xE5), 1.0));
                    g.Freeze();
                    return g;
                default: return Frozen(C(0xBD, 0xBD, 0xBD));
            }
        }

        private static SolidColorBrush Frozen(Color c)
        {
            var b = new SolidColorBrush(c);
            b.Freeze();
            return b;
        }
    }
}
