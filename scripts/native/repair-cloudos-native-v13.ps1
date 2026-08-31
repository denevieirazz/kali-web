param([string]$InstallRoot)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'CloudOS.Deployment.V13.psm1'
Import-Module -Name $module -Force
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Get-CloudOSDefaultInstallRoot
}
$result = Invoke-CloudOSRepair -InstallRoot $InstallRoot
$result | Format-List
Write-Host "[CloudOS V13] REPAIR_OK action=$($result.action) active=$($result.active_version)"
