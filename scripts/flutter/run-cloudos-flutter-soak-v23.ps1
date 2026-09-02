# CloudOS Flutter V23 — interactive long-session soak
#
# Default mode starts the tracked Windows Release build and samples it for
# five hours while the operator uses CloudOS normally. AttachExisting can be
# used when CloudOS is already running. The harness never logs session file
# contents or user file paths; it records only process telemetry and structural
# session-health counters.

[CmdletBinding()]
param(
    [ValidateRange(1, 10080)]
    [int]$DurationMinutes = 300,

    [ValidateRange(5, 3600)]
    [int]$SampleIntervalSeconds = 60,

    [ValidateRange(0, 600)]
    [int]$WarmupSeconds = 20,

    [string]$ExecutablePath = '',
    [string]$OutputDirectory = '',

    [switch]$AttachExisting,
    [switch]$StopLaunchedProcessOnExit,

    [ValidateRange(64, 32768)]
    [double]$MaxWorkingSetGrowthMb = 2048,

    [ValidateRange(64, 32768)]
    [double]$MaxPrivateGrowthMb = 2048,

    [ValidateRange(100, 100000)]
    [int]$MaxHandleGrowth = 2500,

    [ValidateRange(1, 60)]
    [int]$MaxConsecutiveGrowthBreaches = 5,

    [ValidateRange(1, 60)]
    [int]$MaxConsecutiveInvalidSessionSamples = 3,

    [ValidateRange(1, 60)]
    [int]$MaxConsecutiveBrokerMissingSamples = 3,

    [ValidateRange(0, 100)]
    [int]$MaxBrokerRestarts = 3
)

$ErrorActionPreference = 'Stop'
$root = (Get-Item "$PSScriptRoot\..\..").FullName

if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
    $ExecutablePath = Join-Path $root 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\cloudos_flutter_shell.exe'
}
$ExecutablePath = [IO.Path]::GetFullPath($ExecutablePath)

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $OutputDirectory = Join-Path $root "TestResults\v23-flutter-soak\$stamp"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$csvPath = Join-Path $OutputDirectory 'samples.csv'
$summaryPath = Join-Path $OutputDirectory 'summary.json'
$livePath = Join-Path $OutputDirectory 'live-status.json'
$eventsPath = Join-Path $OutputDirectory 'events.log'

foreach ($path in @($csvPath, $summaryPath, $livePath, $eventsPath)) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}

function Write-SoakEvent {
    param([Parameter(Mandatory = $true)][string]$Message)
    $line = '{0} {1}' -f (Get-Date).ToUniversalTime().ToString('o'), $Message
    Add-Content -LiteralPath $eventsPath -Value $line -Encoding UTF8
    Write-Host "[CloudOS soak] $Message"
}

function Get-ProcessByIdSafe {
    param([int]$Id)
    if ($Id -le 0) { return $null }
    return Get-Process -Id $Id -ErrorAction SilentlyContinue
}

function Get-LatestProcessByNameSafe {
    param([Parameter(Mandatory = $true)][string]$Name)
    $items = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    if ($items.Count -eq 0) { return $null }
    return $items | Sort-Object -Property StartTime -Descending | Select-Object -First 1
}

function Get-ProcessSample {
    param($Process)
    if ($null -eq $Process) { return $null }
    try {
        $Process.Refresh()
        return [ordered]@{
            pid = [int]$Process.Id
            workingSetMb = [math]::Round(([double]$Process.WorkingSet64 / 1MB), 2)
            privateMb = [math]::Round(([double]$Process.PrivateMemorySize64 / 1MB), 2)
            handles = [int]$Process.HandleCount
            threads = [int]$Process.Threads.Count
            cpuSeconds = [math]::Round(([double]($Process.CPU ?? 0.0)), 3)
        }
    }
    catch {
        return $null
    }
}

function Read-SessionHealth {
    param([string]$Path)

    $result = [ordered]@{
        state = 'not-seen'
        schemaVersion = $null
        sequence = $null
        activeWorkspace = $null
        windowCount = $null
        error = $null
    }

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        $result.state = 'missing'
        return $result
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            throw 'desktop_session.json is empty'
        }
        $decoded = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $decoded) { throw 'desktop_session.json decoded to null' }

        $result.state = 'valid'
        if ($null -ne $decoded.schemaVersion) { $result.schemaVersion = [int]$decoded.schemaVersion }
        if ($null -ne $decoded.sequence) { $result.sequence = [int64]$decoded.sequence }
        if ($null -ne $decoded.activeWorkspace) { $result.activeWorkspace = [int]$decoded.activeWorkspace }
        if ($null -ne $decoded.windows) { $result.windowCount = @($decoded.windows).Count }
        return $result
    }
    catch {
        $result.state = 'invalid'
        $result.error = $_.Exception.GetType().Name
        return $result
    }
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $tmp = "$Path.tmp"
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

if (-not $AttachExisting -and -not (Test-Path -LiteralPath $ExecutablePath)) {
    throw "CloudOS Flutter Release executable not found: $ExecutablePath. Build it with: cd desktop/CloudOS.FlutterShell; flutter build windows --release"
}

$processName = [IO.Path]::GetFileNameWithoutExtension($ExecutablePath)
$shellProcess = $null
$launchedByHarness = $false

if ($AttachExisting) {
    $shellProcess = Get-LatestProcessByNameSafe -Name $processName
    if ($null -eq $shellProcess) {
        throw "AttachExisting requested, but no exact process '$processName' is running."
    }
    Write-SoakEvent "attached to existing CloudOS PID $($shellProcess.Id)"
}
else {
    $workingDirectory = Split-Path -Parent $ExecutablePath
    $shellProcess = Start-Process -FilePath $ExecutablePath -WorkingDirectory $workingDirectory -PassThru
    $launchedByHarness = $true
    Write-SoakEvent "started CloudOS PID $($shellProcess.Id) from tracked Release build"
}

$shellPid = [int]$shellProcess.Id
$startedAt = (Get-Date).ToUniversalTime()
$deadline = $startedAt.AddMinutes($DurationMinutes)
$sessionPath = if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Join-Path $env:LOCALAPPDATA 'CloudOS\desktop_session.json'
} else { '' }

if ($WarmupSeconds -gt 0) {
    Write-SoakEvent "warmup ${WarmupSeconds}s; use CloudOS normally when the desktop appears"
    Start-Sleep -Seconds $WarmupSeconds
}

$baseline = $null
$maxShellWorkingSetMb = 0.0
$maxShellPrivateMb = 0.0
$maxShellHandles = 0
$maxShellThreads = 0
$maxBrokerWorkingSetMb = 0.0
$maxBrokerPrivateMb = 0.0
$maxBrokerHandles = 0
$sampleCount = 0
$sessionValidSamples = 0
$sessionInvalidSamples = 0
$sessionMissingSamples = 0
$sessionSeen = $false
$consecutiveInvalidSession = 0
$consecutiveBrokerMissing = 0
$consecutiveGrowthBreaches = 0
$brokerRestarts = 0
$lastBrokerPid = 0
$failures = [System.Collections.Generic.List[string]]::new()
$verdict = 'running'
$completedNormally = $false

try {
    while ((Get-Date).ToUniversalTime() -lt $deadline) {
        $now = (Get-Date).ToUniversalTime()
        $elapsed = [math]::Round(($now - $startedAt).TotalSeconds, 1)
        $shellLive = Get-ProcessByIdSafe -Id $shellPid
        $shell = Get-ProcessSample -Process $shellLive

        if ($null -eq $shell) {
            $failures.Add("CloudOS shell PID $shellPid exited during soak at ${elapsed}s")
            Write-SoakEvent $failures[$failures.Count - 1]
            break
        }

        if ($null -eq $baseline) {
            $baseline = [ordered]@{
                workingSetMb = $shell.workingSetMb
                privateMb = $shell.privateMb
                handles = $shell.handles
                threads = $shell.threads
            }
            Write-SoakEvent "baseline WS=$($shell.workingSetMb)MB Private=$($shell.privateMb)MB Handles=$($shell.handles) Threads=$($shell.threads)"
        }

        $maxShellWorkingSetMb = [math]::Max($maxShellWorkingSetMb, [double]$shell.workingSetMb)
        $maxShellPrivateMb = [math]::Max($maxShellPrivateMb, [double]$shell.privateMb)
        $maxShellHandles = [math]::Max($maxShellHandles, [int]$shell.handles)
        $maxShellThreads = [math]::Max($maxShellThreads, [int]$shell.threads)

        $workingSetGrowth = [math]::Round(([double]$shell.workingSetMb - [double]$baseline.workingSetMb), 2)
        $privateGrowth = [math]::Round(([double]$shell.privateMb - [double]$baseline.privateMb), 2)
        $handleGrowth = [int]$shell.handles - [int]$baseline.handles
        $growthBreached = $workingSetGrowth -gt $MaxWorkingSetGrowthMb -or
            $privateGrowth -gt $MaxPrivateGrowthMb -or
            $handleGrowth -gt $MaxHandleGrowth
        if ($growthBreached) { $consecutiveGrowthBreaches++ } else { $consecutiveGrowthBreaches = 0 }
        if ($consecutiveGrowthBreaches -ge $MaxConsecutiveGrowthBreaches) {
            $failures.Add("resource growth exceeded limits for $consecutiveGrowthBreaches consecutive samples: WS +${workingSetGrowth}MB, Private +${privateGrowth}MB, Handles +$handleGrowth")
            Write-SoakEvent $failures[$failures.Count - 1]
            break
        }

        $brokerProcess = Get-LatestProcessByNameSafe -Name 'CloudOS.SystemBroker'
        $broker = Get-ProcessSample -Process $brokerProcess
        if ($null -ne $broker) {
            $consecutiveBrokerMissing = 0
            if ($lastBrokerPid -gt 0 -and $lastBrokerPid -ne [int]$broker.pid) {
                $brokerRestarts++
                Write-SoakEvent "SystemBroker PID changed $lastBrokerPid -> $($broker.pid) (restart $brokerRestarts)"
            }
            $lastBrokerPid = [int]$broker.pid
            $maxBrokerWorkingSetMb = [math]::Max($maxBrokerWorkingSetMb, [double]$broker.workingSetMb)
            $maxBrokerPrivateMb = [math]::Max($maxBrokerPrivateMb, [double]$broker.privateMb)
            $maxBrokerHandles = [math]::Max($maxBrokerHandles, [int]$broker.handles)
            if ($brokerRestarts -gt $MaxBrokerRestarts) {
                $failures.Add("SystemBroker restarted $brokerRestarts times; allowed=$MaxBrokerRestarts")
                Write-SoakEvent $failures[$failures.Count - 1]
                break
            }
        }
        elseif ($lastBrokerPid -gt 0) {
            $consecutiveBrokerMissing++
            if ($consecutiveBrokerMissing -ge $MaxConsecutiveBrokerMissingSamples) {
                $failures.Add("SystemBroker disappeared for $consecutiveBrokerMissing consecutive samples after previously being observed")
                Write-SoakEvent $failures[$failures.Count - 1]
                break
            }
        }

        $session = Read-SessionHealth -Path $sessionPath
        switch ($session.state) {
            'valid' {
                $sessionSeen = $true
                $sessionValidSamples++
                $consecutiveInvalidSession = 0
            }
            'invalid' {
                $sessionSeen = $true
                $sessionInvalidSamples++
                $consecutiveInvalidSession++
            }
            default {
                $sessionMissingSamples++
                if ($sessionSeen) { $consecutiveInvalidSession++ }
            }
        }
        if ($consecutiveInvalidSession -ge $MaxConsecutiveInvalidSessionSamples) {
            $failures.Add("desktop_session.json was invalid/missing after being established for $consecutiveInvalidSession consecutive samples")
            Write-SoakEvent $failures[$failures.Count - 1]
            break
        }

        $sample = [pscustomobject][ordered]@{
            timestampUtc = $now.ToString('o')
            elapsedSeconds = $elapsed
            shellPid = $shell.pid
            shellWorkingSetMb = $shell.workingSetMb
            shellPrivateMb = $shell.privateMb
            shellHandles = $shell.handles
            shellThreads = $shell.threads
            shellCpuSeconds = $shell.cpuSeconds
            shellWorkingSetGrowthMb = $workingSetGrowth
            shellPrivateGrowthMb = $privateGrowth
            shellHandleGrowth = $handleGrowth
            brokerPid = if ($null -ne $broker) { $broker.pid } else { $null }
            brokerWorkingSetMb = if ($null -ne $broker) { $broker.workingSetMb } else { $null }
            brokerPrivateMb = if ($null -ne $broker) { $broker.privateMb } else { $null }
            brokerHandles = if ($null -ne $broker) { $broker.handles } else { $null }
            brokerCpuSeconds = if ($null -ne $broker) { $broker.cpuSeconds } else { $null }
            brokerRestarts = $brokerRestarts
            sessionState = $session.state
            sessionSchemaVersion = $session.schemaVersion
            sessionSequence = $session.sequence
            sessionActiveWorkspace = $session.activeWorkspace
            sessionWindowCount = $session.windowCount
        }

        if ($sampleCount -eq 0) {
            $sample | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
        }
        else {
            $sample | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -Append
        }
        $sampleCount++

        $live = [ordered]@{
            schema = 23
            state = 'running'
            startedAtUtc = $startedAt.ToString('o')
            updatedAtUtc = $now.ToString('o')
            targetDurationMinutes = $DurationMinutes
            sampleCount = $sampleCount
            shellPid = $shellPid
            shellWorkingSetMb = $shell.workingSetMb
            shellPrivateMb = $shell.privateMb
            shellHandles = $shell.handles
            brokerPid = if ($null -ne $broker) { $broker.pid } else { $null }
            brokerRestarts = $brokerRestarts
            sessionState = $session.state
            failures = @($failures)
        }
        Write-JsonAtomic -Value $live -Path $livePath

        Write-Host ("[CloudOS soak] {0}/{1} min | WS {2} MB | Private {3} MB | Handles {4} | Broker {5} | Session {6}" -f
            [math]::Round($elapsed / 60.0, 1), $DurationMinutes, $shell.workingSetMb,
            $shell.privateMb, $shell.handles,
            $(if ($null -ne $broker) { $broker.pid } else { 'n/a' }), $session.state)

        $remaining = ($deadline - (Get-Date).ToUniversalTime()).TotalSeconds
        if ($remaining -le 0) { break }
        Start-Sleep -Seconds ([math]::Min($SampleIntervalSeconds, [math]::Ceiling($remaining)))
    }

    $completedNormally = $failures.Count -eq 0 -and (Get-Date).ToUniversalTime() -ge $deadline.AddSeconds(-1)
    if ($failures.Count -gt 0) {
        $verdict = 'fail'
    }
    elseif ($completedNormally) {
        $verdict = 'pass'
    }
    else {
        $verdict = 'incomplete'
    }
}
finally {
    $endedAt = (Get-Date).ToUniversalTime()
    $summary = [ordered]@{
        schema = 23
        verdict = $verdict
        startedAtUtc = $startedAt.ToString('o')
        endedAtUtc = $endedAt.ToString('o')
        requestedDurationMinutes = $DurationMinutes
        observedDurationMinutes = [math]::Round(($endedAt - $startedAt).TotalMinutes, 2)
        sampleIntervalSeconds = $SampleIntervalSeconds
        warmupSeconds = $WarmupSeconds
        sampleCount = $sampleCount
        launchedByHarness = $launchedByHarness
        attachExisting = [bool]$AttachExisting
        shellPid = $shellPid
        shell = [ordered]@{
            baselineWorkingSetMb = if ($null -ne $baseline) { $baseline.workingSetMb } else { $null }
            baselinePrivateMb = if ($null -ne $baseline) { $baseline.privateMb } else { $null }
            baselineHandles = if ($null -ne $baseline) { $baseline.handles } else { $null }
            maxWorkingSetMb = $maxShellWorkingSetMb
            maxPrivateMb = $maxShellPrivateMb
            maxHandles = $maxShellHandles
            maxThreads = $maxShellThreads
            maxWorkingSetGrowthAllowedMb = $MaxWorkingSetGrowthMb
            maxPrivateGrowthAllowedMb = $MaxPrivateGrowthMb
            maxHandleGrowthAllowed = $MaxHandleGrowth
        }
        broker = [ordered]@{
            lastPid = if ($lastBrokerPid -gt 0) { $lastBrokerPid } else { $null }
            restarts = $brokerRestarts
            maxRestartsAllowed = $MaxBrokerRestarts
            maxWorkingSetMb = $maxBrokerWorkingSetMb
            maxPrivateMb = $maxBrokerPrivateMb
            maxHandles = $maxBrokerHandles
        }
        session = [ordered]@{
            pathConfigured = -not [string]::IsNullOrWhiteSpace($sessionPath)
            everSeen = $sessionSeen
            validSamples = $sessionValidSamples
            invalidSamples = $sessionInvalidSamples
            missingSamples = $sessionMissingSamples
            maxConsecutiveInvalidAllowed = $MaxConsecutiveInvalidSessionSamples
        }
        failures = @($failures)
        evidence = [ordered]@{
            samplesCsv = [IO.Path]::GetFileName($csvPath)
            eventsLog = [IO.Path]::GetFileName($eventsPath)
            liveStatus = [IO.Path]::GetFileName($livePath)
        }
    }

    Write-JsonAtomic -Value $summary -Path $summaryPath
    Write-SoakEvent "verdict=$verdict samples=$sampleCount duration=$([math]::Round(($endedAt - $startedAt).TotalMinutes, 2))min evidence=$OutputDirectory"

    if ($launchedByHarness -and $StopLaunchedProcessOnExit) {
        $owned = Get-ProcessByIdSafe -Id $shellPid
        if ($null -ne $owned) {
            try {
                Stop-Process -Id $shellPid -Force -ErrorAction Stop
                Write-SoakEvent "stopped harness-owned CloudOS PID $shellPid"
            }
            catch {
                Write-SoakEvent "warning: failed to stop harness-owned PID $shellPid ($($_.Exception.GetType().Name))"
            }
        }
    }
}

if ($verdict -eq 'pass') { exit 0 }
if ($verdict -eq 'incomplete') { exit 2 }
exit 1
