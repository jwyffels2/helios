param(
    [Parameter(Mandatory = $true)]
    [string]$UART0
)
$MINPort = "/dev/ttyUSB0"
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ImageName = 'helios-listener:latest'

Write-Host "Preparing UART0 for container passthrough..."
Write-Host ''
Write-Host "Host device: $UART0"
Write-Host "Container alias: $MINPort"
Write-Host "MIN_PORT env: $MINPort"
Write-Host ''

$rootless = (& podman info --format "{{.Host.Security.Rootless}}" 2>$null | Out-String).Trim()

if ([string]::IsNullOrWhiteSpace($rootless)) {
    throw "Failed to query Podman rootless status. Ensure Podman is installed and available in PATH and also turned on."
}

if ($rootless -ne 'false') {
    throw "Podman must be rootful first stop podman by running; podman machine stop; podman machine set --rootful=True"
}

podman build -t helios-listener:latest -f $RepoRoot/ground_station/listener.dockerfile .

$podmanArgs = @(
    'run',
    '-it',
    '--rm',
    '-v', "${RepoRoot}:/workspace",
    '-w', '/workspace',
    '--env', "MIN_PORT=$MINPort",
    "--device=${UART0}:${MINPort}:rwm",
    $ImageName,
    "./ground_station/launch_listener.sh"
)

& podman @podmanArgs
