param(
    [string]$Root = $(if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'CloudOS.exe')) { $PSScriptRoot } else { (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }),
    [string]$BuildDirectory,
    [string]$OutputPath,
    [ValidateRange(1, 120)][int]$StartupTimeoutSeconds = 30,
    [ValidateRange(1, 30)][int]$TransitionTimeoutSeconds = 8
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'native-health-v9.ps1')

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
    $OutputPath = Join-Path $base ('CloudOS\Diagnostics\lifecycle-v10-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.json')
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$parent = [IO.Path]::GetDirectoryName($OutputPath)
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
if (Test-Path -LiteralPath $OutputPath) { throw 'Lifecycle report destination already exists.' }

if (-not ('CloudOSLifecycleNativeV10' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CloudOSLifecycleNativeV10 {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint Msg,
        UIntPtr wParam,
        IntPtr lParam,
        uint fuFlags,
        uint uTimeout,
        out UIntPtr lpdwResult);
}
'@
}

$WM_APP = 0x8000
$ProbeSuspend = $WM_APP + 0x5A1
$ProbeResume = $WM_APP + 0x5A2
$ProbeDisplay = $WM_APP + 0x5A3
$ProbeSessionDisconnect = $WM_APP + 0x5A4
$ProbeSessionReconnect = $WM_APP + 0x5A5
$SMTO_ABORTIFHUNG = 0x0002

$failures = [Collections.Generic.List[string]]::new()
$events = [Collections.Generic.List[object]]::new()
$primary = $null
$secondary = $null
$ready = $null
$sessionStatePath = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'CloudOS\session_v3.dat' } else { $null }

function Get-FreshHealthV10 {
    param([int]$ExpectedPid)
    $health = Get-CloudOSHealthSnapshotV9
    if (-not $health) { throw 'HealthMappingMissing' }
    if ([int]$health.process_id -ne $ExpectedPid) { throw 'HealthProcessChanged' }
    if ([int]$health.state -ne 2) { throw ('HealthStateNotReady:' + $health.state) }
    if (-not (Test-CloudOSHeartbeatFreshV9 -Snapshot $health -MaximumAgeSeconds 5)) { throw 'UiHeartbeatStale' }
    return $health
}

function Wait-HeartbeatAdvanceV10 {
    param(
        [int]$ExpectedPid,
        [uint64]$PreviousCount,
        [int]$TimeoutSeconds
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $health = Get-FreshHealthV10 -ExpectedPid $ExpectedPid
        if ([uint64]$health.heartbeat_count -gt $PreviousCount) { return $health }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'HeartbeatDidNotAdvance'
}

function Send-LifecycleProbeV10 {
    param(
        [Parameter(Mandatory)][IntPtr]$Window,
        [Parameter(Mandatory)][uint32]$Message,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$ExpectedPid
    )
    $before = Get-FreshHealthV10 -ExpectedPid $ExpectedPid
    $nativeResult = [UIntPtr]::Zero
    $sent = [CloudOSLifecycleNativeV10]::SendMessageTimeout(
        $Window,
        $Message,
        [UIntPtr]::Zero,
        [IntPtr]::Zero,
        $SMTO_ABORTIFHUNG,
        3000,
        [ref]$nativeResult)
    if ($sent -eq [IntPtr]::Zero) { throw ("ProbeMessageTimeout:" + $Name) }
    if ($nativeResult.ToUInt64() -eq 0) { throw ("ProbeMessageRejected:" + $Name) }

    $after = Wait-HeartbeatAdvanceV10 -ExpectedPid $ExpectedPid -PreviousCount ([uint64]$before.heartbeat_count) -TimeoutSeconds $TransitionTimeoutSeconds
    $events.Add([ordered]@{
        name = $Name
        heartbeat_before = [uint64]$before.heartbeat_count
        heartbeat_after = [uint64]$after.heartbeat_count
        process_id = [int]$after.process_id
    })
    return $after
}

try {
    if (Get-CloudOSHealthSnapshotV9) {
        throw 'A CloudOS health block already exists in this session. Close the running shell before lifecycle validation.'
    }

    $primary = Start-Process -FilePath $exe -WorkingDirectory $out -ArgumentList @('--stability-probe', '--lifecycle-probe') -PassThru
    $ready = Wait-CloudOSReadyV9 -TimeoutSeconds $StartupTimeoutSeconds -ExpectedProcessId $primary.Id
    if (-not $ready) {
        if ($primary.HasExited) { throw "PrimaryExitedBeforeReady:$($primary.ExitCode)" }
        throw 'PrimaryDidNotReachReady'
    }
    if ([uint64]$ready.main_window_value -eq 0) { throw 'PrimaryDesktopHandleMissing' }
    $desktop = [IntPtr]([int64][uint64]$ready.main_window_value)

    # The named session mutex is a product invariant. A second normal launch in
    # the same user/session must surface the first shell and exit without ever
    # replacing the health PID.
    $secondary = Start-Process -FilePath $exe -WorkingDirectory $out -ArgumentList @('--stability-probe', '--lifecycle-probe') -PassThru
    if (-not $secondary.WaitForExit(6000)) {
        throw 'SecondInstanceDidNotExit'
    }
    $postSecond = Get-FreshHealthV10 -ExpectedPid $primary.Id
    if ($primary.HasExited) { throw 'PrimaryExitedDuringSecondInstanceCheck' }
    $events.Add([ordered]@{
        name = 'single-instance'
        primary_pid = $primary.Id
        secondary_pid = $secondary.Id
        secondary_exit_code = $secondary.ExitCode
        health_pid = [int]$postSecond.process_id
    })

    $stateBefore = if ($sessionStatePath -and (Test-Path -LiteralPath $sessionStatePath)) {
        (Get-Item -LiteralPath $sessionStatePath).LastWriteTimeUtc.Ticks
    } else { 0L }

    $current = Send-LifecycleProbeV10 -Window $desktop -Message $ProbeSuspend -Name 'suspend-checkpoint' -ExpectedPid $primary.Id
    $current = Send-LifecycleProbeV10 -Window $desktop -Message $ProbeResume -Name 'resume-revalidate' -ExpectedPid $primary.Id
    $current = Send-LifecycleProbeV10 -Window $desktop -Message $ProbeDisplay -Name 'display-revalidate' -ExpectedPid $primary.Id
    $current = Send-LifecycleProbeV10 -Window $desktop -Message $ProbeSessionDisconnect -Name 'session-disconnect-checkpoint' -ExpectedPid $primary.Id
    $current = Send-LifecycleProbeV10 -Window $desktop -Message $ProbeSessionReconnect -Name 'session-reconnect-revalidate' -ExpectedPid $primary.Id

    if ($sessionStatePath) {
        if (-not (Test-Path -LiteralPath $sessionStatePath -PathType Leaf)) {
            throw 'SessionCheckpointMissing'
        }
        $stateItem = Get-Item -LiteralPath $sessionStatePath
        if ($stateItem.Length -lt 12) { throw 'SessionCheckpointTooSmall' }
        $events.Add([ordered]@{
            name = 'checkpoint-file'
            exists = $true
            bytes = [int64]$stateItem.Length
            write_ticks_before = [int64]$stateBefore
            write_ticks_after = [int64]$stateItem.LastWriteTimeUtc.Ticks
        })
    }

    $final = Get-FreshHealthV10 -ExpectedPid $primary.Id
    if ([int]$final.process_id -ne $primary.Id) { throw 'PrimaryPidChanged' }
}
catch {
    $failures.Add($_.Exception.Message)
}
finally {
    if ($secondary -and -not $secondary.HasExited) {
        try { Stop-Process -Id $secondary.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    if ($primary -and -not $primary.HasExited) {
        try {
            Stop-Process -Id $primary.Id -Force -ErrorAction SilentlyContinue
            [void]$primary.WaitForExit(5000)
        } catch {}
    }
}

$report = [ordered]@{
    schema = 10
    test = 'CloudOS Lifecycle V10'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    verdict = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    coverage = 'Hosted Windows smoke: same-session single-instance plus deterministic lifecycle handlers. Physical suspend/resume, RDP transport and monitor hotplug remain VM/hardware matrix tests.'
    privacy = 'Process IDs, health counters and checkpoint file metadata only. No window titles, document paths, command lines, URLs, credentials, dumps or uploads.'
    primary_process_id = if ($primary) { $primary.Id } else { 0 }
    startup_timeout_seconds = $StartupTimeoutSeconds
    transition_timeout_seconds = $TransitionTimeoutSeconds
    failures = $failures.ToArray()
    events = $events.ToArray()
}

$json = $report | ConvertTo-Json -Depth 10
$stream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }

if ($failures.Count -gt 0) {
    Write-Error "FAIL: Lifecycle V10 failed: $($failures -join ', '). Report: $OutputPath"
    exit 1
}

Write-Host "PASS: Lifecycle V10 validated single-instance and five lifecycle transitions. Report: $OutputPath"
