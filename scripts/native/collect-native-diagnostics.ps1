param(
    [string]$Root = $(if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'cloudos-native-manifest.json')) { $PSScriptRoot } else { (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }),
    [string]$OutputPath,
    [ValidateRange(0, 3600)][int]$SampleSeconds = 0,
    [ValidateRange(1, 60)][int]$IntervalSeconds = 5
)
$ErrorActionPreference = 'Stop'

$healthHelper = Join-Path $PSScriptRoot 'native-health-v9.ps1'
if (Test-Path -LiteralPath $healthHelper) { . $healthHelper }

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$out = if (Test-Path -LiteralPath (Join-Path $rootPath 'cloudos-native-manifest.json')) { $rootPath } else { Join-Path $rootPath 'desktop\CloudOS.NativeShell\bin\Release' }
if (-not $OutputPath) {
    $OutputPath = Join-Path $env:LOCALAPPDATA ('CloudOS\Diagnostics\native-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.json')
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw 'Diagnostic destination already exists; choose a new file.' }
New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($OutputPath)) -Force | Out-Null

$os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$manifestPath = Join-Path $out 'cloudos-native-manifest.json'
$build = $null
$buildError = $null
if (Test-Path -LiteralPath $manifestPath) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $build = [ordered]@{
            git_head = if ($manifest.git_head -is [string] -and $manifest.git_head -cmatch '^[a-f0-9]{40}$') { $manifest.git_head } else { $null }
            fingerprint = if ($manifest.source_fingerprint_sha256 -is [string] -and $manifest.source_fingerprint_sha256 -cmatch '^[a-f0-9]{64}$') { $manifest.source_fingerprint_sha256 } else { $null }
            source_tree_dirty = if ($manifest.source_tree_dirty -is [bool]) { $manifest.source_tree_dirty } else { $null }
            supervisor_runtime_schema = if ($null -ne $manifest.supervisor_runtime_schema) { [int]$manifest.supervisor_runtime_schema } else { $null }
        }
    } catch {
        $buildError = 'ManifestUnreadable'
    }
}

$artifacts = foreach ($name in @(
    'CloudOS.exe',
    'CloudOS.NativeRuntime.dll',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe'
)) {
    $path = Join-Path $out $name
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    [ordered]@{
        name = $name
        exists = $exists
        bytes = if ($exists) { (Get-Item -LiteralPath $path).Length } else { 0 }
        sha256 = if ($exists) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
        authenticode_status = if ($exists) { (Get-AuthenticodeSignature -LiteralPath $path).Status.ToString() } else { 'Missing' }
    }
}

# Supervisor V22 owns a small allowlisted state journal. Diagnostics deliberately
# excludes the free-form reason string and never copies process command lines.
$supervisorState = $null
$supervisorStateError = $null
$supervisorStatePath = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $null
} else {
    Join-Path $env:LOCALAPPDATA 'CloudOS\Recovery\supervisor-state-v22.json'
}
if ($supervisorStatePath -and (Test-Path -LiteralPath $supervisorStatePath -PathType Leaf)) {
    try {
        $rawSupervisorState = Get-Content -LiteralPath $supervisorStatePath -Raw | ConvertFrom-Json
        $allowedStates = @('STARTING', 'HEALTHY', 'DEGRADED', 'RESTARTING', 'CRASH_LOOP', 'SAFE_MODE', 'STOPPING')
        $stateName = [string]$rawSupervisorState.state
        $supervisorState = [ordered]@{
            schema = if ($null -ne $rawSupervisorState.schema) { [int]$rawSupervisorState.schema } else { $null }
            state = if ($allowedStates -contains $stateName) { $stateName } else { 'UNKNOWN' }
            shell_pid = if ($null -ne $rawSupervisorState.shell_pid) { [int]$rawSupervisorState.shell_pid } else { 0 }
            failure_count = if ($null -ne $rawSupervisorState.failure_count) { [int]$rawSupervisorState.failure_count } else { 0 }
            last_exit_code = if ($null -ne $rawSupervisorState.last_exit_code) { [uint32]$rawSupervisorState.last_exit_code } else { 0 }
            job_kill_on_close_assigned = if ($rawSupervisorState.job_kill_on_close_assigned -is [bool]) { [bool]$rawSupervisorState.job_kill_on_close_assigned } else { $null }
            updated_utc = if ($rawSupervisorState.updated_utc -is [string]) { [string]$rawSupervisorState.updated_utc } else { $null }
        }
    } catch {
        $supervisorStateError = 'SupervisorStateUnreadable'
    }
}

$samples = [Collections.Generic.List[object]]::new()
$session = [Diagnostics.Process]::GetCurrentProcess().SessionId
$timer = [Diagnostics.Stopwatch]::StartNew()
do {
    $health = $null
    if (Get-Command Get-CloudOSHealthSnapshotV9 -ErrorAction SilentlyContinue) {
        try { $health = Get-CloudOSHealthSnapshotV9 } catch { $health = $null }
    }

    $processes = @(Get-Process -Name CloudOS -ErrorAction SilentlyContinue | Where-Object {
        $_.SessionId -eq $session -and $_.Path -eq (Join-Path $out 'CloudOS.exe')
    })
    $metrics = foreach ($process in $processes) {
        try {
            $isHealthOwner = $health -and [int]$health.process_id -eq $process.Id
            [ordered]@{
                pid = $process.Id
                cpu_seconds = $process.TotalProcessorTime.TotalSeconds
                working_set_bytes = $process.WorkingSet64
                private_bytes = $process.PrivateMemorySize64
                threads = $process.Threads.Count
                handles = $process.HandleCount
                responding = $process.Responding
                health_state = if ($isHealthOwner) { [int]$health.state } else { $null }
                heartbeat_count = if ($isHealthOwner) { [uint64]$health.heartbeat_count } else { $null }
                heartbeat_tick_ms = if ($isHealthOwner) { [uint64]$health.heartbeat_tick_ms } else { $null }
                gdi_objects = if ($isHealthOwner) { [int]$health.gdi_objects } else { $null }
                user_objects = if ($isHealthOwner) { [int]$health.user_objects } else { $null }
                health_handles = if ($isHealthOwner) { [int]$health.handle_count } else { $null }
            }
        } catch { [ordered]@{ pid = $process.Id; exited_during_sample = $true } }
    }
    $samples.Add([ordered]@{ elapsed_seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3); processes = @($metrics) })
    if ($timer.Elapsed.TotalSeconds -ge $SampleSeconds) { break }
    Start-Sleep -Milliseconds ([int](1000 * [Math]::Min($IntervalSeconds, $SampleSeconds - $timer.Elapsed.TotalSeconds)))
} while ($true)

$report = [ordered]@{
    schema = 2
    collected_utc = [DateTime]::UtcNow.ToString('o')
    privacy = 'Allowlisted local metadata only. No window titles, filenames from user folders, command lines, URLs, credentials, session contents, logs, Supervisor reason text or memory dumps. No upload.'
    windows = [ordered]@{ build = $os.CurrentBuild; revision = $os.UBR; display_version = $os.DisplayVersion }
    logical_processors = [Environment]::ProcessorCount
    build = $build
    build_error = $buildError
    artifacts = @($artifacts)
    supervisor = $supervisorState
    supervisor_error = $supervisorStateError
    health_schema = 9
    samples = $samples.ToArray()
}
$json = $report | ConvertTo-Json -Depth 10
$stream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }
Write-Host "PASS: local diagnostics V22 saved ($($samples.Count) samples). No data uploaded."
