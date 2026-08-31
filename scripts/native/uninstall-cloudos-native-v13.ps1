param([string]$InstallRoot)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'CloudOS.Deployment.V13.psm1'
Import-Module -Name $module -Force
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Get-CloudOSDefaultInstallRoot
}

$installFull = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$activationStatePath = Join-Path $installFull 'state\shell-activation-v14.json'
if (Test-Path -LiteralPath $activationStatePath -PathType Leaf) {
    try {
        $activation = Get-Content -LiteralPath $activationStatePath -Raw | ConvertFrom-Json
    }
    catch {
        throw 'CloudOS shell activation state is unreadable. Refusing uninstall until shell recovery is completed.'
    }
    if ([int]$activation.schema -ne 14 -or [string]$activation.product -ne 'CloudOS Native Shell') {
        throw 'Unknown shell activation state exists. Refusing uninstall to avoid removing the configured logon shell.'
    }
    if ([bool]$activation.active) {
        throw 'CloudOS is still configured as the per-user logon shell. Run "Restaurar Explorer.cmd" / Shell Activation V14 rollback before uninstalling.'
    }
}

# Independent fail-safe: even if the V14 state file was manually removed, never delete an
# install root that the production HKCU Winlogon Shell value still references.
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows NT\CurrentVersion\Winlogon', $false)
if ($null -ne $key) {
    try {
        $shell = $key.GetValue('Shell', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -ne $shell -and ([string]$shell).IndexOf($installFull, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw 'HKCU Winlogon Shell still references this CloudOS install root. Restore Explorer before uninstalling.'
        }
    }
    finally {
        $key.Dispose()
    }
}

$result = Invoke-CloudOSUninstall -InstallRoot $InstallRoot
$result | Format-List
Write-Host "[CloudOS V13] UNINSTALL_OK root=$($result.install_root)"
