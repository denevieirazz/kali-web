param([string]$InstallRoot)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'CloudOS.Deployment.V13.psm1'
Import-Module -Name $module -Force
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Get-CloudOSDefaultInstallRoot
}
$result = Invoke-CloudOSUninstall -InstallRoot $InstallRoot
$result | Format-List
Write-Host "[CloudOS V13] UNINSTALL_OK root=$($result.install_root)"
