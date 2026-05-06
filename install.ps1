# install.ps1 — cold-start installer for the Windows side of the dotfiles.
#
# Run on a fresh Win11 machine from an elevated PowerShell:
#   irm https://raw.githubusercontent.com/slamb2k/dotfiles/main/install.ps1 | iex
#
# What it does:
#   1. Self-elevates if not admin
#   2. Installs winget + dependencies if missing
#   3. Installs Git if missing (via winget)
#   4. Clones / updates the repo to %USERPROFILE%\dotfiles
#   5. Runs `winget configure` against windows\configuration.dsc.yaml
#   6. Prints next-step hint for the WSL / setup.sh side
#
# Idempotent. Safe to re-run.

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Section($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

# -----------------------------------------------------------------------------
# 1. Self-elevate
# -----------------------------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Section 'Re-launching elevated'
    Start-Process pwsh.exe -Verb RunAs -ArgumentList @(
        '-ExecutionPolicy', 'Bypass',
        '-NoExit',
        '-Command', "irm https://raw.githubusercontent.com/slamb2k/dotfiles/main/install.ps1 | iex"
    )
    return
}

# -----------------------------------------------------------------------------
# 2. winget + dependencies
# -----------------------------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Section 'Installing winget'

    $tmp = "$env:TEMP\winget-bootstrap"
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { 'x64' }
        'ARM64' { 'arm64' }
        default { 'x86' }
    }

    # WindowsAppRuntime 1.8 (newer winget needs this)
    Invoke-WebRequest 'https://aka.ms/windowsappsdk/1.8/latest/windowsappruntimeinstall-x64.exe' -OutFile "$tmp\war.exe"
    Start-Process -FilePath "$tmp\war.exe" -ArgumentList '--quiet' -Wait

    # winget bundle + matching deps zip from the same release
    $rel         = Invoke-RestMethod 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    $bundleAsset = $rel.assets | Where-Object name -Like 'Microsoft.DesktopAppInstaller_*.msixbundle' | Select-Object -First 1
    $depsAsset   = $rel.assets | Where-Object name -eq 'DesktopAppInstaller_Dependencies.zip' | Select-Object -First 1

    Invoke-WebRequest $bundleAsset.browser_download_url -OutFile "$tmp\winget.msixbundle"
    if ($depsAsset) {
        Invoke-WebRequest $depsAsset.browser_download_url -OutFile "$tmp\deps.zip"
        Expand-Archive "$tmp\deps.zip" -DestinationPath "$tmp\deps" -Force
        Get-ChildItem "$tmp\deps" -Recurse -Filter '*.appx' |
            Where-Object { $_.Name -match "_${arch}\.appx$" } |
            ForEach-Object { Add-AppxPackage $_.FullName -ErrorAction SilentlyContinue }
    }
    Add-AppxPackage "$tmp\winget.msixbundle"

    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('PATH', 'User')
    winget --version
    winget source update --accept-source-agreements | Out-Null
}

# -----------------------------------------------------------------------------
# 3. Git
# -----------------------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Section 'Installing Git'
    winget install --id Git.Git --silent `
        --accept-package-agreements --accept-source-agreements | Out-Null
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('PATH', 'User')
}

# -----------------------------------------------------------------------------
# 4. Clone or update the dotfiles repo
# -----------------------------------------------------------------------------
$repo = "$env:USERPROFILE\dotfiles"
if (-not (Test-Path $repo)) {
    Section "Cloning to $repo"
    git clone https://github.com/slamb2k/dotfiles.git $repo
} else {
    Section "Updating $repo"
    git -C $repo pull --rebase --autostash
}

# -----------------------------------------------------------------------------
# 5. Run the DSC
# -----------------------------------------------------------------------------
Section 'Running winget configure (full DSC)'
Push-Location $repo
try {
    winget configure --file .\windows\configuration.dsc.yaml `
        --accept-configuration-agreements
} finally {
    Pop-Location
}

# -----------------------------------------------------------------------------
# 6. Next steps
# -----------------------------------------------------------------------------
Section 'Next steps'
Write-Host @"
Windows side complete. If WSL or Hyper-V features just enabled, REBOOT NOW
before continuing — those features won't take effect until reboot.

After reboot, in Windows Terminal -> Ubuntu profile:
    curl -fsSL https://raw.githubusercontent.com/slamb2k/dotfiles/main/install.sh | bash

Or, if you've already cloned ~/dotfiles inside WSL:
    cd ~/dotfiles && ./setup.sh
"@ -ForegroundColor Green
