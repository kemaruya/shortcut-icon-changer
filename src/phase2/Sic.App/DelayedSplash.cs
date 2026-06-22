using System;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Sic.App
{
    /// <summary>
    /// 遅延ゲート付きスプラッシュ。<see cref="Begin"/> から指定ミリ秒以内に <see cref="Done"/> が
    /// 呼ばれた場合は一度も表示しない（ウォーム起動）。超過した場合のみ、UI スレッドの混雑に
    /// 依存しない専用 STA スレッド上で表示する（コールド起動で待たされた時の合図）。
    /// </summary>
    internal sealed class DelayedSplash
    {
        private readonly int _delayMs;
        private readonly ManualResetEventSlim _cancel = new ManualResetEventSlim(false);
        private readonly object _lock = new object();
        private byte[]? _imageBytes;
        private Thread? _thread;
        private Dispatcher? _dispatcher;
        private Window? _window;
        private bool _done;
        private bool _shown;

        public DelayedSplash(int delayMs) => _delayMs = delayMs;

        /// <summary>計測を開始する。画像が読めた場合のみ、専用スレッドが遅延後にスプラッシュを表示する。</summary>
        public void Begin()
        {
            // 画像読込は呼び出し（UI）スレッドで実施し、クロススレッドの pack URI 解決を避ける。
            _imageBytes = TryLoadResourceBytes("Assets/splash.png");
            if (_imageBytes == null) return;

            _thread = new Thread(ThreadProc) { IsBackground = true, Name = "SicSplash" };
            _thread.SetApartmentState(ApartmentState.STA);
            _thread.Start();
        }

        /// <summary>表示を終了する（描画完了時/終了時に呼ぶ）。遅延中なら以後も表示しない。冪等。</summary>
        public void Done()
        {
            Dispatcher? disp = null;
            lock (_lock)
            {
                if (_done) return;
                _done = true;
                _cancel.Set();          // 遅延中なら ThreadProc の待機を解除し、未表示で終了させる
                if (_shown) disp = _dispatcher;
            }
            if (disp == null) return;   // まだ表示していなければ片付け不要
            try
            {
                disp.BeginInvoke(new Action(() =>
                {
                    try { _window?.Close(); } catch { /* 失敗しても無視 */ }
                    try { disp.InvokeShutdown(); } catch { /* 既に終了などは無視 */ }
                }));
            }
            catch { /* dispatcher が既に終了している場合などは無視 */ }
        }

        private void ThreadProc()
        {
            try
            {
                // 遅延ゲート: しきい値内に Done が来たら（ウォーム起動）何も出さずに終了。
                if (_cancel.Wait(_delayMs)) return;

                lock (_lock)
                {
                    if (_done) return; // 境界で Done が来ていた場合は表示しない
                    var win = CreateWindow();
                    if (win == null) return;
                    _window = win;
                    _dispatcher = win.Dispatcher;
                    _shown = true;
                    win.Show();
                }
                Dispatcher.Run();
            }
            catch
            {
                // スプラッシュ表示の失敗が本体プロセスを巻き込まないよう握りつぶす。
                try { Dispatcher.CurrentDispatcher.InvokeShutdown(); } catch { }
            }
        }

        private Window? CreateWindow()
        {
            try
            {
                var bmp = new BitmapImage();
                bmp.BeginInit();
                bmp.StreamSource = new MemoryStream(_imageBytes!, writable: false);
                bmp.CacheOption = BitmapCacheOption.OnLoad;
                bmp.EndInit();
                bmp.Freeze();

                return new Window
                {
                    WindowStyle = WindowStyle.None,
                    ResizeMode = ResizeMode.NoResize,
                    AllowsTransparency = true,
                    Background = Brushes.Transparent,
                    ShowInTaskbar = false,
                    Topmost = true,
                    WindowStartupLocation = WindowStartupLocation.CenterScreen,
                    SizeToContent = SizeToContent.WidthAndHeight,
                    Content = new Image { Source = bmp, Stretch = Stretch.None },
                };
            }
            catch
            {
                return null; // 画像デコード/ウィンドウ生成失敗時はスプラッシュ無しで続行
            }
        }

        private static byte[]? TryLoadResourceBytes(string relativePath)
        {
            try
            {
                var info = Application.GetResourceStream(new Uri(relativePath, UriKind.Relative));
                if (info?.Stream == null) return null;
                using (var s = info.Stream)
                using (var ms = new MemoryStream())
                {
                    s.CopyTo(ms);
                    return ms.ToArray();
                }
            }
            catch
            {
                return null;
            }
        }
    }
}
