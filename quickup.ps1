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
    [ValidateSet('install', 'uninstall', 'update', 'upload', 'selftest')]
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
    'x0'        = 'x0.at (up to 1 year)'
    'litterbox' = 'Litterbox (1 hour)'
    'uguu'      = 'Uguu (48 hours)'
}

$script:UserAgent = 'QuickUp/1.0 (+https://github.com/Riyoway/quickup)'
$script:RegPath = 'Software\Classes\*\shell\QuickUp'
$script:InstallerUrl = 'https://raw.githubusercontent.com/Riyoway/quickup/main/quickup.ps1'

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
        Invoke-WebRequest -UseBasicParsing -OutFile $Dest -Uri "https://raw.githubusercontent.com/Riyoway/quickup/main/assets/$Rel"
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
    # 0x20 = ECF_SEPARATORBEFORE: draws a line above Update, splitting the
    # hosts from the management actions.
    New-MenuItem '80_update'    'Update QuickUp'    "$visible update"    $icon 0x20
    New-MenuItem '90_uninstall' 'Uninstall QuickUp' "$visible uninstall" $icon

    Write-Banner 'INSTALLED'
    Write-Host '  [ OK ] ' -ForegroundColor Green -NoNewline
    Write-Host 'Added to the right-click menu.'
    Write-Host ''
    Write-Field 'Use'   'Right-click a file  ->  QuickUp  ->  pick a host'
    Write-Field 'Hosts' ($script:Services.Values -join '  |  ')
    Write-Field 'Menu'  'Update / Uninstall are in the submenu too'
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

function Invoke-UploadUI {
    param(
        [Parameter(Mandatory)][string]$Service,
        [Parameter(Mandatory)][string]$Path
    )

    if (-not $script:Services.Contains($Service)) { throw "Unknown service '$Service'." }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: $Path" }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
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

    # Kick the upload off immediately; PostAsync returns a running Task that a
    # UI timer polls, so the dialog stays responsive without extra threads.
    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromHours(1)
    $client.DefaultRequestHeaders.Add('User-Agent', $script:UserAgent)
    $content = [System.Net.Http.MultipartFormDataContent]::new()
    foreach ($k in $req.Fields.Keys) {
        $content.Add([System.Net.Http.StringContent]::new([string]$req.Fields[$k]), $k)
    }
    $total = (Get-Item -LiteralPath $Path).Length
    $stream = [QuickUp.ProgressStream]::new([System.IO.File]::OpenRead($Path))
    $fileContent = [System.Net.Http.StreamContent]::new($stream)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
    $content.Add($fileContent, $req.FileField, $fileName)
    $task = $client.PostAsync($req.Uri, $content)

    $state = [pscustomobject]@{ Url = $null }

    $form = [System.Windows.Forms.Form]@{
        Text = 'QuickUp'; ClientSize = [System.Drawing.Size]::new(444, 150)
        StartPosition = 'CenterScreen'; FormBorderStyle = 'FixedDialog'
        MaximizeBox = $false; MinimizeBox = $false; TopMost = $true
    }
    $label = [System.Windows.Forms.Label]@{
        Location = [System.Drawing.Point]::new(12, 12); Size = [System.Drawing.Size]::new(420, 36)
        Text = "Uploading `"$fileName`" to $displayName ..."
    }
    $bar = [System.Windows.Forms.ProgressBar]@{
        Style = 'Continuous'; Minimum = 0; Maximum = 100
        Location = [System.Drawing.Point]::new(12, 56); Size = [System.Drawing.Size]::new(420, 20)
    }
    $box = [System.Windows.Forms.TextBox]@{
        ReadOnly = $true; Visible = $false
        Location = [System.Drawing.Point]::new(12, 56); Size = [System.Drawing.Size]::new(420, 24)
    }
    $btnCopy = [System.Windows.Forms.Button]@{
        Text = 'Copy'; Enabled = $false
        Location = [System.Drawing.Point]::new(12, 104); Size = [System.Drawing.Size]::new(96, 30)
    }
    $btnOpen = [System.Windows.Forms.Button]@{
        Text = 'Open'; Enabled = $false
        Location = [System.Drawing.Point]::new(116, 104); Size = [System.Drawing.Size]::new(96, 30)
    }
    $btnClose = [System.Windows.Forms.Button]@{
        Text = 'Close'; DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        Location = [System.Drawing.Point]::new(336, 104); Size = [System.Drawing.Size]::new(96, 30)
    }
    $form.Controls.AddRange(@($label, $bar, $box, $btnCopy, $btnOpen, $btnClose))
    $form.CancelButton = $btnClose

    $btnCopy.Add_Click({
        if ($state.Url) { $btnCopy.Text = if (Copy-Text $state.Url) { 'Copied!' } else { 'Copy failed' } }
    }.GetNewClosure())
    $btnOpen.Add_Click({ if ($state.Url) { Start-Process $state.Url } }.GetNewClosure())

    $timer = [System.Windows.Forms.Timer]@{ Interval = 150 }
    $timer.Add_Tick({
        if (-not $task.IsCompleted) {
            if ($total -gt 0) {
                $pct = [int][Math]::Min(100, [Math]::Floor($stream.Sent * 100 / $total))
                $bar.Value = $pct
                $label.Text = "Uploading `"$fileName`" to $displayName ...  $pct%"
            }
            return
        }
        $bar.Value = 100
        $timer.Stop()
        $bar.Visible = $false
        $box.Visible = $true
        try {
            $resp = $task.GetAwaiter().GetResult()
            $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult().Trim()
            if (-not $resp.IsSuccessStatusCode) { throw "HTTP $([int]$resp.StatusCode): $body" }
            if ($body -notmatch '^https?://\S+$') { throw "Unexpected response: $body" }
            $state.Url = $body
            $label.Text = "Uploaded to $displayName :"
            $box.Text = $body
            $box.SelectAll()
            $btnCopy.Enabled = $true; $btnOpen.Enabled = $true
            # Copy last: a clipboard lock must not turn a good upload into an error.
            $btnCopy.Text = if (Copy-Text $body) { 'Copied!' } else { 'Copy' }
        }
        catch {
            $label.Text = 'Upload failed:'
            $box.ForeColor = [System.Drawing.Color]::Firebrick
            $box.Text = $_.Exception.Message
        }
        finally {
            $stream.Dispose(); $content.Dispose(); $client.Dispose()
        }
    }.GetNewClosure())

    $timer.Start()
    [void]$form.ShowDialog()
    $timer.Dispose(); $form.Dispose()
}

function Invoke-SelfTest {
    foreach ($svc in $script:Services.Keys) {
        $r = Get-ServiceRequest -Service $svc
        if ($r.Uri -notmatch '^https://') { throw "SELFTEST: $svc endpoint is not https." }
        if (-not $r.FileField) { throw "SELFTEST: $svc has no file field." }
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
    'selftest'  { Invoke-SelfTest }
}
