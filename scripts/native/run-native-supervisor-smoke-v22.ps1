[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$BuildDirectory,
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$out = if ($BuildDirectory) {
    (Resolve-Path -LiteralPath $BuildDirectory).Path
} else {
    Join-Path $rootPath 'desktop\CloudOS.NativeShell\bin\Release'
}
$supervisor = Join-Path $out 'CloudOS.Supervisor.exe'
$shell = Join-Path $out 'CloudOS.exe'
foreach ($path in @($supervisor, $shell)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Supervisor V22 smoke binary missing: $path"
    }
}

if (-not $OutputPath) {
    $artifactDir = Join-Path $rootPath 'desktop\CloudOS.NativeShell\artifacts'
    New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
    $OutputPath = Join-Path $artifactDir 'supervisor-v22-smoke.json'
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}

$statePath = Join-Path $env:LOCALAPPDATA 'CloudOS\Recovery\supervisor-state-v22.json'
if (Test-Path -LiteralPath $statePath) {
    Remove-Item -LiteralPath $statePath -Force
}

$failures = [Collections.Generic.List[string]]::new()
$evidence = [ordered]@{}

function Invoke-SupervisorProbe {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $process = Start-Process `
        -FilePath $supervisor `
        -WorkingDirectory $out `
        -ArgumentList $Arguments `
        -PassThru `
        -Wait
    return [int]$process.ExitCode
}

function Read-V22State {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return $null
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ([int]$state.schema -ne 22 -or [string]$state.component -ne 'CloudOS.Supervisor') {
        throw 'Supervisor V22 state schema/component mismatch.'
    }
    return $state
}

try {
    $selfTest = Invoke-SupervisorProbe -Arguments @('--self-test')
    $evidence.self_test_exit_code = $selfTest
    if ($selfTest -ne 0) { $failures.Add("SelfTestExit:$selfTest") }

    $readyExit = Invoke-SupervisorProbe -Arguments @(
        '--probe-ready-once',
        '--probe-no-explorer',
        '--ready-timeout-ms', '30000',
        '--heartbeat-timeout-ms', '5000'
    )
    $evidence.ready_probe_exit_code = $readyExit
    if ($readyExit -ne 0) { $failures.Add("ReadyProbeExit:$readyExit") }

    $readyState = Read-V22State
    $evidence.ready_state_written = ($null -ne $readyState)
    if ($null -eq $readyState) {
        $failures.Add('ReadyStateMissing')
    }
    else {
        $evidence.ready_final_state = [string]$readyState.state
        $evidence.ready_job_assignment_observed = [bool]$readyState.job_kill_on_close_assigned
        if ([string]$readyState.state -ne 'STOPPING') {
            $failures.Add("UnexpectedReadyFinalState:$($readyState.state)")
        }
    }

    $failureExit = Invoke-SupervisorProbe -Arguments @(
        '--probe-failure-loop',
        '--probe-no-explorer',
        '--max-failures', '3',
        '--ready-timeout-ms', '5000',
        '--heartbeat-timeout-ms', '3000'
    )
    $evidence.failure_loop_exit_code = $failureExit
    if ($failureExit -ne 42 -and $failureExit -ne 0) {
        $failures.Add("FailureLoopExit:$failureExit")
    }

    $safeState = Read-V22State
    $evidence.safe_mode_state_written = ($null -ne $safeState)
    if ($null -eq $safeState) {
        $failures.Add('SafeModeStateMissing')
    }
    else {
        $evidence.failure_final_state = [string]$safeState.state
        $evidence.failure_count = [int]$safeState.failure_count
        $evidence.failure_reason = [string]$safeState.reason
        if ([string]$safeState.state -ne 'SAFE_MODE') {
            $failures.Add("UnexpectedFailureFinalState:$($safeState.state)")
        }
        if ([int]$safeState.failure_count -lt 3) {
            $failures.Add("CrashBudgetNotExhausted:$($safeState.failure_count)")
        }
    }

    Start-Sleep -Milliseconds 500
    $remaining = @(Get-Process -Name 'CloudOS' -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -and ([IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($shell))
        }
        catch { $false }
    })
    $evidence.remaining_installation_shell_processes = $remaining.Count
    if ($remaining.Count -ne 0) { $failures.Add('CloudOSProcessLeaked') }

    $statusScript = Join-Path $PSScriptRoot 'get-cloudos-recovery-status-v22.ps1'
    $status = & $statusScript
    $evidence.recovery_status_schema = [int]$status.schema
    $evidence.recovery_status_state_present = [bool]$status.supervisor_state_present
    if ([int]$status.schema -ne 22 -or -not $status.supervisor_state_present) {
        $failures.Add('RecoveryStatusDidNotObserveSupervisorState')
    }
}
catch {
    $failures.Add(('HarnessException:' + $_.Exception.GetType().Name + ':' + $_.Exception.Message))
}

$report = [ordered]@{
    schema = 22
    test = 'CloudOS Supervisor/Recovery V22'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    verdict = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    scope = 'V22 self-test, real readiness/graceful-exit, persistent recovery state, rolling crash budget, safe-mode transition, process cleanup and recovery status diagnostics.'
    evidence = $evidence
    failures = $failures.ToArray()
}

$parent = [IO.Path]::GetDirectoryName($OutputPath)
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8

if ($failures.Count -gt 0) {
    Write-Error "FAIL: Supervisor/Recovery V22 smoke failed: $($failures -join ', '). Report: $OutputPath"
    exit 1
}

Write-Host "PASS: Supervisor/Recovery V22 runtime smoke passed. Report: $OutputPath"
