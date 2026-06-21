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

function Show-SicIconPicker {
    <#
    .SYNOPSIS
        アイコンピッカーを表示し、選択されたアイコンファイルのパスを返す（キャンセル時 $null）。
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

    $targetName = if ($LnkPath) { [System.IO.Path]::GetFileName($LnkPath) } else { '(ショートカット)' }

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="アイコンを変更" Height="540" Width="760"
        WindowStartupLocation="CenterScreen" Background="#FAFAFA">
  <DockPanel Margin="10">
    <StackPanel DockPanel.Dock="Top" Margin="0,0,0,8">
      <TextBlock x:Name="HeaderText" FontSize="13" Foreground="#333" Margin="2,0,0,6"/>
      <TextBox x:Name="SearchBox" Height="28" VerticalContentAlignment="Center"
               FontSize="13" Padding="6,0,0,0"
               ToolTip="名前で絞り込み（例: rocket, folder, star）"/>
    </StackPanel>
    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal"
                HorizontalAlignment="Right" Margin="0,8,0,0">
      <TextBlock x:Name="StatusText" VerticalAlignment="Center" Foreground="#777"
                 Margin="0,0,12,0"/>
      <Button x:Name="CustomButton" Content="カスタム..." Width="110" Height="32" Margin="0,0,8,0"/>
      <Button x:Name="CancelButton" Content="キャンセル" Width="110" Height="32" IsCancel="True"/>
    </StackPanel>
    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
      <WrapPanel x:Name="IconPanel"/>
    </ScrollViewer>
  </DockPanel>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $headerText  = $window.FindName('HeaderText')
    $searchBox   = $window.FindName('SearchBox')
    $iconPanel   = $window.FindName('IconPanel')
    $statusText  = $window.FindName('StatusText')
    $customBtn   = $window.FindName('CustomButton')
    $cancelBtn   = $window.FindName('CancelButton')

    $headerText.Text = "「$targetName」に設定するアイコンを選んでください。"

    # 選択結果を保持
    $state = [pscustomobject]@{ Selected = $null }

    $library = @(Get-IconLibrary)
    $maxItems = 300

    $buildItems = {
        param($filter)
        $iconPanel.Children.Clear()
        $items = $library
        if ($filter) {
            $items = $library | Where-Object { $_.Name -like "*$filter*" }
        }
        $items = @($items)
        $shown = $items
        if ($shown.Count -gt $maxItems) { $shown = $shown[0..($maxItems - 1)] }

        if ($items.Count -eq 0) {
            $tb = New-Object System.Windows.Controls.TextBlock
            if ($library.Count -eq 0) {
                $tb.Text = "ライブラリが空です。tools\Fetch-FluentEmoji.ps1 で取得するか、「カスタム...」で任意の .ico/.png を指定してください。"
            } else {
                $tb.Text = "該当するアイコンがありません。"
            }
            $tb.Foreground = 'Gray'; $tb.Margin = '6'; $tb.TextWrapping = 'Wrap'; $tb.Width = 680
            [void]$iconPanel.Children.Add($tb)
        }

        foreach ($icon in $shown) {
            $btn = New-Object System.Windows.Controls.Button
            $btn.Width = 92; $btn.Height = 104; $btn.Margin = '4'
            $btn.Background = 'White'; $btn.BorderBrush = '#DDD'
            $btn.ToolTip = $icon.Name
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

            $btn.Add_Click({
                param($s, $e)
                $state.Selected = $s.Tag
                $window.DialogResult = $true
                $window.Close()
            }.GetNewClosure())

            [void]$iconPanel.Children.Add($btn)
        }

        $statusText.Text = "{0} 件" -f $items.Count
        if ($items.Count -gt $shown.Count) {
            $statusText.Text = "{0} 件中 {1} 件を表示（絞り込んでください）" -f $items.Count, $shown.Count
        }
    }

    $searchBox.Add_TextChanged({ & $buildItems $searchBox.Text.Trim() }.GetNewClosure())

    $customBtn.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "アイコン画像 (*.ico;*.png;*.exe;*.dll)|*.ico;*.png;*.exe;*.dll|すべてのファイル (*.*)|*.*"
        $dlg.Title = "アイコンファイルを選択"
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $state.Selected = $dlg.FileName
            $window.DialogResult = $true
            $window.Close()
        }
    }.GetNewClosure())

    $cancelBtn.Add_Click({ $window.DialogResult = $false; $window.Close() }.GetNewClosure())

    & $buildItems ''

    if ($NoShow) {
        # 自動テスト用: 構築のみ確認して閉じずに $null を返す
        return $null
    }

    [void]$window.ShowDialog()
    return $state.Selected
}
