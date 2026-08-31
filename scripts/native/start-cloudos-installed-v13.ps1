param(
    [string]$InstallRoot,
    [switch]$Recovery
)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'CloudOS.Deployment.V13.psm1'
Import-Module -Name $module -Force
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Get-CloudOSDefaultInstallRoot
}
$launcher = Get-Command -Name 'Start-CloudOSInstalled' -ErrorAction Stop
& $launcher -InstallRoot $InstallRoot -Recovery:$Recovery
Write-Host '[CloudOS V13] START_OK: verified active version delegated to Supervisor V11.'
