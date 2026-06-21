#requires -Version 5.1
<#
.SYNOPSIS
    アイコン選択ピッカー（WPF, Windows 11 同梱 .NET Framework 4.8）。
.DESCRIPTION
    dot-source して Show-SicIconPicker を利用する。
    Get-IconLibrary のアイコン（同梱スターター + 取得済みライブラリ）をグリッド表示し、
    ユーザーが選んだアイコンファイルのパスを返す。「カスタム...」で任意の .ico/.png も選べる。
    WPF のため STA スレッドで実行すること（powershell.exe -STA）。
#>

Set-StrictMode -Version Latest

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms  # OpenFileDialog 用

function New-SicIconPickerWindow {
    <#
    .SYNOPSIS
        アイコンピッカーのウィンドウを構築して返す（ShowDialog はしない）。
    .DESCRIPTION
        選択結果はウィンドウの Tag プロパティ（アイコンのパス）に格納される。
        キャンセル/×ボタンの場合は Tag は $null のまま。自動テストからも利用する。
    .PARAMETER LnkPath
        対象の .lnk（タイトル表示用）。
    #>
    [CmdletBinding()]
    param(
        [string] $LnkPath
    )

    $targetName = if ($LnkPath) { [System.IO.Path]::GetFileName($LnkPath) } else { '(ショートカット)' }

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="アイコンを変更" Height="660" Width="860"
        WindowStartupLocation="CenterScreen" Background="#FAFAFA">
  <Window.Resources>
    <Style TargetType="ToggleButton">
      <Setter Property="Margin" Value="3"/>
      <Setter Property="Padding" Value="9,3"/>
      <Setter Property="Foreground" Value="#333"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="chip" CornerRadius="11" Background="White"
                    BorderBrush="#CFCFCF" BorderThickness="1"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="chip" Property="Background" Value="#EAF3FB"/>
                <Setter TargetName="chip" Property="BorderBrush" Value="#9CC3E6"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="chip" Property="Background" Value="#0F6CBD"/>
                <Setter TargetName="chip" Property="BorderBrush" Value="#0F6CBD"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <DockPanel Margin="10">
    <StackPanel DockPanel.Dock="Top" Margin="0,0,0,8">
      <TextBlock x:Name="HeaderText" FontSize="13" Foreground="#333" Margin="2,0,0,6"/>
      <DockPanel Margin="0,0,0,6">
        <Button x:Name="ClearTagsButton" DockPanel.Dock="Right" Content="タグをクリア"
                Width="100" Height="28" Margin="6,0,0,0"
                ToolTip="選択中のタグをすべて解除します"/>
        <TextBlock DockPanel.Dock="Left" Text="絞り込み" FontSize="12" FontWeight="SemiBold"
                   Foreground="#555" VerticalAlignment="Center" Margin="2,0,8,0"/>
        <Grid>
          <TextBox x:Name="SearchBox" Height="28" VerticalContentAlignment="Center"
                   FontSize="13" Padding="6,0,0,0"
                   ToolTip="名前・キーワードで絞り込み（例: rocket, folder, star）"/>
          <TextBlock x:Name="SearchPlaceholder" IsHitTestVisible="False" Foreground="#9AA0A6"
                     FontSize="12.5" VerticalAlignment="Center" Margin="9,0,0,0"
                     Text="ここに入力して名前・キーワードで絞り込み（例: rocket / 星 / フォルダ）"/>
        </Grid>
      </DockPanel>
      <Border Background="#F2F5F8" BorderBrush="#E2E2E2" BorderThickness="1" CornerRadius="6" Padding="8,6">
        <StackPanel>
          <DockPanel>
            <TextBlock DockPanel.Dock="Left" Text="スタイル" FontSize="11" Foreground="#888"
                       VerticalAlignment="Center" Width="52" Margin="0,0,4,0"/>
            <WrapPanel x:Name="StylePanel"/>
          </DockPanel>
          <DockPanel Margin="0,6,0,0">
            <TextBlock DockPanel.Dock="Left" Text="ジャンル" FontSize="11" Foreground="#888"
                       VerticalAlignment="Center" Width="52" Margin="0,0,4,0"/>
            <WrapPanel x:Name="CategoryPanel"/>
          </DockPanel>
          <DockPanel Margin="0,6,0,0">
            <TextBlock DockPanel.Dock="Left" Text="色調" FontSize="11" Foreground="#888"
                       VerticalAlignment="Center" Width="52" Margin="0,0,4,0"/>
            <WrapPanel x:Name="ColorPanel"/>
          </DockPanel>
        </StackPanel>
      </Border>
    </StackPanel>
    <DockPanel DockPanel.Dock="Bottom" Margin="0,8,0,0" LastChildFill="False">
      <Button x:Name="ResetButton" DockPanel.Dock="Left" Content="既定に戻す" Width="120" Height="32"
              ToolTip="このショートカットのアイコンを既定（ターゲット本来のアイコン）に戻します"/>
      <Button x:Name="CancelButton" DockPanel.Dock="Right" Content="キャンセル" Width="110" Height="32" IsCancel="True"/>
      <Button x:Name="CustomButton" DockPanel.Dock="Right" Content="カスタム..." Width="110" Height="32" Margin="0,0,8,0"/>
      <TextBlock x:Name="StatusText" DockPanel.Dock="Right" VerticalAlignment="Center" Foreground="#777"
                 Margin="0,0,12,0"/>
    </DockPanel>
    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
      <WrapPanel x:Name="IconPanel"/>
    </ScrollViewer>
  </DockPanel>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $headerText    = $window.FindName('HeaderText')
    $searchBox     = $window.FindName('SearchBox')
    $searchPlaceholder = $window.FindName('SearchPlaceholder')
    $stylePanel    = $window.FindName('StylePanel')
    $categoryPanel = $window.FindName('CategoryPanel')
    $colorPanel    = $window.FindName('ColorPanel')
    $clearBtn      = $window.FindName('ClearTagsButton')
    $iconPanel     = $window.FindName('IconPanel')
    $statusText    = $window.FindName('StatusText')
    $customBtn     = $window.FindName('CustomButton')
    $cancelBtn     = $window.FindName('CancelButton')
    $resetBtn      = $window.FindName('ResetButton')

    $headerText.Text = "「$targetName」に設定するアイコンを選んでください。"

    # 選択結果はウィンドウの Tag に格納する（イベント ハンドラからは sender 経由で参照）。
    # 既定に戻す場合は Tag に番兵 '__SIC_RESET__' を入れる。
    $library = @(Get-IconLibrary)
    $maxItems = 500

    # --- タグクラウド（スタイル=カテゴリ / 色調）を母集団から構築 ---
    # 各タグは ToggleButton（チップ）。Tag に正規化タグ値を保持し、
    # 件数が多いタグほどフォントを大きく描く（タグクラウド風）。
    $toneHex = @{
        '赤' = '#E53935'; '橙' = '#FB8C00'; '黄' = '#F9A825'; '緑' = '#43A047'; '青' = '#1E88E5';
        '紫' = '#8E24AA'; '桃' = '#EC407A'; '茶' = '#6D4C41'; '白' = '#BDBDBD'; '灰' = '#9E9E9E'; '黒' = '#424242'
    }
    $brushConv = New-Object System.Windows.Media.BrushConverter

    # 件数を 11〜17pt に線形スケールする
    $scaleFont = {
        param($count, $min, $max)
        if ($max -le $min) { return 13.0 }
        $t = ($count - $min) / [double]($max - $min)
        return [Math]::Round(11.0 + $t * 6.0, 1)
    }

    # スタイル チップ（3D / フラット / ハイコントラスト）— 定義順
    $styleOrder = @(Get-SicStyleOrder)
    $styleGroups = @($library | Where-Object { $_.StyleJa } | Group-Object StyleJa |
        Sort-Object @{ Expression = { [array]::IndexOf($styleOrder, $_.Name) } })
    if ($styleGroups.Count -gt 0) {
        $stMax = ($styleGroups | Measure-Object Count -Maximum).Maximum
        $stMin = ($styleGroups | Measure-Object Count -Minimum).Minimum
        foreach ($g in $styleGroups) {
            $chip = New-Object System.Windows.Controls.Primitives.ToggleButton
            $chip.Content = "{0} ({1})" -f $g.Name, $g.Count
            $chip.Tag = [string]$g.Name
            $chip.FontSize = & $scaleFont $g.Count $stMin $stMax
            $chip.ToolTip = "スタイル: $($g.Name)"
            [void]$stylePanel.Children.Add($chip)
        }
    }

    # ジャンル チップ — 件数の多い順
    $catGroups = @($library | Where-Object { $_.CategoryJa } | Group-Object CategoryJa | Sort-Object Count -Descending)
    if ($catGroups.Count -gt 0) {
        $catMax = ($catGroups | Measure-Object Count -Maximum).Maximum
        $catMin = ($catGroups | Measure-Object Count -Minimum).Minimum
        foreach ($g in $catGroups) {
            $chip = New-Object System.Windows.Controls.Primitives.ToggleButton
            $chip.Content = "{0} ({1})" -f $g.Name, $g.Count
            $chip.Tag = [string]$g.Name
            $chip.FontSize = & $scaleFont $g.Count $catMin $catMax
            $chip.ToolTip = "ジャンル: $($g.Name)"
            [void]$categoryPanel.Children.Add($chip)
        }
    }

    # 色調チップ — 色相順。小さな色見本（丸）を添える
    $toneOrder = @(Get-SicToneOrder)
    $colGroups = @($library | ForEach-Object { $_.Colors } | Where-Object { $_ } | Group-Object |
        Sort-Object @{ Expression = { [array]::IndexOf($toneOrder, $_.Name) } })
    if ($colGroups.Count -gt 0) {
        $colMax = ($colGroups | Measure-Object Count -Maximum).Maximum
        $colMin = ($colGroups | Measure-Object Count -Minimum).Minimum
        foreach ($g in $colGroups) {
            $chip = New-Object System.Windows.Controls.Primitives.ToggleButton
            $chip.Tag = [string]$g.Name
            $chip.FontSize = & $scaleFont $g.Count $colMin $colMax
            $chip.ToolTip = "色調: $($g.Name)"

            $row = New-Object System.Windows.Controls.StackPanel
            $row.Orientation = 'Horizontal'
            $dot = New-Object System.Windows.Shapes.Ellipse
            $dot.Width = 11; $dot.Height = 11; $dot.Margin = '0,0,5,0'
            $dot.Stroke = $brushConv.ConvertFromString('#55000000')
            $dot.StrokeThickness = 0.5
            if ($g.Name -eq '多色') {
                $grad = New-Object System.Windows.Media.LinearGradientBrush
                $grad.StartPoint = New-Object System.Windows.Point(0, 0)
                $grad.EndPoint = New-Object System.Windows.Point(1, 1)
                $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromRgb(0xE5, 0x39, 0x35), 0.0)))
                $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromRgb(0x43, 0xA0, 0x47), 0.5)))
                $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromRgb(0x1E, 0x88, 0xE5), 1.0)))
                $dot.Fill = $grad
            }
            elseif ($toneHex.ContainsKey($g.Name)) {
                $dot.Fill = $brushConv.ConvertFromString($toneHex[$g.Name])
            }
            else {
                $dot.Fill = $brushConv.ConvertFromString('#9E9E9E')
            }
            $txt = New-Object System.Windows.Controls.TextBlock
            $txt.Text = "{0} ({1})" -f $g.Name, $g.Count
            $txt.VerticalAlignment = 'Center'
            [void]$row.Children.Add($dot)
            [void]$row.Children.Add($txt)
            $chip.Content = $row
            [void]$colorPanel.Children.Add($chip)
        }
    }

    $buildItems = {
        $nameFilter = $searchBox.Text.Trim()
        # 検索ボックスのプレースホルダ（注釈）は未入力のときだけ表示する
        if ($searchBox.Text.Length -gt 0) {
            $searchPlaceholder.Visibility = [System.Windows.Visibility]::Collapsed
        } else {
            $searchPlaceholder.Visibility = [System.Windows.Visibility]::Visible
        }
        # ON になっているチップ（タグ）を facet ごとに集める
        $enabledStyles = @()
        foreach ($c in $stylePanel.Children) { if ($c.IsChecked) { $enabledStyles += [string]$c.Tag } }
        $enabledCats = @()
        foreach ($c in $categoryPanel.Children) { if ($c.IsChecked) { $enabledCats += [string]$c.Tag } }
        $enabledCols = @()
        foreach ($c in $colorPanel.Children) { if ($c.IsChecked) { $enabledCols += [string]$c.Tag } }

        $iconPanel.Children.Clear()
        $items = $library
        if ($nameFilter) {
            $items = $items | Where-Object {
                ($_.Name -like "*$nameFilter*") -or
                ($_.CategoryJa -and $_.CategoryJa -like "*$nameFilter*") -or
                ($_.StyleJa -and $_.StyleJa -like "*$nameFilter*") -or
                ($_.Keywords -and ((@($_.Keywords) -join ' ') -like "*$nameFilter*"))
            }
        }
        # facet 内は OR、facet をまたぐと AND
        if ($enabledStyles.Count -gt 0) {
            # スタイル未設定（ユーザー追加の .ico/.png）は常に通す
            $items = $items | Where-Object { (-not $_.StyleJa) -or ($enabledStyles -contains $_.StyleJa) }
        }
        if ($enabledCats.Count -gt 0) {
            $items = $items | Where-Object { $enabledCats -contains $_.CategoryJa }
        }
        if ($enabledCols.Count -gt 0) {
            $items = $items | Where-Object { @($_.Colors | Where-Object { $enabledCols -contains $_ }).Count -gt 0 }
        }
        $items = @($items)
        $shown = $items
        if ($shown.Count -gt $maxItems) { $shown = $shown[0..($maxItems - 1)] }

        if ($items.Count -eq 0) {
            $tb = New-Object System.Windows.Controls.TextBlock
            if ($library.Count -eq 0) {
                $tb.Text = "ライブラリが空です。tools\Fetch-FluentEmoji.ps1 で取得するか、「カスタム...」で任意の .ico/.png を指定してください。"
            } else {
                $tb.Text = "該当するアイコンがありません。条件を変えてお試しください。"
            }
            $tb.Foreground = 'Gray'; $tb.Margin = '6'; $tb.TextWrapping = 'Wrap'; $tb.Width = 720
            [void]$iconPanel.Children.Add($tb)
        }

        foreach ($icon in $shown) {
            $btn = New-Object System.Windows.Controls.Button
            $btn.Width = 92; $btn.Height = 104; $btn.Margin = '4'
            $btn.Background = 'White'; $btn.BorderBrush = '#DDD'
            $tip = $icon.Name
            $tipMeta = @()
            if ($icon.CategoryJa) { $tipMeta += [string]$icon.CategoryJa }
            if ($icon.StyleJa)    { $tipMeta += [string]$icon.StyleJa }
            if ($tipMeta.Count -gt 0) { $tip += "`n[" + ($tipMeta -join '・') + "]" }
            if (@($icon.Colors).Count -gt 0) { $tip += ' ' + (@($icon.Colors) -join '/') }
            $btn.ToolTip = $tip
            $btn.Tag = $icon.Path
            $btn.Cursor = [System.Windows.Input.Cursors]::Hand

            $sp = New-Object System.Windows.Controls.StackPanel
            $img = New-Object System.Windows.Controls.Image
            $img.Width = 48; $img.Height = 48; $img.Margin = '0,6,0,4'
            try {
                $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                $bmp.BeginInit()
                $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bmp.DecodePixelWidth = 48
                $bmp.UriSource = New-Object System.Uri($icon.Path)
                $bmp.EndInit()
                $img.Source = $bmp
            } catch { }

            $label = New-Object System.Windows.Controls.TextBlock
            $label.Text = $icon.Name
            $label.FontSize = 10; $label.TextAlignment = 'Center'
            $label.TextTrimming = 'CharacterEllipsis'; $label.MaxWidth = 84
            $label.Foreground = '#444'

            [void]$sp.Children.Add($img)
            [void]$sp.Children.Add($label)
            $btn.Content = $sp

            # このハンドラは子スコープ ($buildItems) 内で生成されるため、親スコープの
            # 変数は .GetNewClosure() では捕捉できず、WPF のイベント実行時に失われる。
            # sender からウィンドウを辿り、結果は Window.Tag に格納して閉じる。
            $btn.Add_Click({
                param($s, $e)
                $win = [System.Windows.Window]::GetWindow($s)
                $win.Tag = $s.Tag
                $win.Close()
            })

            [void]$iconPanel.Children.Add($btn)
        }

        $statusText.Text = "{0} 件" -f $items.Count
        if ($items.Count -gt $shown.Count) {
            $statusText.Text = "{0} 件中 {1} 件を表示（絞り込んでください）" -f $items.Count, $shown.Count
        }
    }.GetNewClosure()

    $searchBox.Add_TextChanged({ & $buildItems }.GetNewClosure())

    # 各タグ チップの Click で再描画。ハンドラは関数スコープで生成し $buildItems を捕捉する。
    $rebuild = { & $buildItems }.GetNewClosure()
    foreach ($c in $stylePanel.Children) { $c.Add_Click($rebuild) }
    foreach ($c in $categoryPanel.Children) { $c.Add_Click($rebuild) }
    foreach ($c in $colorPanel.Children) { $c.Add_Click($rebuild) }

    # タグをクリア: 全チップを解除して再描画
    $clearBtn.Add_Click({
        param($s, $e)
        foreach ($c in $stylePanel.Children) { $c.IsChecked = $false }
        foreach ($c in $categoryPanel.Children) { $c.IsChecked = $false }
        foreach ($c in $colorPanel.Children) { $c.IsChecked = $false }
        & $buildItems
    }.GetNewClosure())

    $customBtn.Add_Click({
        param($s, $e)
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "アイコン画像 (*.ico;*.png;*.exe;*.dll)|*.ico;*.png;*.exe;*.dll|すべてのファイル (*.*)|*.*"
        $dlg.Title = "アイコンファイルを選択"
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $win = [System.Windows.Window]::GetWindow($s)
            $win.Tag = $dlg.FileName
            $win.Close()
        }
    })

    # 既定（ターゲット本来）のアイコンに戻す。番兵を Tag に入れて閉じ、呼び出し側で解釈する。
    $resetBtn.Add_Click({
        param($s, $e)
        $win = [System.Windows.Window]::GetWindow($s)
        $win.Tag = '__SIC_RESET__'
        $win.Close()
    })

    $cancelBtn.Add_Click({
        param($s, $e)
        [System.Windows.Window]::GetWindow($s).Close()
    })

    & $buildItems

    return $window
}

function Show-SicIconPicker {
    <#
    .SYNOPSIS
        アイコンピッカーを表示し、選択されたアイコンファイルのパスを返す（キャンセル時 $null）。
    .DESCRIPTION
        「既定に戻す」が選ばれた場合は番兵文字列 '__SIC_RESET__' を返す。
        呼び出し側はこれを Reset-ShortcutIcon に対応付けること。
    .PARAMETER LnkPath
        対象の .lnk（タイトル表示用）。
    .PARAMETER NoShow
        ウィンドウを表示せず構築のみ行う（自動テスト用）。$null を返す。
    #>
    [CmdletBinding()]
    param(
        [string] $LnkPath,
        [switch] $NoShow
    )

    $window = New-SicIconPickerWindow -LnkPath $LnkPath
    if ($NoShow) { return $null }

    [void]$window.ShowDialog()
    return $window.Tag
}
