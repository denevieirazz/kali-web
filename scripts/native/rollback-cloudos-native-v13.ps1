param([string]$InstallRoot)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'CloudOS.Deployment.V13.psm1'
Import-Module -Name $module -Force
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Get-CloudOSDefaultInstallRoot
}
$status = Invoke-CloudOSRollback -InstallRoot $InstallRoot
$status | Format-List
Write-Host "[CloudOS V13] ROLLBACK_OK active=$($status.active_version) lkg=$($status.last_known_good)"
