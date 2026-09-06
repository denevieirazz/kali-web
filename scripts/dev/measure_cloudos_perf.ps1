$root = if ($PSScriptRoot) { (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path } else { (Get-Location).Path }
$releaseDir = Join-Path $root 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release'
$exePath = Join-Path $releaseDir 'cloudos_flutter_shell.exe'

$proc = Start-Process -FilePath $exePath -WorkingDirectory $releaseDir -PassThru
Start-Sleep -Seconds 5

Write-Output "=== CloudOS Process Telemetry ==="
$names = @('CloudOS', 'CloudOS.Supervisor', 'CloudOS.SystemBroker', 'cloudos_flutter_shell')
$procs = Get-Process -Name $names -ErrorAction SilentlyContinue

$procs | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.ProcessName
        PID = $_.Id
        WorkingSetMB = [Math]::Round($_.WorkingSet64 / 1MB, 2)
        Threads = $_.Threads.Count
        Handles = $_.HandleCount
    }
} | Format-Table -AutoSize

Write-Output "=== 3-Second Idle CPU Measurement ==="
$cput0 = @{}
foreach ($p in $procs) {
    $cput0[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds
}

Start-Sleep -Seconds 3

foreach ($p in $procs) {
    $live = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
    if ($live) {
        $deltaMs = $live.TotalProcessorTime.TotalMilliseconds - $cput0[$p.Id]
        $cores = [Environment]::ProcessorCount
        $pct = [Math]::Round(($deltaMs / 3000.0) * 100.0 / $cores, 2)
        Write-Output ("{0,-24} (PID {1,6}): {2,5}% CPU idle average" -f $live.ProcessName, $live.Id, $pct)
    }
}

Write-Output "=== WSL Background State ==="
$wslProcs = Get-Process -Name *wslhost*, *wslrelay* -ErrorAction SilentlyContinue
if ($null -eq $wslProcs) {
    Write-Output "WSL user session: ZERO instances active (lazy start honored)"
} else {
    Write-Output ("WSL instances: " + ($wslProcs.Name -join ', '))
}

Get-Process -Name $names -ErrorAction SilentlyContinue | Stop-Process -Force
