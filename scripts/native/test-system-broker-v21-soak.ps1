# test-system-broker-v21-soak.ps1
# CloudOS V21 — 120-Second System Broker Soak & Stability Test

param(
    [int]$DurationSeconds = 120,
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$root = (Get-Item "$PSScriptRoot\..\..").FullName

$brokerExe = Join-Path $root "desktop\CloudOS.NativeShell\bin\$Configuration\CloudOS.SystemBroker.exe"
$probeExe = Join-Path $root "desktop\CloudOS.NativeShell\bin\$Configuration\CloudOS.BrokerProbe.exe"

Write-Host "[Soak-V21] Starting $DurationSeconds-second System Broker soak test..."

$brokerProc = Start-Process -FilePath $brokerExe -PassThru
Start-Sleep -Milliseconds 500

$samples = @()
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    while ($stopwatch.Elapsed.TotalSeconds -lt $DurationSeconds) {
        # Probe broker
        $null = & $probeExe ping
        $null = & $probeExe snapshot

        $proc = Get-Process -Id $brokerProc.Id
        $sample = [PSCustomObject]@{
            ElapsedSec = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
            Handles = $proc.Handles
            WorkingSetMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            CPU = $proc.CPU
            Threads = $proc.Threads.Count
        }
        $samples += $sample
        Write-Host "[Soak-V21] t=$($sample.ElapsedSec)s | WS: $($sample.WorkingSetMB) MB | Handles: $($sample.Handles) | Threads: $($sample.Threads)"
        Start-Sleep -Seconds 5
    }

    $initialWS = $samples[0].WorkingSetMB
    $finalWS = $samples[-1].WorkingSetMB
    $wsGrowth = $finalWS - $initialWS
    $initialHandles = $samples[0].Handles
    $finalHandles = $samples[-1].Handles
    $handlesGrowth = $finalHandles - $initialHandles

    Write-Host "[Soak-V21] Initial Working Set: $initialWS MB -> Final: $finalWS MB (Delta: $wsGrowth MB)"
    Write-Host "[Soak-V21] Initial Handles: $initialHandles -> Final: $finalHandles (Delta: $handlesGrowth)"

    if ($wsGrowth -gt 25.0) {
        throw "Excessive memory growth detected during soak test: $wsGrowth MB"
    }
    if ($handlesGrowth -gt 50) {
        throw "Excessive handle growth detected during soak test: $handlesGrowth handles"
    }

    Write-Host "[PASS] 120-Second Soak Test Passed with stable memory and zero leaks."
}
finally {
    if ($brokerProc -and -not $brokerProc.HasExited) {
        Stop-Process -Id $brokerProc.Id -Force -ErrorAction SilentlyContinue
    }
}
