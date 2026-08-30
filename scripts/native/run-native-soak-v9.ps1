param(
    [string]$Root = $(if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'CloudOS.exe')) { $PSScriptRoot } else { (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }),
    [string]$BuildDirectory,
    [string]$OutputPath,
    [ValidateRange(5, 172800)][int]$DurationSeconds = 300,
    [ValidateRange(1, 300)][int]$StartupTimeoutSeconds = 30,
    [ValidateRange(250, 10000)][int]$IntervalMilliseconds = 1000,
    [ValidateRange(1, 120)][int]$HeartbeatTimeoutSeconds = 5,
    [ValidateRange(0, 4096)][int]$MaxWorkingSetGrowthMB = 256,
    [ValidateRange(0, 4096)][int]$MaxPrivateGrowthMB = 256,
    [ValidateRange(0, 10000)][int]$MaxHandleGrowth = 512,
    [ValidateRange(0, 5000)][int]$MaxGdiGrowth = 256,
    [ValidateRange(0, 5000)][int]$MaxUserGrowth = 256,
    [ValidateRange(0, 1000)][int]$MaxThreadGrowth = 64,
    [ValidateRange(0, 100)][double]$MaxAverageCpuPercent = 0,
    [switch]$Launch,
    [ValidateRange(0, 2147483647)][int]$ProcessId = 0
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'native-health-v9.ps1')

if ($Launch -and $ProcessId -ne 0) {
    throw 'Choose either -Launch or -ProcessId, not both.'
}

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$out = if ($BuildDirectory) {
    (Resolve-Path -LiteralPath $BuildDirectory).Path
} elseif (Test-Path -LiteralPath (Join-Path $rootPath 'CloudOS.exe')) {
    $rootPath
} else {
    Join-Path $rootPath 'desktop\CloudOS.NativeShell\bin\Release'
}
$exe = Join-Path $out 'CloudOS.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "CloudOS.exe not found: $exe"
}

if (-not $OutputPath) {
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
    $OutputPath = Join-Path $base ('CloudOS\Diagnostics\stability-v9-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.json')
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$parent = [IO.Path]::GetDirectoryName($OutputPath)
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
if (Test-Path -LiteralPath $OutputPath) { throw 'Stability report destination already exists.' }

$startedProcess = $null
$ownsProcess = $false
$failures = [Collections.Generic.List[string]]::new()
$samples = [Collections.Generic.List[object]]::new()
$ready = $null
$baseline = $null
$summary = $null

function Get-CloudOSProcessSampleV9 {
    param(
        [Parameter(Mandatory)][int]$Id,
        [Parameter(Mandatory)]$Health,
        [double]$ElapsedSeconds
    )

    $process = Get-Process -Id $Id -ErrorAction Stop
    $process.Refresh()
    $responding = $true
    try { $responding = [bool]$process.Responding } catch { $responding = $false }

    [pscustomobject][ordered]@{
        elapsed_seconds = [Math]::Round($ElapsedSeconds, 3)
        pid = $Id
        responding = $responding
        cpu_seconds = [Math]::Round($process.TotalProcessorTime.TotalSeconds, 6)
        working_set_bytes = [int64]$process.WorkingSet64
        private_bytes = [int64]$process.PrivateMemorySize64
        threads = [int]$process.Threads.Count
        handles = [int]$process.HandleCount
        health_handles = [int]$Health.handle_count
        gdi_objects = [int]$Health.gdi_objects
        user_objects = [int]$Health.user_objects
        heartbeat_count = [uint64]$Health.heartbeat_count
        heartbeat_tick_ms = [uint64]$Health.heartbeat_tick_ms
    }
}

try {
    if ($Launch) {
        if (Get-CloudOSHealthSnapshotV9) {
            throw 'A CloudOS health block already exists in this session. Close the running shell before launching an isolated stability probe.'
        }
        $startedProcess = Start-Process -FilePath $exe -WorkingDirectory $out -ArgumentList '--stability-probe' -PassThru
        $ownsProcess = $true
        $ProcessId = $startedProcess.Id
    }

    $ready = Wait-CloudOSReadyV9 -TimeoutSeconds $StartupTimeoutSeconds -ExpectedProcessId $ProcessId
    if (-not $ready) {
        if ($startedProcess -and $startedProcess.HasExited) {
            throw "CloudOS exited before readiness. Exit code: $($startedProcess.ExitCode)"
        }
        throw "CloudOS did not reach Ready within $StartupTimeoutSeconds seconds."
    }
    if ($ProcessId -eq 0) { $ProcessId = [int]$ready.process_id }
    if ($ready.process_id -ne $ProcessId) {
        throw "Health PID $($ready.process_id) does not match monitored PID $ProcessId."
    }
    if (-not (Test-CloudOSHeartbeatFreshV9 -Snapshot $ready -MaximumAgeSeconds $HeartbeatTimeoutSeconds)) {
        throw 'CloudOS reached Ready with a stale UI heartbeat.'
    }

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $baseline = Get-CloudOSProcessSampleV9 -Id $ProcessId -Health $ready -ElapsedSeconds 0
    $samples.Add($baseline)

    $maxWorkingSet = [int64]$baseline.working_set_bytes
    $maxPrivate = [int64]$baseline.private_bytes
    $maxHandles = [int]$baseline.health_handles
    $maxGdi = [int]$baseline.gdi_objects
    $maxUser = [int]$baseline.user_objects
    $maxThreads = [int]$baseline.threads
    $lastCpuSeconds = [double]$baseline.cpu_seconds
    $lastCpuElapsed = 0.0
    $cpuPercentSum = 0.0
    $cpuPercentSamples = 0
    $notRespondingStreak = 0

    while ($timer.Elapsed.TotalSeconds -lt $DurationSeconds) {
        Start-Sleep -Milliseconds $IntervalMilliseconds

        $health = Get-CloudOSHealthSnapshotV9
        if (-not $health) {
            $failures.Add('HealthMappingMissing')
            break
        }
        if ($health.process_id -ne $ProcessId) {
            $failures.Add('HealthProcessChanged')
            break
        }
        if ($health.state -ne 2) {
            $failures.Add("HealthStateNotReady:$($health.state)")
            break
        }
        if (-not (Test-CloudOSHeartbeatFreshV9 -Snapshot $health -MaximumAgeSeconds $HeartbeatTimeoutSeconds)) {
            $failures.Add('UiHeartbeatStale')
            break
        }

        try {
            $sample = Get-CloudOSProcessSampleV9 -Id $ProcessId -Health $health -ElapsedSeconds $timer.Elapsed.TotalSeconds
        }
        catch {
            $failures.Add('ProcessExitedOrUnreadable')
            break
        }
        $samples.Add($sample)

        if ($sample.responding) { $notRespondingStreak = 0 } else { ++$notRespondingStreak }
        if ($notRespondingStreak -ge 3) {
            $failures.Add('WindowNotResponding')
            break
        }

        $maxWorkingSet = [Math]::Max($maxWorkingSet, [int64]$sample.working_set_bytes)
        $maxPrivate = [Math]::Max($maxPrivate, [int64]$sample.private_bytes)
        $maxHandles = [Math]::Max($maxHandles, [int]$sample.health_handles)
        $maxGdi = [Math]::Max($maxGdi, [int]$sample.gdi_objects)
        $maxUser = [Math]::Max($maxUser, [int]$sample.user_objects)
        $maxThreads = [Math]::Max($maxThreads, [int]$sample.threads)

        $elapsedDelta = [double]$sample.elapsed_seconds - $lastCpuElapsed
        $cpuDelta = [double]$sample.cpu_seconds - $lastCpuSeconds
        if ($elapsedDelta -gt 0 -and $cpuDelta -ge 0) {
            $cpuPercent = 100.0 * $cpuDelta / $elapsedDelta / [Math]::Max(1, [Environment]::ProcessorCount)
            $cpuPercentSum += $cpuPercent
            ++$cpuPercentSamples
        }
        $lastCpuElapsed = [double]$sample.elapsed_seconds
        $lastCpuSeconds = [double]$sample.cpu_seconds
    }

    $mb = 1MB
    $workingSetGrowth = [int64]($maxWorkingSet - [int64]$baseline.working_set_bytes)
    $privateGrowth = [int64]($maxPrivate - [int64]$baseline.private_bytes)
    $handleGrowth = [int]($maxHandles - [int]$baseline.health_handles)
    $gdiGrowth = [int]($maxGdi - [int]$baseline.gdi_objects)
    $userGrowth = [int]($maxUser - [int]$baseline.user_objects)
    $threadGrowth = [int]($maxThreads - [int]$baseline.threads)
    $averageCpu = if ($cpuPercentSamples -gt 0) { $cpuPercentSum / $cpuPercentSamples } else { 0.0 }

    if ($MaxWorkingSetGrowthMB -gt 0 -and $workingSetGrowth -gt ($MaxWorkingSetGrowthMB * $mb)) { $failures.Add('WorkingSetGrowthBudgetExceeded') }
    if ($MaxPrivateGrowthMB -gt 0 -and $privateGrowth -gt ($MaxPrivateGrowthMB * $mb)) { $failures.Add('PrivateBytesGrowthBudgetExceeded') }
    if ($MaxHandleGrowth -gt 0 -and $handleGrowth -gt $MaxHandleGrowth) { $failures.Add('HandleGrowthBudgetExceeded') }
    if ($MaxGdiGrowth -gt 0 -and $gdiGrowth -gt $MaxGdiGrowth) { $failures.Add('GdiGrowthBudgetExceeded') }
    if ($MaxUserGrowth -gt 0 -and $userGrowth -gt $MaxUserGrowth) { $failures.Add('UserGrowthBudgetExceeded') }
    if ($MaxThreadGrowth -gt 0 -and $threadGrowth -gt $MaxThreadGrowth) { $failures.Add('ThreadGrowthBudgetExceeded') }
    if ($MaxAverageCpuPercent -gt 0 -and $averageCpu -gt $MaxAverageCpuPercent) { $failures.Add('AverageCpuBudgetExceeded') }

    $summary = [ordered]@{
        ready_latency_ms = [uint64]$ready.ready_tick_ms - [uint64]$ready.started_tick_ms
        duration_seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
        sample_count = $samples.Count
        average_cpu_percent = [Math]::Round($averageCpu, 3)
        working_set_growth_bytes = $workingSetGrowth
        private_bytes_growth = $privateGrowth
        handle_growth = $handleGrowth
        gdi_growth = $gdiGrowth
        user_growth = $userGrowth
        thread_growth = $threadGrowth
        max_working_set_bytes = $maxWorkingSet
        max_private_bytes = $maxPrivate
        max_handles = $maxHandles
        max_gdi_objects = $maxGdi
        max_user_objects = $maxUser
        max_threads = $maxThreads
    }
}
catch {
    $failures.Add(('HarnessException:' + $_.Exception.GetType().Name))
    if (-not $summary) {
        $summary = [ordered]@{
            duration_seconds = 0
            sample_count = $samples.Count
        }
    }
}
finally {
    if ($ownsProcess -and $startedProcess) {
        try {
            if (-not $startedProcess.HasExited) {
                Stop-Process -Id $startedProcess.Id -Force -ErrorAction SilentlyContinue
                [void]$startedProcess.WaitForExit(5000)
            }
        } catch {}
    }
}

$report = [ordered]@{
    schema = 9
    test = 'CloudOS Stability/Readiness V9'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    verdict = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    privacy = 'Allowlisted process/resource metadata only. No window titles, filenames, command lines, URLs, credentials, session contents, dumps or uploads.'
    process_id = $ProcessId
    executable = 'CloudOS.exe'
    startup_timeout_seconds = $StartupTimeoutSeconds
    heartbeat_timeout_seconds = $HeartbeatTimeoutSeconds
    requested_duration_seconds = $DurationSeconds
    budgets = [ordered]@{
        max_working_set_growth_mb = $MaxWorkingSetGrowthMB
        max_private_growth_mb = $MaxPrivateGrowthMB
        max_handle_growth = $MaxHandleGrowth
        max_gdi_growth = $MaxGdiGrowth
        max_user_growth = $MaxUserGrowth
        max_thread_growth = $MaxThreadGrowth
        max_average_cpu_percent = $MaxAverageCpuPercent
    }
    summary = $summary
    failures = $failures.ToArray()
    samples = $samples.ToArray()
}

$json = $report | ConvertTo-Json -Depth 10
$stream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }

if ($failures.Count -gt 0) {
    Write-Error "FAIL: Stability/Readiness V9 failed: $($failures -join ', '). Report: $OutputPath"
    exit 1
}

Write-Host "PASS: Stability/Readiness V9 completed with $($samples.Count) samples. Report: $OutputPath"
