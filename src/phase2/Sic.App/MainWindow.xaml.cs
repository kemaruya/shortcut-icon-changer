using System;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using Sic.App.Interop;
using Sic.App.ViewModels;

namespace Sic.App
{
    public partial class MainWindow : Window
    {
        private readonly MainViewModel _vm;
        private readonly DispatcherTimer _resizeTimer;

        public PickResult? Result { get; private set; }

        public MainWindow(MainViewModel vm)
        {
            InitializeComponent();
            _vm = vm;
            DataContext = vm;
            vm.RequestClose += OnRequestClose;

            // リサイズの嵐を間引いてから列数を再計算する。
            _resizeTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(80) };
            _resizeTimer.Tick += (_, __) => { _resizeTimer.Stop(); PushViewportWidth(); };
            Loaded += (_, __) => PushViewportWidth();
        }

        private void PushViewportWidth()
        {
            if (IconList != null && IconList.ActualWidth > 0)
                _vm.SetViewportWidth(IconList.ActualWidth);
        }

        private void IconList_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            if (e.WidthChanged) { _resizeTimer.Stop(); _resizeTimer.Start(); }
        }

        private void OnRequestClose(PickResult r)
        {
            Result = r;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e)
        {
            Result = new PickResult { Kind = PickKind.Cancel };
            Close();
        }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            try
            {
                var hwnd = new WindowInteropHelper(this).Handle;
                DwmHelper.TryApplyDarkTitleBar(hwnd, DwmHelper.IsSystemDark());
            }
            catch { /* 外観の微調整失敗は無視 */ }
        }
    }
}
