[CmdletBinding()]
param(
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$statePath = Join-Path $env:LOCALAPPDATA 'CloudOS\Recovery\supervisor-state-v22.json'
$state = $null
$stateError = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
        $candidate = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ([int]$candidate.schema -ne 22 -or [string]$candidate.component -ne 'CloudOS.Supervisor') {
            throw 'schema/component mismatch'
        }
        $state = $candidate
    }
    catch {
        $stateError = 'SupervisorStateUnreadable'
    }
}

$sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
$runtime = New-Object System.Collections.Generic.List[object]
foreach ($name in @(
    'CloudOS',
    'CloudOS.Supervisor',
    'CloudOS.SystemBroker',
    'CloudOS.BrokerProbe',
    'cloudos_flutter_shell'
)) {
    foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
        try {
            if ($process.SessionId -ne $sessionId) { continue }
            $runtime.Add([pscustomobject]@{
                name = $process.ProcessName
                pid = $process.Id
                responding = [bool]$process.Responding
                working_set_bytes = [Int64]$process.WorkingSet64
                handles = [int]$process.HandleCount
                threads = [int]$process.Threads.Count
            })
        }
        catch {
            # A process can exit between enumeration and sampling. That is normal.
        }
    }
}

$werRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps'
$wer = New-Object System.Collections.Generic.List[object]
foreach ($exe in @(
    'CloudOS.exe',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'cloudos_flutter_shell.exe'
)) {
    $key = Join-Path $werRoot $exe
    if (-not (Test-Path -LiteralPath $key)) {
        $wer.Add([pscustomobject]@{
            executable = $exe
            configured = $false
            dump_type = $null
            dump_count = $null
        })
        continue
    }

    try {
        $values = Get-ItemProperty -LiteralPath $key
        $wer.Add([pscustomobject]@{
            executable = $exe
            configured = $true
            dump_type = if ($null -ne $values.DumpType) { [int]$values.DumpType } else { $null }
            dump_count = if ($null -ne $values.DumpCount) { [int]$values.DumpCount } else { $null }
        })
    }
    catch {
        $wer.Add([pscustomobject]@{
            executable = $exe
            configured = $true
            dump_type = $null
            dump_count = $null
        })
    }
}

$report = [ordered]@{
    schema = 22
    component = 'CloudOS.RecoveryStatus'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    privacy = 'Local operational metadata only. No command lines, window titles, URLs, file contents, credentials or dump contents are read or uploaded.'
    supervisor_state_present = ($null -ne $state)
    supervisor_state_error = $stateError
    supervisor = if ($null -ne $state) {
        [ordered]@{
            state = [string]$state.state
            reason = [string]$state.reason
            shell_pid = [int]$state.shell_pid
            failure_count = [int]$state.failure_count
            last_exit_code = [uint32]$state.last_exit_code
            job_kill_on_close_assigned = [bool]$state.job_kill_on_close_assigned
            updated_utc = [string]$state.updated_utc
        }
    } else { $null }
    current_session_runtime = @($runtime)
    wer_local_dumps = @($wer)
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $full = [IO.Path]::GetFullPath($OutputPath)
    $directory = Split-Path -Parent $full
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $temporary = $full + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $json = $report | ConvertTo-Json -Depth 10
        [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $full -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

$report
