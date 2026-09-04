[CmdletBinding()]
param(
    [string]$PackageRoot = $PSScriptRoot,
    [string]$InstallRoot,
    [int]$RetainVersions = 2,
    [int]$HealthTimeoutSeconds = 45,
    [switch]$RequireAuthenticodeSignature
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$module = Join-Path $PSScriptRoot 'CloudOS.Deployment.V13.psm1'
$hardenedUpdate = Join-Path $PSScriptRoot 'update-cloudos-native-v13.ps1'
foreach ($path in @($module, $hardenedUpdate)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "CloudOS V22 install dependency missing: $path"
    }
}

Import-Module -Name $module -Force
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Get-CloudOSDefaultInstallRoot
}

# INSTALL and UPDATE intentionally share one activation/health implementation.
# A first install has no last-known-good version; the V22 activation entrypoint
# removes the managed activation again if the real Supervisor readiness gate fails.
$before = Get-CloudOSDeploymentStatus -InstallRoot $InstallRoot
if ($before.installed) {
    throw "CloudOS is already installed at $($before.install_root). Use Atualizar CloudOS.cmd so the existing last-known-good chain is preserved."
}

$arguments = @{
    PackageRoot = $PackageRoot
    InstallRoot = $InstallRoot
    RetainVersions = $RetainVersions
    HealthTimeoutSeconds = $HealthTimeoutSeconds
}
if ($RequireAuthenticodeSignature) {
    $arguments.RequireAuthenticodeSignature = $true
}

# update-cloudos-native-v13.ps1 is a PowerShell script and signals failure by
# terminating error/exception. A successful script invocation does not promise
# to initialize the native-process exit-code automatic variable, so relying on
# that state under Set-StrictMode can turn a healthy first install into a false failure.
& $hardenedUpdate @arguments

$after = Get-CloudOSDeploymentStatus -InstallRoot $InstallRoot
if (-not $after.installed -or -not $after.active_valid) {
    throw 'CloudOS V22 install entrypoint returned without a valid managed activation.'
}

Write-Host "[CloudOS V22] INSTALL_OK active=$($after.active_version) root=$($after.install_root) healthGate=required"
