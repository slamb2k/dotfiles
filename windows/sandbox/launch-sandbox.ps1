# launch-sandbox.ps1 — robust .wsb launcher for the iteration loop.
#
# Handles three known Windows Sandbox failure modes on Win11 26200:
#   1. Lingering WindowsSandboxServer.exe blocks subsequent launches
#      → kill any leftover Sandbox processes before launching.
#   2. WSL2 holds the same hypervisor virt slot Sandbox needs
#      → wsl --shutdown frees it (skip with -SkipWslShutdown).
#   3. UNC paths (\\wsl.localhost\…) stop resolving the moment WSL is shut
#      down, so a UNC .wsb argument can't be opened after step 2
#      → if the path is UNC, copy the .wsb to a Windows-local temp dir
#        BEFORE shutting WSL down, then launch the local copy.
#
# Usage:
#   pwsh -File launch-sandbox.ps1 .\dotfiles-sandbox-minimal.wsb
#   pwsh -File launch-sandbox.ps1 \\wsl.localhost\Ubuntu\home\me\foo.wsb
#   pwsh -File launch-sandbox.ps1 .\foo.wsb -SkipWslShutdown
#
# Note when invoking from a WSL terminal: wsl --shutdown will terminate
# the bash session that called this script (because that bash lives
# inside WSL). The Windows-side Start-Process call has already fired
# by then, so the sandbox still launches — you just lose the shell.

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$WsbPath,
    [switch]$SkipWslShutdown
)

$ErrorActionPreference = 'Stop'

# 1. Resolve the .wsb path (returns provider-qualified for UNC; use ProviderPath)
$resolved = (Resolve-Path -LiteralPath $WsbPath).ProviderPath
if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "Not a file: $resolved"
}
if ([IO.Path]::GetExtension($resolved) -ne '.wsb') {
    throw "Expected a .wsb file, got: $resolved"
}

# 2. If the .wsb lives on a UNC share (e.g. \\wsl.localhost\…), copy to a
#    Windows-local temp dir BEFORE we shut WSL down (otherwise the source
#    path stops resolving the moment WSL goes away).
if ($resolved.StartsWith('\\')) {
    $tempDir = Join-Path $env:TEMP 'launch-sandbox'
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    $localWsb = Join-Path $tempDir ([IO.Path]::GetFileName($resolved))
    Write-Host "Copying UNC -> local: $localWsb" -ForegroundColor Yellow
    Copy-Item -LiteralPath $resolved -Destination $localWsb -Force
    $resolved = $localWsb
}

# 3. Kill any lingering Sandbox processes from prior runs
$stuck = Get-Process WindowsSandboxServer, WindowsSandboxClient, WindowsSandboxRemoteSession -EA SilentlyContinue
if ($stuck) {
    Write-Host "Killing lingering Sandbox processes:" -ForegroundColor Yellow
    $stuck | Format-Table Name, Id, StartTime -AutoSize | Out-Host
    $stuck | Stop-Process -Force
    Start-Sleep -Seconds 2
}

# 4. Free the hypervisor virt slot held by WSL (the actual root cause of the
#    Sandbox-fails-to-initialise bug on this build, beyond the lingering server).
if (-not $SkipWslShutdown -and (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Running wsl --shutdown..." -ForegroundColor Yellow
    & wsl.exe --shutdown
    Start-Sleep -Seconds 3
}

# 5. Launch
Write-Host "Launching $resolved" -ForegroundColor Cyan
Start-Process -FilePath $resolved
