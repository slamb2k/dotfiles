# test.ps1 — kick off a Windows Sandbox iteration test in one command.
#
# Run from PowerShell on Windows (no elevation required):
#   irm https://raw.githubusercontent.com/slamb2k/dotfiles/main/test.ps1 | iex
#
# Default profile is 'minimal' (~5 min iteration loop). For the full
# machine-restoration test (~30 min), prefix with the env var:
#   $env:DOTFILES_PROFILE='full'; irm https://raw.githubusercontent.com/slamb2k/dotfiles/main/test.ps1 | iex
#
# What it does:
#   1. Downloads launch-sandbox.ps1 + the chosen .wsb fresh from main into
#      %TEMP%\dotfiles-sandbox  (so each run picks up the latest fixes —
#      no git checkout required)
#   2. Calls launch-sandbox.ps1, which:
#        - copies UNC paths to local if needed
#        - kills any lingering WindowsSandbox* processes
#        - runs `wsl --shutdown` to free the hypervisor virt slot
#        - launches the .wsb (which fetches bootstrap.ps1 from main and
#          runs `winget configure` against the chosen DSC)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$wsbName = if ($env:DOTFILES_PROFILE -eq 'full') {
    'dotfiles-sandbox.wsb'
} else {
    'dotfiles-sandbox-minimal.wsb'
}

$dest = "$env:TEMP\dotfiles-sandbox"
$base = 'https://raw.githubusercontent.com/slamb2k/dotfiles/main/windows/sandbox'

Write-Host "=== Downloading test artifacts ($wsbName) ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Invoke-WebRequest "$base/launch-sandbox.ps1" -OutFile "$dest\launch-sandbox.ps1"
Invoke-WebRequest "$base/$wsbName"           -OutFile "$dest\$wsbName"

Write-Host "=== Launching $wsbName ===" -ForegroundColor Cyan
& "$dest\launch-sandbox.ps1" "$dest\$wsbName"
