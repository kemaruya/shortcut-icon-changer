using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;
using Sic.App.Localization;
using Sic.Core;
using Sic.Core.Localization;

namespace Sic.App.ViewModels
{
    public sealed class MainViewModel : INotifyPropertyChanged
    {
        // タイル 1 枚の占有幅（Button Width 98 + Margin 4×2）。列数算出に使う。
        private const double TileTotalWidth = 106.0;

        private readonly List<IconItem> _all;
        private readonly AppSettings _settings;
        private bool _suppressRebuild;

        // 現フィルタの全タイル（列数変更時は同じ VM を組み直すのでデコード済みサムネは保持される）。
        private List<IconTileVM> _filtered = new List<IconTileVM>();
        private int _columns = 8; // ビューポート幅が判明するまでの暫定列数

        public ObservableCollection<ChipVM> Styles { get; } = new ObservableCollection<ChipVM>();
        public ObservableCollection<ChipVM> Genres { get; } = new ObservableCollection<ChipVM>();
        public ObservableCollection<ChipVM> Colors { get; } = new ObservableCollection<ChipVM>();

        /// <summary>仮想化リストにバインドする行（各行が最大 <c>_columns</c> 枚のタイル）。</summary>
        public ObservableCollection<TileRow> Rows { get; } = new ObservableCollection<TileRow>();

        public UiStrings Strings { get; private set; } = UiStrings.English();
        public bool IsJapanese { get; private set; }

        // 対象ショートカット（ヘッダー バーで選択/表示）
        private string? _targetLnk;
        public bool HasTarget => _targetLnk != null;
        public string TargetName => HasTarget ? System.IO.Path.GetFileNameWithoutExtension(_targetLnk) : Strings.TargetNone;
        public string TargetPath => _targetLnk ?? "";
        public string ChooseTargetLabel => HasTarget ? Strings.ChangeTarget : Strings.ChooseTarget;

        private ImageSource? _currentIcon;
        public ImageSource? CurrentIcon
        {
            get => _currentIcon;
            private set { _currentIcon = value; OnPropertyChanged(nameof(CurrentIcon)); }
        }

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
        public RelayCommand ChooseTargetCommand { get; }

        public event Action<PickResult>? RequestClose;

        public MainViewModel(AppSettings settings, string? targetLnk)
        {
            _settings = settings;
            _targetLnk = targetLnk;
            _all = IconLibrary.Enumerate();
            _languageChoice = (int)settings.Language;
            ApplyLanguageStrings();

            if (_targetLnk != null)
                _currentIcon = ShortcutIcon.LoadCurrentIcon(_targetLnk);

            ApplyCommand = new RelayCommand(p =>
            {
                if (p is IconItem it && EnsureTarget())
                    RequestClose?.Invoke(new PickResult { Kind = PickKind.Apply, IconPath = SicAssets.ResolveForApply(it), TargetLnk = _targetLnk });
            });
            ResetCommand = new RelayCommand(_ =>
            {
                if (EnsureTarget())
                    RequestClose?.Invoke(new PickResult { Kind = PickKind.Reset, TargetLnk = _targetLnk });
            });
            CustomCommand = new RelayCommand(_ => OnCustom());
            ClearTagsCommand = new RelayCommand(_ => ClearTags());
            ChooseTargetCommand = new RelayCommand(_ => ChooseTarget());

            BuildFacets();
            Rebuild();
        }

        private void ApplyLanguageStrings()
        {
            IsJapanese = Loc.IsJapanese((AppLanguage)_languageChoice);
            Strings = IsJapanese ? UiStrings.Japanese() : UiStrings.English();
            NoteText = HasTarget ? "" : Strings.SelectTargetHint;
            ContextMenu.TryUpdateLabel(IsJapanese);
            OnPropertyChanged(nameof(Strings));
            OnPropertyChanged(nameof(IsJapanese));
            OnPropertyChanged(nameof(TargetName));
            OnPropertyChanged(nameof(ChooseTargetLabel));
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

        private void BuildFacets(HashSet<string>? cs = null, HashSet<string>? cg = null, HashSet<string>? cc = null)
        {
            Styles.Clear(); Genres.Clear(); Colors.Clear();
            Action<ChipVM> onToggle = OnChipToggled;

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
            foreach (var kv in colorList)
            {
                var chip = new ChipVM(kv.Key, Loc.ColorLabel(kv.Key, IsJapanese), kv.Value,
                    onToggle, isColor: true, swatch: ToneBrush(kv.Key));
                if (cc != null && cc.Contains(kv.Key)) chip.SetCheckedSilently(true);
                Colors.Add(chip);
            }
        }

        private static void FillChips(ObservableCollection<ChipVM> target,
            List<(string Key, string Label, int Count)> data, Action<ChipVM> onToggle, HashSet<string>? checkedKeys)
        {
            foreach (var d in data)
            {
                var chip = new ChipVM(d.Key, d.Label, d.Count, onToggle);
                if (checkedKeys != null && checkedKeys.Contains(d.Key)) chip.SetCheckedSilently(true);
                target.Add(chip);
            }
        }

        /// <summary>
        /// 行内は単一選択にする。あるタグを ON にしたら同じ行（スタイル/ジャンル/色）の
        /// 他タグを外す。同じタグの再クリックによる OFF は ToggleButton の標準動作に任せる。
        /// 行をまたぐ併用（スタイル×ジャンル×色）は従来どおり維持する。
        /// </summary>
        private void OnChipToggled(ChipVM chip)
        {
            if (chip.IsChecked)
            {
                ObservableCollection<ChipVM>? group =
                      Styles.Contains(chip) ? Styles
                    : Genres.Contains(chip) ? Genres
                    : Colors.Contains(chip) ? Colors
                    : null;
                if (group != null)
                    foreach (var c in group)
                        if (!ReferenceEquals(c, chip) && c.IsChecked)
                            c.SetCheckedSilently(false);
            }
            Rebuild();
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
            if (!EnsureTarget()) return;
            var dlg = new OpenFileDialog { Filter = Strings.OpenFileFilter, CheckFileExists = true };
            if (dlg.ShowDialog() == true)
                RequestClose?.Invoke(new PickResult { Kind = PickKind.Apply, IconPath = dlg.FileName, TargetLnk = _targetLnk });
        }

        /// <summary>対象が未選択なら選択ダイアログを出す。対象が確定すれば true。</summary>
        private bool EnsureTarget() => _targetLnk != null || ChooseTarget();

        /// <summary>対象の .lnk を選ぶ。選択されたら対象とプレビューを更新して true。</summary>
        private bool ChooseTarget()
        {
            var dlg = new OpenFileDialog
            {
                Filter = IsJapanese ? "ショートカット (*.lnk)|*.lnk" : "Shortcut (*.lnk)|*.lnk",
                Title = IsJapanese ? "アイコンを変更するショートカット (.lnk) を選択してください"
                                   : "Select a shortcut (.lnk) to change its icon",
                CheckFileExists = true,
                Multiselect = false,
                InitialDirectory = SafeInitialDir(),
            };
            if (dlg.ShowDialog() != true) return false;
            SetTarget(dlg.FileName);
            return true;
        }

        private void SetTarget(string lnk)
        {
            _targetLnk = lnk;
            CurrentIcon = ShortcutIcon.LoadCurrentIcon(lnk);
            NoteText = "";
            OnPropertyChanged(nameof(HasTarget));
            OnPropertyChanged(nameof(TargetName));
            OnPropertyChanged(nameof(TargetPath));
            OnPropertyChanged(nameof(ChooseTargetLabel));
        }

        private string SafeInitialDir()
        {
            try { return _settings.ResolveShortcutFolder(); }
            catch { return ""; }
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

            // 全件をタイル化（デコードはサムネ初回アクセス時まで遅延、可視行のみ実体化）。
            _filtered = q.Select(i => new IconTileVM(i, Loc.DisplayName(i, IsJapanese))).ToList();
            CountText = string.Format(Strings.CountFormat, _filtered.Count);
            BuildRows();
        }

        /// <summary>
        /// ビューポート幅から列数を更新する。MainWindow が初回表示/リサイズ時に呼ぶ。
        /// 列数が変わったときだけ行を組み直す（同じタイル VM を使うのでサムネは再デコードされない）。
        /// </summary>
        public void SetViewportWidth(double width)
        {
            if (width <= 0) return;
            int cols = Math.Max(1, (int)((width - 12.0) / TileTotalWidth));
            if (cols == _columns && Rows.Count > 0) return;
            _columns = cols;
            BuildRows();
        }

        /// <summary>現フィルタのタイル列を <c>_columns</c> 枚ごとの行へ束ね直す。</summary>
        private void BuildRows()
        {
            Rows.Clear();
            int cols = Math.Max(1, _columns);
            for (int i = 0; i < _filtered.Count; i += cols)
            {
                int n = Math.Min(cols, _filtered.Count - i);
                var slice = new IconTileVM[n];
                for (int j = 0; j < n; j++) slice[j] = _filtered[i + j];
                Rows.Add(new TileRow(slice));
            }
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
