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

$module = Join-Path $PSScriptRoot 'CloudOS.Deployment.V13.psm1'
Import-Module -Name $module -Force

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Get-CloudOSDefaultInstallRoot
}
if ($RetainVersions -lt 2 -or $RetainVersions -gt 10) {
    throw 'RetainVersions must be between 2 and 10 so rollback capacity is preserved.'
}
if ($HealthTimeoutSeconds -lt 15 -or $HealthTimeoutSeconds -gt 120) {
    throw 'HealthTimeoutSeconds must be between 15 and 120.'
}

function Get-CloudOSAuthenticodeEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Root)

    $records = New-Object System.Collections.Generic.List[object]
    foreach ($name in @(
        'CloudOS.exe',
        'CloudOS.NativeRuntime.dll',
        'CloudOS.Supervisor.exe',
        'CloudOS.SystemBroker.exe',
        'CloudOS.BrokerProbe.exe'
    )) {
        $path = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Update package is missing required payload before activation: $name"
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $path
        $records.Add([pscustomobject]@{
            file = $name
            status = [string]$signature.Status
            signer = if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { $null }
            thumbprint = if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Thumbprint } else { $null }
        })
    }
    return @($records)
}

function Assert-CloudOSRuntimeStoppedForUpdate {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ManagedRoot)

    $fullRoot = [IO.Path]::GetFullPath($ManagedRoot).TrimEnd('\') + '\'
    $running = New-Object System.Collections.Generic.List[string]
    foreach ($name in @(
        'CloudOS',
        'CloudOS.Supervisor',
        'CloudOS.SystemBroker',
        'CloudOS.BrokerProbe',
        'cloudos_flutter_shell'
    )) {
        foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try { $path = [string]$process.Path } catch { continue }
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            $fullPath = [IO.Path]::GetFullPath($path)
            if ($fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
                $running.Add("$($process.ProcessName):$($process.Id)")
            }
        }
    }
    if ($running.Count -gt 0) {
        throw "CloudOS update requires the managed runtime to be stopped first: $($running -join ', ')"
    }
}

function Invoke-CloudOSPostActivationHealthGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ActiveRoot,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $supervisor = Join-Path $ActiveRoot 'CloudOS.Supervisor.exe'
    if (-not (Test-Path -LiteralPath $supervisor -PathType Leaf)) {
        return [pscustomobject]@{ healthy = $false; exit_code = -1; timed_out = $false; reason = 'supervisor_missing' }
    }

    $arguments = @(
        '--probe-ready-once', '--probe-no-explorer',
        '--max-failures', '1',
        '--ready-timeout-ms', '30000',
        '--heartbeat-timeout-ms', '5000'
    )
    $process = Start-Process -FilePath $supervisor -ArgumentList $arguments -WorkingDirectory $ActiveRoot -PassThru -WindowStyle Hidden

    try {
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill($true) } catch { try { $process.Kill() } catch {} }
            try { [void]$process.WaitForExit(5000) } catch {}
            return [pscustomobject]@{ healthy = $false; exit_code = -1; timed_out = $true; reason = 'supervisor_health_timeout' }
        }

        return [pscustomobject]@{
            healthy = ($process.ExitCode -eq 0)
            exit_code = [int]$process.ExitCode
            timed_out = $false
            reason = if ($process.ExitCode -eq 0) { 'ready_heartbeat_graceful_exit' } else { 'supervisor_probe_failed' }
        }
    }
    finally {
        $process.Dispose()
    }
}

# Manifest/SHA256 validation remains mandatory in Deployment V13. Authenticode
# is additive evidence until a production signing certificate is configured.
$sourceIdentity = Get-CloudOSPayloadIdentity -PackageRoot $PackageRoot
$signatureEvidence = @(Get-CloudOSAuthenticodeEvidence -Root $sourceIdentity.Root)
$unsignedOrInvalid = @($signatureEvidence | Where-Object { $_.status -ne 'Valid' })
if ($RequireAuthenticodeSignature -and $unsignedOrInvalid.Count -gt 0) {
    $invalidSummary = (@($unsignedOrInvalid | ForEach-Object { "$($_.file)=$($_.status)" })) -join ', '
    throw "Authenticode enforcement rejected update payload: $invalidSummary"
}

$before = Get-CloudOSDeploymentStatus -InstallRoot $InstallRoot
if ($before.installed) {
    Assert-CloudOSRuntimeStoppedForUpdate -ManagedRoot $before.install_root
}

$previousActive = [string]$before.active_version
$deploymentSucceeded = $false
$health = $null
$status = $null
try {
    $status = Invoke-CloudOSDeployment -SourcePackageRoot $sourceIdentity.Root -InstallRoot $InstallRoot -RetainVersions $RetainVersions
    $deploymentSucceeded = $true

    if ($SkipPostActivationHealthCheck) {
        $health = [pscustomobject]@{ healthy = $null; exit_code = $null; timed_out = $false; reason = 'explicitly_skipped' }
    }
    else {
        $activeRoot = Join-Path (Join-Path $status.install_root 'versions') $status.active_version
        $health = Invoke-CloudOSPostActivationHealthGate -ActiveRoot $activeRoot -TimeoutSeconds $HealthTimeoutSeconds

        if (-not $health.healthy) {
            if (-not [string]::IsNullOrWhiteSpace($previousActive)) {
                $rollback = Invoke-CloudOSRollback -InstallRoot $InstallRoot
                throw "CloudOS V22 update health gate failed ($($health.reason), exit=$($health.exit_code)); rollback restored $($rollback.active_version)."
            }

            # A failed first update has no LKG. Do not leave a known-bad active
            # version behind merely because this entrypoint was used for install.
            try { [void](Invoke-CloudOSUninstall -InstallRoot $InstallRoot) } catch {}
            throw "CloudOS V22 update health gate failed with no last-known-good version ($($health.reason)). Managed activation was removed when possible."
        }
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
}

$report | Format-List
Write-Host "[CloudOS V22] UPDATE_OK active=$($status.active_version) lkg=$($status.last_known_good) health=$($health.reason) signatureEnforced=$([bool]$RequireAuthenticodeSignature)"
