param(
    [string]$PackageRoot = $PSScriptRoot,
    [string]$InstallRoot,
    [int]$RetainVersions = 2
)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'CloudOS.Deployment.V13.psm1'
Import-Module -Name $module -Force
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Get-CloudOSDefaultInstallRoot
}
$status = Invoke-CloudOSDeployment -SourcePackageRoot $PackageRoot -InstallRoot $InstallRoot -RetainVersions $RetainVersions
$status | Format-List
Write-Host "[CloudOS V13] UPDATE_OK active=$($status.active_version) lkg=$($status.last_known_good)"
