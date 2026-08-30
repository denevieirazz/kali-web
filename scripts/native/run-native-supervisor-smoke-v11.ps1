param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$BuildDirectory,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$out = if ($BuildDirectory) { (Resolve-Path -LiteralPath $BuildDirectory).Path } else { Join-Path $rootPath 'desktop\CloudOS.NativeShell\bin\Release' }
$supervisor = Join-Path $out 'CloudOS.Supervisor.exe'
$shell = Join-Path $out 'CloudOS.exe'
foreach ($path in @($supervisor, $shell)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Supervisor V11 binary missing: $path" }
}

if (-not $OutputPath) {
    $artifactDir = Join-Path $rootPath 'desktop\CloudOS.NativeShell\artifacts'
    New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
    $OutputPath = Join-Path $artifactDir 'supervisor-v11-smoke.json'
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }

. (Join-Path $PSScriptRoot 'native-health-v9.ps1')

$failures = [Collections.Generic.List[string]]::new()
$evidence = [ordered]@{}

function Invoke-Probe {
    param([string[]]$Arguments)
    $process = Start-Process -FilePath $supervisor -WorkingDirectory $out -ArgumentList $Arguments -PassThru -Wait
    return [int]$process.ExitCode
}

try {
    if (Get-CloudOSHealthSnapshotV9) {
        throw 'A CloudOS health block already exists before Supervisor V11 smoke.'
    }

    $selfTest = Invoke-Probe @('--self-test')
    $evidence.self_test_exit_code = $selfTest
    if ($selfTest -ne 0) { $failures.Add("SelfTestExit:$selfTest") }

    $readyProbe = Invoke-Probe @(
        '--probe-ready-once',
        '--probe-no-explorer',
        '--ready-timeout-ms', '30000',
        '--heartbeat-timeout-ms', '5000'
    )
    $evidence.ready_probe_exit_code = $readyProbe
    if ($readyProbe -ne 0) { $failures.Add("ReadyProbeExit:$readyProbe") }

    Start-Sleep -Milliseconds 500
    $healthAfterReady = Get-CloudOSHealthSnapshotV9
    $evidence.health_mapping_released_after_ready_probe = ($null -eq $healthAfterReady)
    if ($healthAfterReady) { $failures.Add('HealthMappingLeakedAfterReadyProbe') }

    $failureProbe = Invoke-Probe @(
        '--probe-failure-loop',
        '--probe-no-explorer',
        '--max-failures', '3',
        '--ready-timeout-ms', '5000',
        '--heartbeat-timeout-ms', '3000'
    )
    $evidence.failure_loop_exit_code = $failureProbe
    # 42 means Explorer fallback was deliberately suppressed by the probe.
    # 0 is also valid when Windows already has an Explorer shell active.
    if ($failureProbe -ne 42 -and $failureProbe -ne 0) {
        $failures.Add("FailureLoopExit:$failureProbe")
    }

    Start-Sleep -Milliseconds 500
    $healthAfterFailure = Get-CloudOSHealthSnapshotV9
    $evidence.health_mapping_absent_after_failure_loop = ($null -eq $healthAfterFailure)
    if ($healthAfterFailure) { $failures.Add('HealthMappingLeakedAfterFailureLoop') }

    $cloudos = @(Get-Process -Name 'CloudOS' -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and ([IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($shell)) } catch { $false }
    })
    $evidence.remaining_installation_shell_processes = $cloudos.Count
    if ($cloudos.Count -ne 0) { $failures.Add('CloudOSProcessLeaked') }
}
catch {
    $failures.Add(('HarnessException:' + $_.Exception.GetType().Name + ':' + $_.Exception.Message))
}

$report = [ordered]@{
    schema = 11
    test = 'CloudOS Shell Supervisor V11'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    verdict = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    scope = 'External supervisor binary, real CloudOS readiness/heartbeat/graceful-exit probe, deterministic abnormal-exit restart loop, fallback decision without launching Explorer in probe mode.'
    evidence = $evidence
    failures = $failures.ToArray()
}

$parent = [IO.Path]::GetDirectoryName($OutputPath)
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8

if ($failures.Count -gt 0) {
    Write-Error "FAIL: Shell Supervisor V11 smoke failed: $($failures -join ', '). Report: $OutputPath"
    exit 1
}
Write-Host "PASS: Shell Supervisor V11 runtime smoke passed. Report: $OutputPath"
