param(
    [string]$InstallRoot,
    [switch]$AllowTestRegistryOverride
)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'CloudOS.ShellActivation.V14.psm1'
Import-Module -Name $module -Force

$params = @{}
if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) { $params.InstallRoot = $InstallRoot }
if ($AllowTestRegistryOverride) { $params.AllowTestRegistryOverride = $true }

$result = Invoke-CloudOSShellRepair @params
$result | Format-List
if ($result.repaired -ne $true) {
    throw "CloudOS V14 shell repair detected unresolved drift: $($result.action)"
}
Write-Host "[CloudOS V14] SHELL_REPAIR_OK action=$($result.action)"
