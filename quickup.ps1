<#
.SYNOPSIS
    QuickUp - upload any file to a temporary/permanent host straight from the
    Windows right-click menu.

.DESCRIPTION
    A single self-contained script that installs a cascading "QuickUp" entry
    into the file context menu (per-user, no admin required). Picking a host
    starts the upload immediately and shows a dialog with the resulting URL,
    already copied to the clipboard.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File quickup.ps1 install
    powershell -ExecutionPolicy Bypass -File quickup.ps1 uninstall
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'uninstall', 'update', 'upload', 'about', 'selftest')]
    [string]$Command = 'install',

    [Parameter(Position = 1)]
    [string]$Service,

    [Parameter(Position = 2)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

# Display name shown in the submenu and the result dialog, in menu order.
$script:Services = [ordered]@{
    'catbox'    = 'Catbox (permanent)'
    'x0'        = 'x0.at (up to 100 days)'
    'litterbox' = 'Litterbox (1 hour)'
    'uguu'      = 'Uguu (3 hours)'
}

# What each host actually accepts (from their docs/config): size cap in bytes
# and blocked extensions. Used by the About dialog and to refuse an unsupported
# file before uploading. Litterbox shares Catbox's ban list (same operator).
$script:Limits = [ordered]@{
    catbox    = @{ Max = 200MB;  Banned = @('exe', 'scr', 'cpl', 'doc', 'docx', 'docm', 'jar')
                   Accept = 'Permanent  |  max 200 MB  |  blocked: .exe .scr .cpl .doc .docx .jar' }
    x0        = @{ Max = 1024MB; Banned = @('exe', 'dll', 'com', 'scr', 'jar', 'class')
                   Accept = 'Kept 3-100 days (smaller lasts longer)  |  max 1 GB  |  blocked: executables (.exe .dll .jar .class)' }
    litterbox = @{ Max = 1024MB; Banned = @('exe', 'scr', 'cpl', 'doc', 'docx', 'docm', 'jar')
                   Accept = 'Temporary 1 hour  |  max 1 GB  |  blocked: .exe .scr .cpl .doc .docx .jar' }
    uguu      = @{ Max = 128MB;  Banned = @('exe', 'scr', 'com', 'vbs', 'bat', 'cmd', 'htm', 'html', 'jar', 'msi', 'apk', 'phtml', 'svg')
                   Accept = 'Temporary 3 hours  |  max 128 MB  |  blocked: executables, scripts, .html, .svg, .jar, .apk' }
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:0.#} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:0} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:0} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

# $null when $Service accepts $Path, otherwise a human reason why it doesn't.
function Test-Supported {
    param([string]$Service, [string]$Path)
    $lim = $script:Limits[$Service]
    if (-not $lim) { return $null }
    $ext = ([System.IO.Path]::GetExtension($Path)).TrimStart('.').ToLowerInvariant()
    if ($lim.Banned -contains $ext) { return "$($script:Services[$Service]) does not accept .$ext files." }
    $size = (Get-Item -LiteralPath $Path).Length
    if ($size -gt $lim.Max) {
        return ('File is {0}; {1} accepts up to {2}.' -f (Format-Size $size), $script:Services[$Service], (Format-Size $lim.Max))
    }
    return $null
}

function Get-SupportingServices {
    param([string]$Path)
    $script:Services.Keys |
        Where-Object { -not (Test-Supported -Service $_ -Path $Path) } |
        ForEach-Object { $script:Services[$_] }
}

$script:UserAgent = 'QuickUp/1.0 (+https://github.com/Riyoway/quickup)'
$script:RegPath = 'Software\Classes\*\shell\QuickUp'
$script:RepoRaw = 'https://raw.githubusercontent.com/Riyoway/quickup/main'
$script:InstallerUrl = "$script:RepoRaw/quickup.ps1"

# ASCII-only banner so it renders in any console code page (install.cmd).
function Write-Banner {
    param([string]$Title)
    $rule = '=' * 60
    Write-Host ''
    Write-Host $rule -ForegroundColor DarkCyan
    Write-Host "    QuickUp  -  $Title" -ForegroundColor Cyan
    Write-Host $rule -ForegroundColor DarkCyan
    Write-Host ''
}

function Write-Field {
    param([string]$Label, [string]$Value, [string]$Color = 'Gray')
    Write-Host ("  {0,-8}" -f $Label) -ForegroundColor DarkGray -NoNewline
    Write-Host $Value -ForegroundColor $Color
}

# The Windows clipboard is a shared, briefly-lockable resource; a single
# SetText throws "Requested Clipboard operation did not succeed" whenever
# another app holds it. SetDataObject retries, and we never let a copy failure
# look like an upload failure.
function Copy-Text {
    param([string]$Text)
    # SetDataObject retries the OpenClipboard call (10 x 200ms) to ride out a
    # lock; Set-Clipboard is a separate code path that sometimes wins when it
    # doesn't. Either succeeding is enough.
    try { [System.Windows.Forms.Clipboard]::SetDataObject($Text, $true, 10, 200); return $true } catch { }
    try { Set-Clipboard -Value $Text; return $true } catch { }
    return $false
}

# --- modern UI (WPF, all built into Windows - no extra dependencies) --------

function Initialize-Wpf {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms
}

# Colours follow the user's Windows light/dark setting; accent matches the icon.
function Get-Theme {
    $dark = $false
    try {
        $dark = ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
                    -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme -eq 0)
    } catch { }
    if ($dark) {
        @{ Card = '#FF2B2B2B'; Text = '#FFF4F4F4'; Sub = '#FFA6A6A6'; Field = '#FF383838'
           Accent = '#FF2F80ED'; AccentHover = '#FF4C93F0'; OnAccent = '#FFFFFFFF'; SecBorder = '#FF4A4A4A' }
    } else {
        @{ Card = '#FFFFFFFF'; Text = '#FF1B1B1B'; Sub = '#FF6A6A6A'; Field = '#FFF2F3F5'
           Accent = '#FF2F80ED'; AccentHover = '#FF1F6FD8'; OnAccent = '#FFFFFFFF'; SecBorder = '#FFDADEE3' }
    }
}

# Builds a borderless, rounded, shadowed card window around $Inner with themed
# Primary/Secondary/Ghost button styles. Returns the loaded Window.
function New-CardWindow {
    param([int]$Width, [string]$Inner, [hashtable]$T)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize"
        Width="$Width" SizeToContent="Height" MinHeight="80" FontFamily="Segoe UI" TextOptions.TextFormattingMode="Ideal"
        WindowStartupLocation="CenterScreen" Topmost="True" ShowInTaskbar="False">
  <Window.Resources>
    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Foreground" Value="$($T.OnAccent)"/><Setter Property="Background" Value="$($T.Accent)"/>
      <Setter Property="Height" Value="34"/><Setter Property="Padding" Value="18,0"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" CornerRadius="7" Background="{TemplateBinding Background}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="$($T.AccentHover)"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.45"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Secondary" TargetType="Button">
      <Setter Property="Foreground" Value="$($T.Text)"/><Setter Property="Background" Value="Transparent"/>
      <Setter Property="Height" Value="34"/><Setter Property="Padding" Value="18,0"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" CornerRadius="7" Background="{TemplateBinding Background}" BorderBrush="$($T.SecBorder)" BorderThickness="1"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="$($T.Field)"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.45"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Ghost" TargetType="Button">
      <Setter Property="Foreground" Value="$($T.Sub)"/><Setter Property="Background" Value="Transparent"/>
      <Setter Property="Width" Value="30"/><Setter Property="Height" Value="30"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/><Setter Property="FontSize" Value="11"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" CornerRadius="6" Background="{TemplateBinding Background}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="$($T.Field)"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="12" Background="$($T.Card)" Margin="14">
    <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="0" Opacity="0.28"/></Border.Effect>
    $Inner
  </Border>
</Window>
"@
    [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new([xml]$xaml))
}

# A simple themed card with a title, wrapped body text and an OK button.
function Show-Message {
    param([string]$Title, [string]$Body)
    Initialize-Wpf
    $T = Get-Theme
    $inner = @"
<Grid Margin="22">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <Grid x:Name="Header" Grid.Row="0" Background="Transparent">
    <TextBlock Text="$([System.Security.SecurityElement]::Escape($Title))" FontWeight="SemiBold" FontSize="15" Foreground="$($T.Text)" VerticalAlignment="Center"/>
    <Button x:Name="Close" Style="{StaticResource Ghost}" Content="&#xE10A;" HorizontalAlignment="Right"/>
  </Grid>
  <TextBlock x:Name="Body" Grid.Row="1" TextWrapping="Wrap" FontSize="13" Foreground="$($T.Sub)" Margin="0,12,0,0" VerticalAlignment="Top"/>
  <Button x:Name="Ok" Grid.Row="2" Style="{StaticResource Primary}" Content="OK" HorizontalAlignment="Right" MinWidth="88" Margin="0,14,0,0"/>
</Grid>
"@
    $win = New-CardWindow -Width 460 -Inner $inner -T $T
    $win.FindName('Body').Text = $Body
    $win.FindName('Header').Add_MouseLeftButtonDown({ $win.DragMove() }.GetNewClosure())
    $win.FindName('Close').Add_Click({ $win.Close() }.GetNewClosure())
    $win.FindName('Ok').Add_Click({ $win.Close() }.GetNewClosure())
    [void]$win.ShowDialog()
}

# Endpoint definitions. Every one of these hosts returns the plain-text URL
# as the whole response body, so completion handling is uniform.
function Get-ServiceRequest {
    param([Parameter(Mandatory)][string]$Service)
    switch ($Service) {
        'catbox' {
            @{ Uri = 'https://catbox.moe/user/api.php'
               Fields = @{ reqtype = 'fileupload' }; FileField = 'fileToUpload' }
        }
        'litterbox' {
            @{ Uri = 'https://litterbox.catbox.moe/resources/internals/api.php'
               Fields = @{ reqtype = 'fileupload'; time = '1h' }; FileField = 'fileToUpload' }
        }
        'x0' {
            @{ Uri = 'https://x0.at'; Fields = @{}; FileField = 'file' }
        }
        'uguu' {
            @{ Uri = 'https://uguu.se/upload?output=text'; Fields = @{}; FileField = 'files[]' }
        }
        default { throw "Unknown service '$Service'." }
    }
}

# Copy asset $Rel (e.g. 'quickup.ico' or 'services/catbox.ico') to $Dest from
# the repo checkout, or fetch it from GitHub for one-line remote installs.
# Returns $true when $Dest ends up present.
function Get-Asset {
    param([string]$Rel, [string]$Dest)
    if ($PSCommandPath) {
        $src = Join-Path (Split-Path -Parent $PSCommandPath) ('assets\' + ($Rel -replace '/', '\'))
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $Dest -Force; return $true }
    }
    if (Test-Path -LiteralPath $Dest) { return $true }
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -OutFile $Dest -Uri "$script:RepoRaw/assets/$Rel"
    } catch { }
    return (Test-Path -LiteralPath $Dest)
}

function New-MenuItem {
    param([string]$Key, [string]$Label, [string]$Command, [string]$Icon, [int]$Flags = 0)
    $base = "$script:RegPath\shell\$Key"
    $verb = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($base)
    $verb.SetValue('', $Label)
    if ($Icon)  { $verb.SetValue('Icon', $Icon) }
    if ($Flags) { $verb.SetValue('CommandFlags', $Flags, [Microsoft.Win32.RegistryValueKind]::DWord) }
    $verb.Close()
    $cmd = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$base\command")
    $cmd.SetValue('', $Command)
    $cmd.Close()
}

function Install-QuickUp {
    $installDir = Join-Path $env:LOCALAPPDATA 'QuickUp'
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    $target = Join-Path $installDir 'quickup.ps1'
    if ($PSCommandPath -and ($PSCommandPath -ne $target)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $target -Force
    } elseif (-not $PSCommandPath) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $script:InstallerUrl -OutFile $target
    }

    # Parent-menu icon (app icon).
    $icon = Join-Path $installDir 'quickup.ico'
    [void](Get-Asset 'quickup.ico' $icon)

    # Per-service favicons; a host without one (e.g. x0.at) uses the app icon.
    $iconDir = Join-Path $installDir 'icons'
    New-Item -ItemType Directory -Force -Path $iconDir | Out-Null
    $svcIcon = @{}
    foreach ($svc in $script:Services.Keys) {
        $dest = Join-Path $iconDir "$svc.ico"
        if (Get-Asset "services/$svc.ico" $dest) { $svcIcon[$svc] = $dest }
        elseif (Test-Path -LiteralPath $icon) { $svcIcon[$svc] = $icon }
    }

    # Always launch through Windows PowerShell so the menu works even if the
    # user installed from pwsh 7.
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $hidden  = "`"$ps`" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`""
    $visible = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$target`""

    # The '*' key is a wildcard in the PS registry provider, so drive it
    # through the .NET API which treats the path literally.
    [void][Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($script:RegPath, $false)
    $root = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:RegPath)
    $root.SetValue('MUIVerb', 'QuickUp')
    if (Test-Path -LiteralPath $icon) { $root.SetValue('Icon', $icon) }
    $root.SetValue('SubCommands', '')  # empty + nested 'shell' key => cascade
    $root.Close()

    # Items sort alphabetically by key name, so number them to fix the order
    # and keep the management entries last.
    $order = 10
    foreach ($svc in $script:Services.Keys) {
        New-MenuItem ('{0:D2}_{1}' -f $order, $svc) $script:Services[$svc] "$hidden upload $svc `"%1`"" $svcIcon[$svc]
        $order += 10
    }
    # 0x20 = ECF_SEPARATORBEFORE: a line splitting the hosts from the info /
    # management items. About opens a dialog (hidden launcher); Update and
    # Uninstall print to a visible console.
    New-MenuItem '70_about'     'About QuickUp'     "$hidden about"      $icon 0x20
    New-MenuItem '80_update'    'Update QuickUp'    "$visible update"    $icon
    New-MenuItem '90_uninstall' 'Uninstall QuickUp' "$visible uninstall" $icon

    Write-Banner 'INSTALLED'
    Write-Host '  [ OK ] ' -ForegroundColor Green -NoNewline
    Write-Host 'Added to the right-click menu.'
    Write-Host ''
    Write-Field 'Use'   'Right-click a file  ->  QuickUp  ->  pick a host'
    Write-Field 'Hosts' ($script:Services.Values -join '  |  ')
    Write-Field 'Menu'  'About / Update / Uninstall are in the submenu too'
    Write-Field 'Script' $target
    Write-Host ''
    Write-Host '  Uninstall anytime:' -ForegroundColor DarkGray
    Write-Host "     powershell -ExecutionPolicy Bypass -File `"$target`" uninstall" -ForegroundColor Yellow
    Write-Host ('=' * 60) -ForegroundColor DarkCyan
    Write-Host ''
}

function Update-QuickUp {
    $tmp = Join-Path $env:TEMP 'quickup-latest.ps1'
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Write-Host 'Fetching the latest QuickUp ...' -ForegroundColor DarkCyan
    Invoke-WebRequest -UseBasicParsing -Uri $script:InstallerUrl -OutFile $tmp
    # Re-run install from the fresh copy: refreshes the script, icon and menu.
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
        -NoProfile -ExecutionPolicy Bypass -File $tmp install
}

function Uninstall-QuickUp {
    [void][Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($script:RegPath, $false)
    $dir = Join-Path $env:LOCALAPPDATA 'QuickUp'
    Write-Banner 'REMOVED'
    Write-Host '  [ OK ] ' -ForegroundColor Green -NoNewline
    Write-Host 'Right-click menu entry deleted.'
    Write-Host ''
    Write-Field 'Note' 'The installed script still lives at:'
    Write-Host ("           $dir") -ForegroundColor Gray
    Write-Host '           Delete that folder to remove QuickUp completely.' -ForegroundColor DarkGray
    Write-Host ('=' * 60) -ForegroundColor DarkCyan
    Write-Host ''
}

# Builds a fresh request and (re)starts the upload for the window described by
# $ctx, resetting it to the in-progress state. Called on open and on Retry.
function Start-QuickUpload {
    param([hashtable]$ctx)
    foreach ($d in @($ctx.Stream, $ctx.Content, $ctx.Client)) { if ($d) { try { $d.Dispose() } catch { } } }
    $ctx.Url = $null
    $ctx.Status.Text = "Uploading `"$($ctx.FileName)`" to $($ctx.DisplayName)"
    $ctx.Bar.Value = 0; $ctx.Bar.Visibility = 'Visible'
    $ctx.UrlBox.Text = ''; $ctx.UrlBox.Foreground = $ctx.TextBrush; $ctx.UrlWrap.Visibility = 'Collapsed'
    $ctx.Retry.Visibility = 'Collapsed'
    $ctx.Copy.Visibility = 'Visible'; $ctx.Open.Visibility = 'Visible'
    $ctx.Copy.IsEnabled = $false; $ctx.Open.IsEnabled = $false; $ctx.Copy.Content = 'Copy'
    try {
        $client = [System.Net.Http.HttpClient]::new()
        $client.Timeout = [TimeSpan]::FromHours(1)
        $client.DefaultRequestHeaders.Add('User-Agent', $script:UserAgent)
        $content = [System.Net.Http.MultipartFormDataContent]::new()
        foreach ($k in $ctx.Req.Fields.Keys) {
            $content.Add([System.Net.Http.StringContent]::new([string]$ctx.Req.Fields[$k]), $k)
        }
        $stream = [QuickUp.ProgressStream]::new([System.IO.File]::OpenRead($ctx.Path))
        $fc = [System.Net.Http.StreamContent]::new($stream)
        $fc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
        $content.Add($fc, $ctx.Req.FileField, $ctx.FileName)
        $ctx.Client = $client; $ctx.Content = $content; $ctx.Stream = $stream
        $ctx.Task = $client.PostAsync($ctx.Req.Uri, $content)
        $ctx.Timer.Start()
    }
    catch { Set-UploadError $ctx $_.Exception.Message }
}

# Puts the window into the failed state, showing the Retry button.
function Set-UploadError {
    param([hashtable]$ctx, [string]$Message)
    $ctx.Status.Text = 'Upload failed'
    $ctx.Bar.Visibility = 'Collapsed'
    $ctx.UrlBox.Foreground = [System.Windows.Media.Brushes]::IndianRed
    $ctx.UrlBox.Text = $Message; $ctx.UrlWrap.Visibility = 'Visible'
    $ctx.Copy.Visibility = 'Collapsed'; $ctx.Open.Visibility = 'Collapsed'
    $ctx.Retry.Visibility = 'Visible'
}

function Invoke-UploadUI {
    param(
        [Parameter(Mandatory)][string]$Service,
        [Parameter(Mandatory)][string]$Path
    )

    if (-not $script:Services.Contains($Service)) { throw "Unknown service '$Service'." }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: $Path" }

    Initialize-Wpf

    # Refuse a file this host can't take, and point at the ones that can.
    $reason = Test-Supported -Service $Service -Path $Path
    if ($reason) {
        $ok = @(Get-SupportingServices -Path $Path)
        $suggest = if ($ok.Count) { "This file works with:`r`n  - " + ($ok -join "`r`n  - ") }
                   else { 'None of the configured hosts accept this file.' }
        Show-Message -Title 'File not supported' -Body "$reason`r`n`r`n$suggest"
        return
    }

    Add-Type -AssemblyName System.Net.Http
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    # Counts bytes as HttpClient reads the file to send it, so the dialog can
    # show real upload progress instead of an indeterminate spinner.
    if (-not ('QuickUp.ProgressStream' -as [type])) {
        Add-Type -TypeDefinition @'
namespace QuickUp {
    public class ProgressStream : System.IO.Stream {
        private System.IO.Stream _s;
        public long Sent;
        public ProgressStream(System.IO.Stream s) { _s = s; }
        public override bool CanRead { get { return _s.CanRead; } }
        public override bool CanSeek { get { return _s.CanSeek; } }
        public override bool CanWrite { get { return false; } }
        public override long Length { get { return _s.Length; } }
        public override long Position { get { return _s.Position; } set { _s.Position = value; } }
        public override void Flush() { _s.Flush(); }
        public override int Read(byte[] b, int o, int c) { int n = _s.Read(b, o, c); Sent += n; return n; }
        public override long Seek(long o, System.IO.SeekOrigin r) { return _s.Seek(o, r); }
        public override void SetLength(long v) { _s.SetLength(v); }
        public override void Write(byte[] b, int o, int c) { throw new System.NotSupportedException(); }
        protected override void Dispose(bool d) { if (d && _s != null) { _s.Dispose(); } base.Dispose(d); }
    }
}
'@
    }

    $displayName = $script:Services[$Service]
    $fileName = [System.IO.Path]::GetFileName($Path)
    $req = Get-ServiceRequest -Service $Service
    $total = (Get-Item -LiteralPath $Path).Length
    $T = Get-Theme
    $inner = @"
<Grid Margin="22">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <Grid x:Name="Header" Grid.Row="0" Background="Transparent">
    <StackPanel Orientation="Horizontal">
      <Image x:Name="Fav" Width="18" Height="18" Margin="0,0,9,0" VerticalAlignment="Center"/>
      <TextBlock Text="QuickUp" FontWeight="SemiBold" FontSize="14" Foreground="$($T.Text)" VerticalAlignment="Center"/>
    </StackPanel>
    <Button x:Name="Close" Style="{StaticResource Ghost}" Content="&#xE10A;" HorizontalAlignment="Right"/>
  </Grid>
  <StackPanel Grid.Row="1" VerticalAlignment="Center" Margin="0,16">
    <TextBlock x:Name="Status" FontSize="13" Foreground="$($T.Text)" TextTrimming="CharacterEllipsis" Margin="0,0,0,12"/>
    <ProgressBar x:Name="Bar" Height="6" Minimum="0" Maximum="100" Foreground="$($T.Accent)" Background="$($T.Field)" BorderThickness="0"/>
    <Border x:Name="UrlWrap" CornerRadius="7" Background="$($T.Field)" Padding="12,9" Margin="0,2,0,0" Visibility="Collapsed">
      <TextBox x:Name="Url" IsReadOnly="True" BorderThickness="0" Background="Transparent" Foreground="$($T.Text)" FontFamily="Consolas" FontSize="12"/>
    </Border>
  </StackPanel>
  <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
    <Button x:Name="Retry" Style="{StaticResource Primary}" Content="Retry" MinWidth="96" Visibility="Collapsed"/>
    <Button x:Name="Open" Style="{StaticResource Secondary}" Content="Open" Margin="0,0,8,0" IsEnabled="False" MinWidth="84"/>
    <Button x:Name="Copy" Style="{StaticResource Primary}" Content="Copy" IsEnabled="False" MinWidth="96"/>
  </StackPanel>
</Grid>
"@
    $win = New-CardWindow -Width 468 -Inner $inner -T $T

    try {
        $favPath = Join-Path $env:LOCALAPPDATA "QuickUp\icons\$Service.ico"
        if (-not (Test-Path -LiteralPath $favPath)) { $favPath = Join-Path $env:LOCALAPPDATA 'QuickUp\quickup.ico' }
        if (Test-Path -LiteralPath $favPath) {
            $bmp = [System.Windows.Media.Imaging.BitmapImage]::new()
            $bmp.BeginInit(); $bmp.CacheOption = 'OnLoad'; $bmp.UriSource = [Uri]$favPath; $bmp.EndInit()
            $win.FindName('Fav').Source = $bmp
        }
    } catch { }

    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)

    $ctx = @{
        Win = $win; Timer = $timer
        Status = $win.FindName('Status'); Bar = $win.FindName('Bar')
        UrlWrap = $win.FindName('UrlWrap'); UrlBox = $win.FindName('Url')
        Copy = $win.FindName('Copy'); Open = $win.FindName('Open'); Retry = $win.FindName('Retry')
        Req = $req; Path = $Path; FileName = $fileName; DisplayName = $displayName; Total = $total
        TextBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($T.Text)
        Url = $null; Task = $null; Client = $null; Content = $null; Stream = $null
    }

    $timer.Add_Tick({
        if (-not $ctx.Task.IsCompleted) {
            if ($ctx.Total -gt 0) {
                $pct = [int][Math]::Min(100, [Math]::Floor($ctx.Stream.Sent * 100 / $ctx.Total))
                $ctx.Bar.Value = $pct
                $ctx.Status.Text = "Uploading `"$($ctx.FileName)`" to $($ctx.DisplayName)   $pct%"
            }
            return
        }
        $ctx.Bar.Value = 100
        $ctx.Timer.Stop()
        try {
            $resp = $ctx.Task.GetAwaiter().GetResult()
            $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult().Trim()
            if (-not $resp.IsSuccessStatusCode) { throw "HTTP $([int]$resp.StatusCode): $body" }
            if ($body -notmatch '^https?://\S+$') { throw "Unexpected response: $body" }
            $ctx.Url = $body
            $ctx.Status.Text = "Uploaded to $($ctx.DisplayName)"
            $ctx.Bar.Visibility = 'Collapsed'
            $ctx.UrlBox.Text = $body; $ctx.UrlWrap.Visibility = 'Visible'
            $ctx.UrlBox.Focus(); $ctx.UrlBox.SelectAll()
            $ctx.Copy.IsEnabled = $true; $ctx.Open.IsEnabled = $true
            # Copy last: a clipboard lock must not turn a good upload into an error.
            $ctx.Copy.Content = if (Copy-Text $body) { 'Copied' } else { 'Copy' }
        }
        catch { Set-UploadError $ctx $_.Exception.Message }
    }.GetNewClosure())

    $win.FindName('Header').Add_MouseLeftButtonDown({ $win.DragMove() }.GetNewClosure())
    $win.FindName('Close').Add_Click({ $win.Close() }.GetNewClosure())
    $ctx.Open.Add_Click({ if ($ctx.Url) { Start-Process $ctx.Url } }.GetNewClosure())
    $ctx.Copy.Add_Click({ if ($ctx.Url) { $ctx.Copy.Content = if (Copy-Text $ctx.Url) { 'Copied' } else { 'Copy failed' } } }.GetNewClosure())
    $ctx.Retry.Add_Click({ Start-QuickUpload $ctx }.GetNewClosure())

    Start-QuickUpload $ctx
    [void]$win.ShowDialog()
    $timer.Stop()
    foreach ($d in @($ctx.Stream, $ctx.Content, $ctx.Client)) { if ($d) { try { $d.Dispose() } catch { } } }
}

function Invoke-About {
    Initialize-Wpf
    $T = Get-Theme
    $inner = @"
<Grid Margin="22">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <Grid x:Name="Header" Grid.Row="0" Background="Transparent">
    <TextBlock Text="What each host accepts" FontWeight="SemiBold" FontSize="15" Foreground="$($T.Text)" VerticalAlignment="Center"/>
    <Button x:Name="Close" Style="{StaticResource Ghost}" Content="&#xE10A;" HorizontalAlignment="Right"/>
  </Grid>
  <StackPanel x:Name="List" Grid.Row="1" Margin="0,16,0,0"/>
  <Grid Grid.Row="2" Margin="0,14,0,0">
    <TextBlock Text="Unsupported files are refused before upload." FontSize="11" Foreground="$($T.Sub)" VerticalAlignment="Center"/>
    <Button x:Name="Ok" Style="{StaticResource Primary}" Content="OK" HorizontalAlignment="Right" MinWidth="88"/>
  </Grid>
</Grid>
"@
    $win = New-CardWindow -Width 520 -Inner $inner -T $T
    $list = $win.FindName('List')
    $conv = [System.Windows.Media.BrushConverter]::new()
    $accent = $conv.ConvertFromString($T.Accent); $sub = $conv.ConvertFromString($T.Sub)
    foreach ($svc in $script:Services.Keys) {
        $name = [System.Windows.Controls.TextBlock]::new()
        $name.Text = $script:Services[$svc]; $name.FontWeight = 'SemiBold'; $name.FontSize = 13; $name.Foreground = $accent
        $desc = [System.Windows.Controls.TextBlock]::new()
        $desc.Text = $script:Limits[$svc].Accept; $desc.FontSize = 12; $desc.Foreground = $sub
        $desc.TextWrapping = 'Wrap'; $desc.Margin = [System.Windows.Thickness]::new(0, 2, 0, 14)
        [void]$list.Children.Add($name); [void]$list.Children.Add($desc)
    }
    $win.FindName('Header').Add_MouseLeftButtonDown({ $win.DragMove() }.GetNewClosure())
    $win.FindName('Close').Add_Click({ $win.Close() }.GetNewClosure())
    $win.FindName('Ok').Add_Click({ $win.Close() }.GetNewClosure())
    [void]$win.ShowDialog()
}

function Invoke-SelfTest {
    foreach ($svc in $script:Services.Keys) {
        $r = Get-ServiceRequest -Service $svc
        if ($r.Uri -notmatch '^https://') { throw "SELFTEST: $svc endpoint is not https." }
        if (-not $r.FileField) { throw "SELFTEST: $svc has no file field." }
        if (-not $script:Limits.Contains($svc)) { throw "SELFTEST: $svc has no limits entry." }
        if ($script:Limits[$svc].Max -le 0) { throw "SELFTEST: $svc max size invalid." }
    }
    if ('https://a.b/c' -notmatch '^https?://\S+$') { throw 'SELFTEST: valid URL rejected.' }
    if ('some error text' -match '^https?://\S+$') { throw 'SELFTEST: error text accepted as URL.' }
    Write-Host 'SELFTEST OK' -ForegroundColor Green
}

switch ($Command) {
    'install'   { Install-QuickUp }
    'uninstall' { Uninstall-QuickUp }
    'update'    { Update-QuickUp }
    'upload'    { Invoke-UploadUI -Service $Service -Path $Path }
    'about'     { Invoke-About }
    'selftest'  { Invoke-SelfTest }
}
