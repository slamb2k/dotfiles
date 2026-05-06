# bootstrap.ps1 — runs inside Windows Sandbox at logon
# Fetched fresh from GitHub each launch (see dotfiles-sandbox.wsb).
#
# Sequence:
#   1. Install winget (Sandbox doesn't ship with App Installer)
#   2. Download dotfiles repo zip and unpack to C:\dotfiles
#   3. Hand off to setup.ps1 (winget configure with the DSC file)
#   4. Print next-step hint for running setup.sh inside WSL Ubuntu

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Section($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

# -----------------------------------------------------------------------------
# 1. Install winget + dependencies
# -----------------------------------------------------------------------------
Section 'Installing winget'

$tmp = "$env:TEMP\winget-bootstrap"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# Detect host arch so we install only the matching appx variants
$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'x64' }
    'ARM64' { 'arm64' }
    default { 'x86' }
}

# Microsoft.WindowsAppRuntime.1.8 — modern winget (1.10+) needs this. Install
# from the official redistributable, which registers a current version.
$warExe = "$tmp\windowsappruntimeinstall-x64.exe"
Invoke-WebRequest 'https://aka.ms/windowsappsdk/1.8/latest/windowsappruntimeinstall-x64.exe' -OutFile $warExe
Start-Process -FilePath $warExe -ArgumentList '--quiet' -Wait

# Pull the latest winget release + its matching DesktopAppInstaller_Dependencies
# zip. Using the deps zip from the *same* release guarantees VCLibs/etc versions
# line up with the bundle — hand-rolled aka.ms URLs drift out of sync.
$rel         = Invoke-RestMethod 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
$bundleAsset = $rel.assets | Where-Object name -Like 'Microsoft.DesktopAppInstaller_*.msixbundle' | Select-Object -First 1
$depsAsset   = $rel.assets | Where-Object name -eq 'DesktopAppInstaller_Dependencies.zip' | Select-Object -First 1

$bundle = "$tmp\winget.msixbundle"
Invoke-WebRequest $bundleAsset.browser_download_url -OutFile $bundle

if ($depsAsset) {
    $depsZip = "$tmp\deps.zip"
    Invoke-WebRequest $depsAsset.browser_download_url -OutFile $depsZip
    Expand-Archive $depsZip -DestinationPath "$tmp\deps" -Force
    Get-ChildItem "$tmp\deps" -Recurse -Filter '*.appx' |
        Where-Object { $_.Name -match "_${arch}\.appx$" } |
        ForEach-Object {
            Write-Host "Installing dep: $($_.Name)"
            Add-AppxPackage $_.FullName -ErrorAction SilentlyContinue
        }
}

Add-AppxPackage $bundle

# Refresh PATH so `winget` resolves in this same session
$env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('PATH', 'User')

winget --version
winget source update --accept-source-agreements | Out-Null

# -----------------------------------------------------------------------------
# 2. Download dotfiles repo (no git yet — use the zip)
# -----------------------------------------------------------------------------
Section 'Downloading dotfiles'

$zip = "$env:TEMP\dotfiles.zip"
Invoke-WebRequest 'https://github.com/slamb2k/dotfiles/archive/refs/heads/main.zip' -OutFile $zip
Expand-Archive -Path $zip -DestinationPath 'C:\' -Force
# Repo lands at C:\dotfiles-main\ — rename for convenience
if (Test-Path C:\dotfiles)      { Remove-Item C:\dotfiles -Recurse -Force }
Rename-Item C:\dotfiles-main C:\dotfiles

# -----------------------------------------------------------------------------
# 3. Run winget configure against the chosen DSC file
#    DOTFILES_PROFILE=minimal  → configuration.dsc.minimal.yaml (3-5 min)
#    otherwise (default)       → configuration.dsc.yaml         (full restore)
# -----------------------------------------------------------------------------
$dscFile = if ($env:DOTFILES_PROFILE -eq 'minimal') {
    '.\windows\configuration.dsc.minimal.yaml'
} else {
    '.\windows\configuration.dsc.yaml'
}
Section "Running winget configure ($dscFile)"

Push-Location C:\dotfiles
try {
    winget configure --file $dscFile --accept-configuration-agreements
}
catch {
    Write-Warning "winget configure failed: $_"
    Write-Warning "You can re-run manually: cd C:\dotfiles; winget configure --file $dscFile --accept-configuration-agreements"
}
finally {
    Pop-Location
}

# -----------------------------------------------------------------------------
# 4. Next steps for setup.sh
# -----------------------------------------------------------------------------
Section 'Next steps'

Write-Host @"
WSL/Ubuntu was installed by the DSC config. To test setup.sh:

  1. Open Windows Terminal (now installed) and pick the Ubuntu profile.
  2. First launch will prompt to create a UNIX user.
  3. Inside Ubuntu:
       git clone https://github.com/slamb2k/dotfiles.git ~/dotfiles
       cd ~/dotfiles
       ./setup.sh

Sandbox state is thrown away when you close this window. Reopen the .wsb
to start over from scratch.
"@ -ForegroundColor Green
