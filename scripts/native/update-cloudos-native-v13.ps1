[CmdletBinding()]
param(
    [string]$PackageRoot = $PSScriptRoot,
    [string]$InstallRoot,
    [int]$RetainVersions = 2,
    [int]$HealthTimeoutSeconds = 45,
    [switch]$RequireAuthenticodeSignature,
    [switch]$SkipPostActivationHealthCheck
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$deploymentModule = Join-Path $PSScriptRoot 'CloudOS.Deployment.V13.psm1'
$healthModule = Join-Path $PSScriptRoot 'CloudOS.HealthGate.V22.psm1'
$managedToolsModule = Join-Path $PSScriptRoot 'CloudOS.ManagedTools.V22.psm1'
foreach ($path in @($deploymentModule, $healthModule, $managedToolsModule)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "CloudOS V22 update dependency missing: $path"
    }
}
Import-Module -Name $deploymentModule -Force
Import-Module -Name $healthModule -Force
Import-Module -Name $managedToolsModule -Force

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Get-CloudOSDefaultInstallRoot
}
if ($RetainVersions -lt 2 -or $RetainVersions -gt 10) {
    throw 'RetainVersions must be between 2 and 10 so rollback capacity is preserved.'
}
if ($HealthTimeoutSeconds -lt 15 -or $HealthTimeoutSeconds -gt 120) {
    throw 'HealthTimeoutSeconds must be between 15 and 120.'
}

# Manifest/SHA256 validation remains mandatory in Deployment V13. Authenticode
# is additive evidence until a production signing certificate is configured.
$sourceIdentity = Get-CloudOSPayloadIdentity -PackageRoot $PackageRoot
$signatureEvidence = @(Get-CloudOSAuthenticodeEvidenceV22 -Root $sourceIdentity.Root)
$unsignedOrInvalid = @($signatureEvidence | Where-Object { $_.status -ne 'Valid' })
if ($RequireAuthenticodeSignature -and $unsignedOrInvalid.Count -gt 0) {
    $invalidSummary = (@($unsignedOrInvalid | ForEach-Object { "$($_.file)=$($_.status)" })) -join ', '
    throw "Authenticode enforcement rejected update payload: $invalidSummary"
}

$before = Get-CloudOSDeploymentStatus -InstallRoot $InstallRoot
if ($before.installed) {
    Assert-CloudOSRuntimeStoppedV22 -ManagedRoot $before.install_root -Operation 'update'
}

$previousActive = [string]$before.active_version
$deploymentSucceeded = $false
$health = $null
$status = $null
$managedTools = $null
try {
    $status = Invoke-CloudOSDeployment `
        -SourcePackageRoot $sourceIdentity.Root `
        -InstallRoot $InstallRoot `
        -RetainVersions $RetainVersions
    $deploymentSucceeded = $true

    if ($SkipPostActivationHealthCheck) {
        $health = [pscustomobject]@{
            healthy = $null
            exit_code = $null
            timed_out = $false
            reason = 'explicitly_skipped'
            elapsed_ms = 0
        }
    }
    else {
        $activeRoot = Join-Path (Join-Path $status.install_root 'versions') $status.active_version
        $health = Invoke-CloudOSSupervisorHealthGateV22 `
            -ActiveRoot $activeRoot `
            -TimeoutSeconds $HealthTimeoutSeconds

        if (-not $health.healthy) {
            if (-not [string]::IsNullOrWhiteSpace($previousActive)) {
                $rollback = Invoke-CloudOSRollback -InstallRoot $InstallRoot
                throw "CloudOS V22 update health gate failed ($($health.reason), exit=$($health.exit_code)); rollback restored $($rollback.active_version)."
            }

            # A failed first activation has no LKG. Do not leave a known-bad
            # version behind merely because this entrypoint can service install.
            try { [void](Invoke-CloudOSUninstall -InstallRoot $InstallRoot) } catch {}
            throw "CloudOS V22 update health gate failed with no last-known-good version ($($health.reason)). Managed activation was removed when possible."
        }
    }

    # V13 keeps immutable version/state ownership. Only after a healthy V22
    # activation do we publish V22 maintenance entrypoints into the managed root.
    # A deliberately skipped health gate does not get to refresh recovery tools.
    if (-not $SkipPostActivationHealthCheck) {
        $managedTools = Install-CloudOSManagedToolsV22 `
            -SourceRoot $PSScriptRoot `
            -InstallRoot $status.install_root
    }
}
catch {
    if (-not $deploymentSucceeded) {
        Write-Host '[CloudOS V22] Deployment failed before post-activation health was accepted.'
    }
    throw
}

$status = Get-CloudOSDeploymentStatus -InstallRoot $InstallRoot
$report = [pscustomobject]@{
    schema = 22
    operation = 'update'
    verdict = if ($SkipPostActivationHealthCheck) { 'deployed_unprobed' } else { 'pass' }
    active_version = $status.active_version
    last_known_good = $status.last_known_good
    active_valid = $status.active_valid
    health = $health
    signature_enforced = [bool]$RequireAuthenticodeSignature
    signature_all_valid = ($unsignedOrInvalid.Count -eq 0)
    signature_evidence = $signatureEvidence
    rollback_capacity = (-not [string]::IsNullOrWhiteSpace([string]$status.last_known_good))
    managed_tools_synced = ($null -ne $managedTools -and [bool]$managedTools.installed)
}

$report | Format-List
Write-Host "[CloudOS V22] UPDATE_OK active=$($status.active_version) lkg=$($status.last_known_good) health=$($health.reason) toolsSynced=$($report.managed_tools_synced) signatureEnforced=$([bool]$RequireAuthenticodeSignature)"
