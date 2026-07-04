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
    [ValidateSet('install', 'uninstall', 'upload', 'selftest')]
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
    'litterbox' = 'Litterbox (1 hour)'
    '0x0'       = '0x0.st (up to 1 year)'
    'uguu'      = 'Uguu (48 hours)'
}

$script:UserAgent = 'QuickUp/1.0 (+https://github.com/Riyoway/quickup)'
$script:RegPath = 'Software\Classes\*\shell\QuickUp'

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
        '0x0' {
            @{ Uri = 'https://0x0.st'; Fields = @{}; FileField = 'file' }
        }
        'uguu' {
            @{ Uri = 'https://uguu.se/upload?output=text'; Fields = @{}; FileField = 'files[]' }
        }
        default { throw "Unknown service '$Service'." }
    }
}

function Install-QuickUp {
    $installDir = Join-Path $env:LOCALAPPDATA 'QuickUp'
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    $target = Join-Path $installDir 'quickup.ps1'
    if ($PSCommandPath -and ($PSCommandPath -ne $target)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $target -Force
    }

    # Menu icon: use the bundled .ico when installing from the repo, otherwise
    # fetch it once (best effort) so the one-line remote install still gets it.
    $icon = Join-Path $installDir 'quickup.ico'
    $srcIcon = Join-Path (Split-Path -Parent $PSCommandPath) 'assets\quickup.ico'
    if (Test-Path -LiteralPath $srcIcon) {
        Copy-Item -LiteralPath $srcIcon -Destination $icon -Force
    }
    elseif (-not (Test-Path -LiteralPath $icon)) {
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -OutFile $icon `
                -Uri 'https://raw.githubusercontent.com/Riyoway/quickup/main/assets/quickup.ico'
        } catch { }
    }

    # Always launch through Windows PowerShell so the menu works even if the
    # user installed from pwsh 7.
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    # The '*' key is a wildcard in the PS registry provider, so drive it
    # through the .NET API which treats the path literally.
    [void][Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($script:RegPath, $false)
    $root = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:RegPath)
    $root.SetValue('MUIVerb', 'QuickUp')
    if (Test-Path -LiteralPath $icon) { $root.SetValue('Icon', $icon) }
    $root.SetValue('SubCommands', '')  # empty + nested 'shell' key => cascade
    $root.Close()

    foreach ($svc in $script:Services.Keys) {
        $verb = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$script:RegPath\shell\$svc")
        $verb.SetValue('', $script:Services[$svc])
        $verb.Close()
        $cmd = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$script:RegPath\shell\$svc\command")
        $cmd.SetValue('', "`"$ps`" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`" upload $svc `"%1`"")
        $cmd.Close()
    }

    Write-Banner 'INSTALLED'
    Write-Host '  [ OK ] ' -ForegroundColor Green -NoNewline
    Write-Host 'Added to the right-click menu.'
    Write-Host ''
    Write-Field 'Use'   'Right-click a file  ->  QuickUp  ->  pick a host'
    Write-Field 'Hosts' ($script:Services.Values -join '  |  ')
    Write-Field 'Script' $target
    Write-Host ''
    Write-Host '  Uninstall anytime:' -ForegroundColor DarkGray
    Write-Host "     powershell -ExecutionPolicy Bypass -File `"$target`" uninstall" -ForegroundColor Yellow
    Write-Host ('=' * 60) -ForegroundColor DarkCyan
    Write-Host ''
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
    $stream = [System.IO.File]::OpenRead($Path)
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
        Style = 'Marquee'; MarqueeAnimationSpeed = 30
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
        if ($state.Url) { [System.Windows.Forms.Clipboard]::SetText($state.Url); $btnCopy.Text = 'Copied!' }
    }.GetNewClosure())
    $btnOpen.Add_Click({ if ($state.Url) { Start-Process $state.Url } }.GetNewClosure())

    $timer = [System.Windows.Forms.Timer]@{ Interval = 150 }
    $timer.Add_Tick({
        if (-not $task.IsCompleted) { return }
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
            [System.Windows.Forms.Clipboard]::SetText($body)
            $btnCopy.Text = 'Copied!'; $btnCopy.Enabled = $true; $btnOpen.Enabled = $true
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
    'upload'    { Invoke-UploadUI -Service $Service -Path $Path }
    'selftest'  { Invoke-SelfTest }
}
