param(
    [string]$Root=$(if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'CloudOS.exe')){$PSScriptRoot}else{(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path}),
    [string]$BuildDirectory,
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateRange(20,3600)][int]$DurationSeconds=120,
    # V9/V10 smoke runs may leave a deliberate unclean-session marker because
    # their harnesses force-stop owned probes. Give V12 enough time for the
    # one-time continuity restore and asynchronous icon/model publication to
    # settle before the 120-second idle baseline begins.
    [ValidateRange(0,120)][int]$WarmupSeconds=45,
    [double]$MaxAverageCpuPercent=1.0
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'native-health-v9.ps1')
. (Join-Path $PSScriptRoot 'native-performance-v12.ps1')
if(Test-Path -LiteralPath $OutputPath){throw 'Evidence destination already exists.'}
if(Get-CloudOSHealthSnapshotV9){throw 'Close the running CloudOS before starting an isolated performance probe.'}
if(-not $BuildDirectory){$BuildDirectory=if(Test-Path -LiteralPath (Join-Path $Root 'CloudOS.exe')){$Root}else{Join-Path $Root 'desktop/CloudOS.NativeShell/bin/Release'}}
$exe=Join-Path $BuildDirectory 'CloudOS.exe'
if(-not ('NativePerformanceProbeV12' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NativePerformanceProbeV12 {
    [DllImport("user32.dll",SetLastError=true)] public static extern bool PostMessage(IntPtr hwnd,uint message,UIntPtr wp,IntPtr lp);
}
'@
}
$failures=[Collections.Generic.List[string]]::new()
$samples=[Collections.Generic.List[object]]::new()
$owned=$null; $ready=$null; $baseline=$null; $summary=$null
try {
    $owned=Start-Process -FilePath $exe -WorkingDirectory $BuildDirectory -ArgumentList '--stability-probe' -WindowStyle Hidden -PassThru
    $ready=Wait-CloudOSReadyV9 -ExpectedProcessId $owned.Id -TimeoutSeconds 30
    if(-not $ready){throw 'ReadinessTimeout'}
    $target=[IntPtr][long]$ready.main_window_value
    # This message is recognized only by a --stability-probe process. No input
    # injection, system settings, application launches, or real file operations.
    foreach($action in @(1,2,3)) {
        if(-not [NativePerformanceProbeV12]::PostMessage($target,0x861B,[UIntPtr]$action,[IntPtr]::Zero)){throw 'ProbePostFailed'}
        Start-Sleep -Milliseconds 1000
    }
    for($second=0;$second -lt $WarmupSeconds;$second++){Start-Sleep -Seconds 1}
    # Hosted runners can deliver one-time recovery/display notifications after
    # the fixed warmup. Start the idle baseline only after ten quiet seconds;
    # events after that gate remain failures.
    $quiet = 0; $previousQuiet = Get-CloudOSPerformanceV12 $owned.Id
    for($settle=0; $settle -lt 120 -and $quiet -lt 10; $settle++) {
        Start-Sleep -Seconds 1
        $currentQuiet = Get-CloudOSPerformanceV12 $owned.Id
        $changedQuiet = $false
        foreach($name in @('desktop_full_paint','taskbar_full_paint','refresh_shell','reconcile')) {
            if($currentQuiet.$name -ne $previousQuiet.$name) { $changedQuiet = $true; break }
        }
        $quiet = if($changedQuiet) { 0 } else { $quiet + 1 }
        $previousQuiet = $currentQuiet
    }
    if($quiet -lt 10) { throw 'StartupDidNotSettle' }
    # A hosted desktop can dispatch the already-queued restore/display messages
    # immediately after the quiet probe. This short transition is reported as
    # startup time and is excluded from the idle counters; recurring work after
    # it remains a failure.
    Start-Sleep -Seconds 10
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do {
        $health=Get-CloudOSHealthSnapshotV9
        if(-not $health -or $health.process_id -ne $owned.Id -or $health.state -ne 2){throw 'HealthLost'}
        if(-not (Test-CloudOSHeartbeatFreshV9 -Snapshot $health)){throw 'HeartbeatStale'}
        $process=Get-Process -Id $owned.Id; $process.Refresh()
        $sample=[pscustomobject][ordered]@{
            elapsed_seconds=$clock.Elapsed.TotalSeconds
            cpu_seconds=$process.TotalProcessorTime.TotalSeconds
            working_set_bytes=$process.WorkingSet64
            private_bytes=$process.PrivateMemorySize64
            handles=$process.HandleCount
            gdi_objects=$health.gdi_objects
            user_objects=$health.user_objects
            heartbeat_count=$health.heartbeat_count
            performance=Get-CloudOSPerformanceV12 $owned.Id
        }
        $samples.Add($sample)
        if(-not $baseline){$baseline=$sample}
        if($clock.Elapsed.TotalSeconds -ge $DurationSeconds){break}
        Start-Sleep -Seconds 1
    }while($true)
    $last=$samples[$samples.Count-1]
    $duration=$last.elapsed_seconds-$baseline.elapsed_seconds
    $cpu=100*($last.cpu_seconds-$baseline.cpu_seconds)/$duration/[Environment]::ProcessorCount
    $delta=[ordered]@{}
    foreach($name in $script:PerformanceNamesV12[0..12]) { $delta[$name]=$last.performance.$name-$baseline.performance.$name }
    if($delta.icon_load_in_paint -ne 0){$failures.Add('IconIoInPaint')}
    if($delta.start_paint -ne 0 -or $delta.quick_paint -ne 0){$failures.Add('HiddenFlyoutPaint')}
    if($delta.reconcile -ne 0){$failures.Add('IdleReconcile')}
    if($last.performance.start_open_us -le 0 -or $last.performance.quick_open_us -le 0){$failures.Add('MissingOpenMeasurements')}
    if($MaxAverageCpuPercent -gt 0 -and $cpu -gt $MaxAverageCpuPercent){$failures.Add('CpuBudgetExceeded')}
    $summary=[ordered]@{
        ready_latency_ms=$ready.ready_tick_ms-$ready.started_tick_ms
        duration_seconds=[Math]::Round($duration,3)
        sample_count=$samples.Count
        average_cpu_percent=[Math]::Round($cpu,4)
        max_working_set_bytes=($samples | Measure-Object working_set_bytes -Maximum).Maximum
        max_private_bytes=($samples | Measure-Object private_bytes -Maximum).Maximum
        handle_growth=($samples | Measure-Object handles -Maximum).Maximum-$baseline.handles
        gdi_growth=($samples | Measure-Object gdi_objects -Maximum).Maximum-$baseline.gdi_objects
        user_growth=($samples | Measure-Object user_objects -Maximum).Maximum-$baseline.user_objects
        idle_counter_delta=$delta
        start_show_to_first_paint_ms=$last.performance.start_open_us/1000.0
        quick_show_to_first_paint_ms=$last.performance.quick_open_us/1000.0
    }
    if($summary.handle_growth -gt 64 -or $summary.gdi_growth -gt 16 -or $summary.user_growth -gt 16){$failures.Add('ResourceGrowthBudgetExceeded')}
    if($delta.filesystem_scan -ne 0){$failures.Add('IdleDesktopScan')}
    if($delta.desktop_full_paint -ne 0){$failures.Add('IdleDesktopFullPaint')}
    if($delta.backbuffer_allocation -ne 0){$failures.Add('IdleBufferAllocation')}

} catch { $failures.Add($_.Exception.Message) }
finally {
    if($owned -and -not $owned.HasExited) {
        if($ready){[void][NativePerformanceProbeV12]::PostMessage([IntPtr][long]$ready.main_window_value,0x85B1,[UIntPtr]::Zero,[IntPtr]::Zero)}
        if(-not $owned.WaitForExit(10000)){$failures.Add('GracefulExitTimeout');Stop-Process -Id $owned.Id -Force}
    }
}
$report=[ordered]@{
    schema=12; verdict=$(if($failures.Count){'fail'}else{'pass'})
    collected_utc=[DateTime]::UtcNow.ToString('o'); warmup_seconds=$WarmupSeconds; quiet_window_seconds=10; startup_transition_seconds=10
    privacy='Numeric local telemetry only; no titles, user filenames, media, network identifiers or uploads.'
    measurement='Process CPU normalized by logical processor count. First-paint latency excludes compositor presentation. Shared numeric counters are individually atomic, not a transactional frame snapshot. Paint timings include native media child/cards where applicable.'
    executable_sha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    summary=$summary;failures=$failures.ToArray();samples=$samples.ToArray()
}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));[void][IO.Directory]::CreateDirectory($parent)
$json=$report | ConvertTo-Json -Depth 12
$stream=[IO.File]::Open($OutputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
try{$bytes=[Text.Encoding]::UTF8.GetBytes($json);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
if($failures.Count){throw "V12 smoke failed: $($failures -join ', ')"}
Write-Host "PASS: Performance V12, $($summary.duration_seconds)s, CPU $($summary.average_cpu_percent)%. Report: $OutputPath"
