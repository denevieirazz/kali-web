param(
    [string]$InstallRoot,
    [string]$RegistrySubKey,
    [switch]$AllowTestRegistryOverride,
    [switch]$ProbeInterruptAfterRegistryWrite
)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'CloudOS.ShellActivation.V14.psm1'
Import-Module -Name $module -Force

$params = @{}
if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) { $params.InstallRoot = $InstallRoot }
if (-not [string]::IsNullOrWhiteSpace($RegistrySubKey)) { $params.RegistrySubKey = $RegistrySubKey }
if ($AllowTestRegistryOverride) { $params.AllowTestRegistryOverride = $true }
if ($ProbeInterruptAfterRegistryWrite) { $params.ProbeInterruptAfterRegistryWrite = $true }

$result = Invoke-CloudOSShellActivation @params
$result | Format-List
Write-Host "[CloudOS V14] SHELL_ACTIVATION_OK root=$($result.install_root) registry_matches=$($result.registry_matches)"
Write-Host '[CloudOS V14] The change applies on the next sign-in. No logoff or reboot was performed.'
