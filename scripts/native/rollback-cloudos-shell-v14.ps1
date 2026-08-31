param(
    [string]$InstallRoot,
    [string]$RegistrySubKey,
    [switch]$AllowTestRegistryOverride,
    [switch]$ForceRestoreSnapshot
)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'CloudOS.ShellActivation.V14.psm1'
Import-Module -Name $module -Force

$params = @{}
if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) { $params.InstallRoot = $InstallRoot }
if (-not [string]::IsNullOrWhiteSpace($RegistrySubKey)) { $params.RegistrySubKey = $RegistrySubKey }
if ($AllowTestRegistryOverride) { $params.AllowTestRegistryOverride = $true }
if ($ForceRestoreSnapshot) { $params.ForceRestoreSnapshot = $true }

$result = Invoke-CloudOSShellRollback @params
$result | Format-List
Write-Host "[CloudOS V14] SHELL_ROLLBACK_OK root=$($result.install_root) activated=$($result.activated)"
Write-Host '[CloudOS V14] The exact pre-activation Shell value/presence/type was restored. No logoff or reboot was performed.'
