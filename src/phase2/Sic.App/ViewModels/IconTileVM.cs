using System;
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
                    _thumb = LoadThumb(Item.Path);
                }
                return _thumb;
            }
        }

        public IconTileVM(IconItem item, string displayName)
        {
            Item = item;
            DisplayName = displayName;
        }

        private static ImageSource? LoadThumb(string path)
        {
            try
            {
                var bmp = new BitmapImage();
                bmp.BeginInit();
                bmp.UriSource = new Uri(path);
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
