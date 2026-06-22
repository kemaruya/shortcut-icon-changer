using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace Sic.App
{
    /// <summary>空文字なら Visible（プレースホルダ表示）、非空なら Collapsed。</summary>
    public sealed class EmptyStringToVisibilityConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
            string.IsNullOrEmpty(value as string) ? Visibility.Visible : Visibility.Collapsed;

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
            throw new NotSupportedException();
    }

    /// <summary>非空なら Visible、空なら Collapsed。</summary>
    public sealed class NonEmptyStringToVisibilityConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
            string.IsNullOrEmpty(value as string) ? Visibility.Collapsed : Visibility.Visible;

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
            throw new NotSupportedException();
    }

    /// <summary>true なら Collapsed、false なら Visible（BooleanToVisibility の反転）。</summary>
    public sealed class InverseBooleanToVisibilityConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
            (value is bool b && b) ? Visibility.Collapsed : Visibility.Visible;

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
            throw new NotSupportedException();
    }

    /// <summary>
    /// 値が ConverterParameter と一致すれば true。セグメント選択（RadioButton）用。
    /// ConvertBack は true のときだけ束縛元の型（enum/int 等）へ ConverterParameter を変換して返す。
    /// </summary>
    public sealed class EqualityToBoolConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
            string.Equals(value?.ToString(), parameter?.ToString(), StringComparison.Ordinal);

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            if (value is bool b && b && parameter != null)
            {
                try
                {
                    if (targetType.IsEnum) return Enum.Parse(targetType, parameter.ToString()!);
                    return System.Convert.ChangeType(parameter, targetType, culture);
                }
                catch { return Binding.DoNothing; }
            }
            return Binding.DoNothing;
        }
    }
}
