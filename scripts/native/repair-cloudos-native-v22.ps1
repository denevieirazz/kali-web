[CmdletBinding()]
param(
    [string]$InstallRoot,
    [ValidateRange(15, 120)][int]$HealthTimeoutSeconds = 45
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$deploymentModule = Join-Path $PSScriptRoot 'CloudOS.Deployment.V13.psm1'
$healthModule = Join-Path $PSScriptRoot 'CloudOS.HealthGate.V22.psm1'
foreach ($path in @($deploymentModule, $healthModule)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "CloudOS Repair V22 dependency missing: $path"
    }
}
Import-Module -Name $deploymentModule -Force
Import-Module -Name $healthModule -Force

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Get-CloudOSDefaultInstallRoot
}

$before = Get-CloudOSDeploymentStatus -InstallRoot $InstallRoot
if (-not $before.installed) {
    throw 'CloudOS Repair V22 requires an existing managed installation.'
}
Assert-CloudOSRuntimeStoppedV22 -ManagedRoot $before.install_root -Operation 'repair'

$repair = Invoke-CloudOSRepair -InstallRoot $InstallRoot
$status = Get-CloudOSDeploymentStatus -InstallRoot $InstallRoot
if (-not $status.active_valid) {
    throw 'CloudOS Repair V22 could not establish a hash-valid active payload.'
}

$versionsRoot = Join-Path $status.install_root 'versions'
$activeRoot = Join-Path $versionsRoot $status.active_version
$primaryHealth = Invoke-CloudOSSupervisorHealthGateV22 `
    -ActiveRoot $activeRoot `
    -TimeoutSeconds $HealthTimeoutSeconds

$fallbackAttempted = $false
$fallbackHealth = $null
$fallbackVersion = $null
if (-not $primaryHealth.healthy) {
    $candidate = [string]$status.last_known_good
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and
        -not $candidate.Equals([string]$status.active_version, [StringComparison]::OrdinalIgnoreCase)) {
        $candidateRoot = Join-Path $versionsRoot $candidate
        try {
            [void](Test-CloudOSPayload -PackageRoot $candidateRoot)
            $fallbackAttempted = $true
            $rolledBack = Invoke-CloudOSRollback -InstallRoot $InstallRoot
            $fallbackVersion = [string]$rolledBack.active_version
            $fallbackRoot = Join-Path $versionsRoot $fallbackVersion
            $fallbackHealth = Invoke-CloudOSSupervisorHealthGateV22 `
                -ActiveRoot $fallbackRoot `
                -TimeoutSeconds $HealthTimeoutSeconds
        }
        catch {
            $fallbackAttempted = $true
            $fallbackHealth = [pscustomobject]@{
                healthy = $false
                exit_code = -1
                timed_out = $false
                reason = 'last_known_good_validation_or_rollback_failed'
                elapsed_ms = 0
            }
        }
    }
}

$finalStatus = Get-CloudOSDeploymentStatus -InstallRoot $InstallRoot
$healthy = if ($primaryHealth.healthy) {
    $true
} elseif ($null -ne $fallbackHealth) {
    [bool]$fallbackHealth.healthy
} else {
    $false
}

$report = [pscustomobject]@{
    schema = 22
    operation = 'repair'
    verdict = if ($healthy) { 'pass' } else { 'fail' }
    repair_action = [string]$repair.action
    active_version = [string]$finalStatus.active_version
    active_valid = [bool]$finalStatus.active_valid
    primary_health = $primaryHealth
    fallback_attempted = $fallbackAttempted
    fallback_version = $fallbackVersion
    fallback_health = $fallbackHealth
    last_known_good = [string]$finalStatus.last_known_good
}
$report | Format-List

if (-not $healthy) {
    throw "CloudOS Repair V22 could not prove a healthy runtime. active=$($finalStatus.active_version) primary=$($primaryHealth.reason) fallback=$(if ($null -ne $fallbackHealth) { $fallbackHealth.reason } else { 'unavailable' }). Use CloudOS Recovery/Explorer and inspect local diagnostics before activating the shell again."
}

Write-Host "[CloudOS V22] REPAIR_OK active=$($finalStatus.active_version) fallbackAttempted=$fallbackAttempted health=$(if ($primaryHealth.healthy) { $primaryHealth.reason } else { $fallbackHealth.reason })"
