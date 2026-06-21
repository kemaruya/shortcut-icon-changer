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
        Title="アイコンを変更" Height="560" Width="820"
        WindowStartupLocation="CenterScreen" Background="#FAFAFA">
  <DockPanel Margin="10">
    <StackPanel DockPanel.Dock="Top" Margin="0,0,0,8">
      <TextBlock x:Name="HeaderText" FontSize="13" Foreground="#333" Margin="2,0,0,6"/>
      <DockPanel>
        <ComboBox x:Name="CategoryCombo" DockPanel.Dock="Right" Width="160" Height="28"
                  Margin="6,0,0,0" VerticalContentAlignment="Center"
                  ToolTip="カテゴリで絞り込み"/>
        <ComboBox x:Name="ColorCombo" DockPanel.Dock="Right" Width="120" Height="28"
                  Margin="6,0,0,0" VerticalContentAlignment="Center"
                  ToolTip="色調で絞り込み"/>
        <TextBox x:Name="SearchBox" Height="28" VerticalContentAlignment="Center"
                 FontSize="13" Padding="6,0,0,0"
                 ToolTip="名前・キーワードで絞り込み（例: rocket, folder, star）"/>
      </DockPanel>
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
    $categoryCombo = $window.FindName('CategoryCombo')
    $colorCombo    = $window.FindName('ColorCombo')
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

    # --- カテゴリ / 色調 コンボボックスを母集団から構築 ---
    $allCatLabel = 'すべて（カテゴリ）'
    $allColLabel = 'すべて（色）'
    [void]$categoryCombo.Items.Add($allCatLabel)
    foreach ($c in @($library | ForEach-Object { $_.CategoryJa } | Where-Object { $_ } | Sort-Object -Unique)) {
        [void]$categoryCombo.Items.Add($c)
    }
    $categoryCombo.SelectedIndex = 0

    $toneOrder = @(Get-SicToneOrder)
    $colorsPresent = @($library | ForEach-Object { $_.Colors } | Where-Object { $_ } | Sort-Object -Unique)
    [void]$colorCombo.Items.Add($allColLabel)
    foreach ($c in @($toneOrder | Where-Object { $colorsPresent -contains $_ })) {
        [void]$colorCombo.Items.Add($c)
    }
    $colorCombo.SelectedIndex = 0

    $buildItems = {
        $nameFilter = $searchBox.Text.Trim()
        $catSel = if ($categoryCombo.SelectedIndex -gt 0) { [string]$categoryCombo.SelectedItem } else { $null }
        $colSel = if ($colorCombo.SelectedIndex -gt 0) { [string]$colorCombo.SelectedItem } else { $null }

        $iconPanel.Children.Clear()
        $items = $library
        if ($nameFilter) {
            $items = $items | Where-Object {
                ($_.Name -like "*$nameFilter*") -or
                ($_.CategoryJa -and $_.CategoryJa -like "*$nameFilter*") -or
                ($_.Keywords -and ((@($_.Keywords) -join ' ') -like "*$nameFilter*"))
            }
        }
        if ($catSel) { $items = $items | Where-Object { $_.CategoryJa -eq $catSel } }
        if ($colSel) { $items = $items | Where-Object { @($_.Colors) -contains $colSel } }
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
            if ($icon.CategoryJa) { $tip += "`n[" + $icon.CategoryJa + "]" }
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
    $categoryCombo.Add_SelectionChanged({ & $buildItems }.GetNewClosure())
    $colorCombo.Add_SelectionChanged({ & $buildItems }.GetNewClosure())

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
