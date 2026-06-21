using System;
using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Sic.Core;

namespace Sic.App.ViewModels
{
    /// <summary>グリッドの 1 タイル。サムネイルは初回アクセス時に 64px でデコード。</summary>
    public sealed class IconTileVM
    {
        public IconItem Item { get; }
        public string DisplayName { get; }

        private ImageSource? _thumb;
        private bool _loaded;
        public ImageSource? Thumbnail
        {
            get
            {
                if (!_loaded)
                {
                    _loaded = true;
                    _thumb = LoadThumb(Item);
                }
                return _thumb;
            }
        }

        public IconTileVM(IconItem item, string displayName)
        {
            Item = item;
            DisplayName = displayName;
        }

        private static ImageSource? LoadThumb(IconItem item)
        {
            try
            {
                var bmp = new BitmapImage();
                bmp.BeginInit();
                if (!string.IsNullOrEmpty(item.ZipPath) && !string.IsNullOrEmpty(item.ZipEntry))
                {
                    var bytes = SicAssetZip.ReadEntry(item.ZipPath!, item.ZipEntry!);
                    if (bytes == null) { bmp.EndInit(); return null; }
                    bmp.StreamSource = new MemoryStream(bytes);
                }
                else
                {
                    bmp.UriSource = new Uri(item.Path);
                }
                bmp.DecodePixelWidth = 64;
                bmp.CacheOption = BitmapCacheOption.OnLoad;
                bmp.CreateOptions = BitmapCreateOptions.IgnoreColorProfile;
                bmp.EndInit();
                bmp.Freeze();
                return bmp;
            }
            catch { return null; }
        }
    }
}
