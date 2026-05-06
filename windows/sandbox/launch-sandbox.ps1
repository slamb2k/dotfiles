# launch-sandbox.ps1 — wrapper around `Start-Process <wsb>` that works around the
# Windows Sandbox lifecycle bug where WindowsSandboxServer.exe doesn't always
# terminate when you close the sandbox window, blocking the next launch with
# "Windows Sandbox failed to initialise."
#
# Usage:
#   pwsh -File launch-sandbox.ps1 .\dotfiles-sandbox-minimal.wsb
#   pwsh -File launch-sandbox.ps1 .\dotfiles-sandbox.wsb

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$WsbPath
)

$ErrorActionPreference = 'Stop'

$resolved = Resolve-Path -LiteralPath $WsbPath
if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "Not a file: $resolved"
}
if ([IO.Path]::GetExtension($resolved) -ne '.wsb') {
    throw "Expected a .wsb file, got: $resolved"
}

$stuck = Get-Process WindowsSandboxServer, WindowsSandboxClient -EA SilentlyContinue
if ($stuck) {
    Write-Host "Killing lingering Sandbox processes:" -ForegroundColor Yellow
    $stuck | Format-Table Name, Id, StartTime -AutoSize | Out-Host
    $stuck | Stop-Process -Force
    Start-Sleep -Seconds 2
}

Write-Host "Launching $resolved" -ForegroundColor Cyan
Start-Process -FilePath $resolved
