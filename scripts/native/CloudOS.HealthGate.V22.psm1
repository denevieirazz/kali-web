Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:RuntimeProcessNames = @(
    'CloudOS',
    'CloudOS.Supervisor',
    'CloudOS.SystemBroker',
    'CloudOS.BrokerProbe',
    'cloudos_flutter_shell'
)
$script:SignedPayloadNames = @(
    'CloudOS.exe',
    'CloudOS.NativeRuntime.dll',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe',
    'install-cloudos-native-v22.ps1',
    'update-cloudos-native-v13.ps1',
    'repair-cloudos-native-v22.ps1',
    'rollback-cloudos-native-v13.ps1',
    'uninstall-cloudos-native-v13.ps1',
    'CloudOS.Deployment.V13.psm1',
    'CloudOS.HealthGate.V22.psm1',
    'CloudOS.ManagedTools.V22.psm1'
)

function Get-CloudOSAuthenticodeEvidenceV22 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Root)

    $fullRoot = (Resolve-Path -LiteralPath $Root).Path
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($name in $script:SignedPayloadNames) {
        $path = Join-Path $fullRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "CloudOS V22 health gate payload is missing: $name"
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $path
        $records.Add([pscustomobject]@{
            file = $name
            status = [string]$signature.Status
            signer = if ($null -ne $signature.SignerCertificate) {
                [string]$signature.SignerCertificate.Subject
            } else { $null }
            thumbprint = if ($null -ne $signature.SignerCertificate) {
                [string]$signature.SignerCertificate.Thumbprint
            } else { $null }
        })
    }
    return @($records)
}

function Get-CloudOSManagedRuntimeProcessesV22 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ManagedRoot)

    $fullRoot = [IO.Path]::GetFullPath($ManagedRoot).TrimEnd('\') + '\'
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($name in $script:RuntimeProcessNames) {
        foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try { $path = [string]$process.Path } catch { continue }
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            $fullPath = [IO.Path]::GetFullPath($path)
            if (-not $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $records.Add([pscustomobject]@{
                name = [string]$process.ProcessName
                pid = [int]$process.Id
                path = $fullPath
            })
        }
    }
    return @($records)
}

function Assert-CloudOSRuntimeStoppedV22 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [string]$Operation = 'maintenance'
    )

    $running = @(Get-CloudOSManagedRuntimeProcessesV22 -ManagedRoot $ManagedRoot)
    if ($running.Count -eq 0) { return }

    $summary = (@($running | ForEach-Object { "$($_.name):$($_.pid)" })) -join ', '
    throw "CloudOS $Operation requires the managed runtime to be stopped first: $summary"
}

function Invoke-CloudOSSupervisorHealthGateV22 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ActiveRoot,
        [ValidateRange(15, 120)][int]$TimeoutSeconds = 45
    )

    $root = (Resolve-Path -LiteralPath $ActiveRoot).Path
    $supervisor = Join-Path $root 'CloudOS.Supervisor.exe'
    if (-not (Test-Path -LiteralPath $supervisor -PathType Leaf)) {
        return [pscustomobject]@{
            healthy = $false
            exit_code = -1
            timed_out = $false
            reason = 'supervisor_missing'
            elapsed_ms = 0
        }
    }

    $arguments = @(
        '--probe-ready-once',
        '--probe-no-explorer',
        '--max-failures', '1',
        '--ready-timeout-ms', '30000',
        '--heartbeat-timeout-ms', '5000'
    )

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process `
        -FilePath $supervisor `
        -ArgumentList $arguments `
        -WorkingDirectory $root `
        -PassThru `
        -WindowStyle Hidden
    try {
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill($true) } catch { try { $process.Kill() } catch {} }
            try { [void]$process.WaitForExit(5000) } catch {}
            return [pscustomobject]@{
                healthy = $false
                exit_code = -1
                timed_out = $true
                reason = 'supervisor_health_timeout'
                elapsed_ms = [int][Math]::Min([int]::MaxValue, $timer.ElapsedMilliseconds)
            }
        }

        return [pscustomobject]@{
            healthy = ($process.ExitCode -eq 0)
            exit_code = [int]$process.ExitCode
            timed_out = $false
            reason = if ($process.ExitCode -eq 0) {
                'ready_heartbeat_graceful_exit'
            } else {
                'supervisor_probe_failed'
            }
            elapsed_ms = [int][Math]::Min([int]::MaxValue, $timer.ElapsedMilliseconds)
        }
    }
    finally {
        $timer.Stop()
        $process.Dispose()
    }
}

Export-ModuleMember -Function @(
    'Get-CloudOSAuthenticodeEvidenceV22',
    'Get-CloudOSManagedRuntimeProcessesV22',
    'Assert-CloudOSRuntimeStoppedV22',
    'Invoke-CloudOSSupervisorHealthGateV22'
)
