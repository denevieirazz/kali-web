<#
.SYNOPSIS
    Coletor de metricas de Long Soak para o CloudOS RC1.4
    Grava metricas continuas em docs/qa-data/rc14-soak.csv
#>
[CmdletBinding()]
param(
    [string]$OutputFile = "docs/qa-data/rc14-soak.csv",
    [int]$IntervalSeconds = 60,
    [int]$MaxIterations = 0 # 0 = infinito ate cancelamento
)

$ErrorActionPreference = 'SilentlyContinue'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$csvPath = if ([System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile } else { Join-Path $repoRoot $OutputFile }
$csvDir = Split-Path -Parent $csvPath
if (-not (Test-Path -LiteralPath $csvDir)) {
    New-Item -ItemType Directory -Path $csvDir -Force | Out-Null
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class CloudOSSoakProbe {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpfn, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    public static Dictionary<uint, int> GetProcessHwndCounts() {
        var counts = new Dictionary<uint, int>();
        EnumWindows((hWnd, lParam) => {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid != 0) {
                if (!counts.ContainsKey(pid)) counts[pid] = 0;
                counts[pid]++;
            }
            return true;
        }, IntPtr.Zero);
        return counts;
    }
}
'@

$header = "Timestamp,SampleIndex,ProcessName,PID,Responding,WorkingSet_MB,PrivateBytes_MB,VirtualMemory_MB,Handles,Threads,HWND_Count,CPU_Time_Sec"
Set-Content -LiteralPath $csvPath -Value $header -Encoding UTF8

$coreNames = @('CloudOS', 'CloudOS.Supervisor', 'CloudOS.SystemBroker', 'cloudos_flutter_shell')
$iteration = 0

Write-Host "[Soak Monitor RC1.4] Iniciando coleta continua em $csvPath (intervalo: ${IntervalSeconds}s)..." -ForegroundColor Cyan

while ($true) {
    $iteration++
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    $hwndMap = [CloudOSSoakProbe]::GetProcessHwndCounts()
    $targetProcesses = [System.Collections.Generic.List[object]]::new()

    # 1. Processos core
    $cores = Get-Process -Name $coreNames -ErrorAction SilentlyContinue
    if ($cores) {
        foreach ($c in $cores) { $targetProcesses.Add($c) }
    }

    # 2. Processos WebView2 pertencentes ao CloudOS
    $webviews = Get-CimInstance Win32_Process -Filter "Name = 'msedgewebview2.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -match 'cloudos_flutter_shell'
    }
    if ($webviews) {
        foreach ($wv in $webviews) {
            $p = Get-Process -Id $wv.ProcessId -ErrorAction SilentlyContinue
            if ($p) { $targetProcesses.Add($p) }
        }
    }

    if ($targetProcesses.Count -gt 0) {
        foreach ($proc in $targetProcesses) {
            try {
                $pidVal = $proc.Id
                $pName = $proc.ProcessName
                $resp = $proc.Responding
                $wsMb = [math]::Round($proc.WorkingSet64 / 1MB, 2)
                $pbMb = [math]::Round($proc.PrivateMemorySize64 / 1MB, 2)
                $vmMb = [math]::Round($proc.VirtualMemorySize64 / 1MB, 2)
                $handles = $proc.HandleCount
                $threads = $proc.Threads.Count
                $cpuSec = [math]::Round($proc.TotalProcessorTime.TotalSeconds, 2)
                $hwndCount = if ($hwndMap.ContainsKey([uint32]$pidVal)) { $hwndMap[[uint32]$pidVal] } else { 0 }

                $row = "$now,$iteration,$pName,$pidVal,$resp,$wsMb,$pbMb,$vmMb,$handles,$threads,$hwndCount,$cpuSec"
                Add-Content -LiteralPath $csvPath -Value $row -Encoding UTF8
            } catch {
                # Processo pode ter finalizado durante leitura
            }
        }
    } else {
        $row = "$now,$iteration,NONE,0,False,0,0,0,0,0,0,0"
        Add-Content -LiteralPath $csvPath -Value $row -Encoding UTF8
    }

    if ($MaxIterations -gt 0 -and $iteration -ge $MaxIterations) {
        break
    }

    Start-Sleep -Seconds $IntervalSeconds
}
Write-Host "[Soak Monitor RC1.4] Coleta concluida ($iteration amostras)." -ForegroundColor Green
