# Yabosen Controller installer for Windows (x64).
#
#   irm https://github.com/Yabosen/yabosenlivecontroller/releases/latest/download/install.ps1 | iex
#
# Installs to %LOCALAPPDATA%\Programs\Yabosen Controller (no admin needed), adds a
# Start Menu shortcut and an entry in Settings > Apps so it can be uninstalled there.
# Running it again updates to the latest release.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # Invoke-WebRequest is very slow with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = 'Yabosen/yabosenlivecontroller'
$Name = 'Yabosen Controller'
$Version = if ($env:YABOSEN_CONTROLLER_VERSION) { $env:YABOSEN_CONTROLLER_VERSION } else { 'latest' }
$Base = if ($Version -eq 'latest') { "https://github.com/$Repo/releases/latest/download" } else { "https://github.com/$Repo/releases/download/$Version" }

$Dir = Join-Path $env:LOCALAPPDATA "Programs\$Name"
$Exe = Join-Path $Dir 'yabosen-controller.exe'
$Shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) "$Name.lnk"
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\YabosenController'

function Say($text) { Write-Host "==> $text" -ForegroundColor Magenta }

if (-not [Environment]::Is64BitOperatingSystem) { throw "$Name needs 64-bit Windows." }

New-Item -ItemType Directory -Force $Dir | Out-Null

# An older copy may be running from the tray; it has to stop before the file can be replaced.
Get-Process yabosen-controller -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Exe } | Stop-Process -Force
Start-Sleep -Milliseconds 300

Say "Downloading $Name ($Version)"
$download = "$Exe.download"
Invoke-WebRequest -UseBasicParsing -Uri "$Base/yabosen-controller-windows-x64.exe" -OutFile $download
Move-Item -Force $download $Exe

# Remember the installed version for Settings > Apps.
$installed = $Version
try {
    $installed = (Invoke-RestMethod -UseBasicParsing "https://api.github.com/repos/$Repo/releases/$(if ($Version -eq 'latest') { 'latest' } else { "tags/$Version" })").tag_name
} catch { }

Say 'Creating the Start Menu shortcut'
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($Shortcut)
$link.TargetPath = $Exe
$link.WorkingDirectory = $Dir
$link.IconLocation = "$Exe,0"
$link.Description = 'Control your live status on yabosen.live'
$link.Save()

# Uninstaller used by Settings > Apps.
$uninstaller = @"
`$ErrorActionPreference = 'SilentlyContinue'
Get-Process yabosen-controller | Where-Object { `$_.Path -eq '$Exe' } | Stop-Process -Force
Start-Sleep -Milliseconds 300
Remove-Item -Force '$Shortcut'
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name '$Name'
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' -Name '$Name'
Remove-Item -Recurse -Force '$UninstallKey'
Set-Location `$env:TEMP
Remove-Item -Recurse -Force '$Dir'
Write-Host '$Name was removed. Your settings are kept in %APPDATA%\yabosen.'
"@
Set-Content -Path (Join-Path $Dir 'uninstall.ps1') -Value $uninstaller -Encoding UTF8

New-Item -Force $UninstallKey | Out-Null
$props = @{
    DisplayName     = $Name
    DisplayVersion  = ($installed -replace '^v', '')
    Publisher       = 'Yabosen'
    DisplayIcon     = "$Exe,0"
    InstallLocation = $Dir
    URLInfoAbout    = "https://github.com/$Repo"
    UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Dir\uninstall.ps1`""
}
foreach ($key in $props.Keys) { Set-ItemProperty -Path $UninstallKey -Name $key -Value $props[$key] }
Set-ItemProperty -Path $UninstallKey -Name NoModify -Value 1 -Type DWord
Set-ItemProperty -Path $UninstallKey -Name NoRepair -Value 1 -Type DWord

Say "Installed $Name $installed to $Dir"
if (-not $env:YABOSEN_CONTROLLER_NO_LAUNCH) {
    Say 'Starting it now. Find it later in the Start Menu.'
    Start-Process -FilePath $Exe -WorkingDirectory $Dir
}
