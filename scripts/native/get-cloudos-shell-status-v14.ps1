param(
    [string]$InstallRoot,
    [string]$RegistrySubKey,
    [switch]$AllowTestRegistryOverride
)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'CloudOS.ShellActivation.V14.psm1'
Import-Module -Name $module -Force

$params = @{}
if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) { $params.InstallRoot = $InstallRoot }
if (-not [string]::IsNullOrWhiteSpace($RegistrySubKey)) { $params.RegistrySubKey = $RegistrySubKey }
if ($AllowTestRegistryOverride) { $params.AllowTestRegistryOverride = $true }

Get-CloudOSShellActivationStatus @params | Format-List
