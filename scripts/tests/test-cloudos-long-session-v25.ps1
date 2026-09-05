# scripts/tests/test-cloudos-long-session-v25.ps1
# Long Session & Monotonic Growth Benchmark (Fase A - Estabilizacao)

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$probeExe = Join-Path $root 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\CloudOS.BrokerProbe.exe'
if (!(Test-Path $probeExe)) {
    $probeExe = Join-Path $root 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.BrokerProbe.exe'
}
$conptyProbeExe = "C:\Users\dougl\.gemini\antigravity\brain\e0ea3935-20e3-4f15-a2a8-79266b2d4907\scratch\cloudos_conpty_probe.exe"
$sandboxDir = Join-Path $env:TEMP 'CloudOS_LongSession_Sandbox'
if (Test-Path $sandboxDir) { Remove-Item $sandboxDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $sandboxDir -Force | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WinMetrics {
    [DllImport("user32.dll")]
    public static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);
}
'@

$procNames = @('CloudOS', 'CloudOS.Supervisor', 'CloudOS.SystemBroker', 'cloudos_flutter_shell')

function Get-ProcessSnapshot {
    $snap = @()
    foreach ($name in $procNames) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            $gdi = 0
            $user = 0
            try {
                $gdi = [WinMetrics]::GetGuiResources($p.Handle, 0)
                $user = [WinMetrics]::GetGuiResources($p.Handle, 1)
            } catch {}

            $snap += [PSCustomObject]@{
                Id = $p.Id
                ProcessName = $p.ProcessName
                WS_MB = [math]::Round($p.WorkingSet64 / 1MB, 2)
                PM_MB = [math]::Round($p.PrivateMemorySize64 / 1MB, 2)
                Paged_MB = [math]::Round($p.PagedMemorySize64 / 1MB, 2)
                VM_MB = [math]::Round($p.VirtualMemorySize64 / 1MB, 2)
                CPU_S = [math]::Round($p.CPU, 2)
                Handles = $p.HandleCount
                Threads = $p.Threads.Count
                GDI = $gdi
                USER = $user
            }
        }
    }
    return $snap
}

function Print-SnapshotTable($title, $snap) {
    Write-Host "`n--- $title ---" -ForegroundColor Cyan
    $snap | Format-Table ProcessName, Id, WS_MB, PM_MB, CPU_S, Handles, Threads, GDI, USER -AutoSize | Out-String | Write-Host
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " CloudOS Long Session & Stability Benchmark (Fase A - 5 Ciclos)" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Baseline
$baseline = Get-ProcessSnapshot
Print-SnapshotTable "BASELINE" $baseline

$cycleReports = @()

# 2. Executar 5 ciclos de estresse
for ($cycle = 1; $cycle -le 5; $cycle++) {
    Write-Host "`n>>> [CICLO $cycle / 5] Iniciando bateria de acoes..." -ForegroundColor Yellow

    # Acao 1: Abrir Files -> Listar Drives -> Fechar Files
    Write-Host "  [$cycle.1] Files: abrir -> list-drives -> fechar" -ForegroundColor Gray
    if (Test-Path $probeExe) {
        & $probeExe invoke "app.launch" '{"appId":"cloudos:files"}' | Out-Null
        Start-Sleep -Milliseconds 400
        & $probeExe list-drives | Out-Null
        & $probeExe files "home" | Out-Null
        & $probeExe invoke "app.close" '{"appId":"cloudos:files"}' | Out-Null
    }
    Start-Sleep -Milliseconds 200

    # Acao 2: Terminal: abrir -> ConPTY probe -> fechar
    Write-Host "  [$cycle.2] Terminal: abrir -> ConPTY probe -> fechar" -ForegroundColor Gray
    if (Test-Path $probeExe) {
        & $probeExe invoke "app.launch" '{"appId":"cloudos:terminal"}' | Out-Null
    }
    if (Test-Path $conptyProbeExe) {
        $conProc = Start-Process -FilePath $conptyProbeExe -NoNewWindow -PassThru
        $null = $conProc.WaitForExit(1500)
        if (!$conProc.HasExited) { Stop-Process -Id $conProc.Id -Force -ErrorAction SilentlyContinue }
    }
    if (Test-Path $probeExe) {
        & $probeExe invoke "app.close" '{"appId":"cloudos:terminal"}' | Out-Null
    }
    Start-Sleep -Milliseconds 200

    # Acao 3: Browser: abrir -> fechar
    Write-Host "  [$cycle.3] Browser: abrir -> fechar" -ForegroundColor Gray
    if (Test-Path $probeExe) {
        & $probeExe invoke "app.launch" '{"appId":"cloudos:browser"}' | Out-Null
        Start-Sleep -Milliseconds 400
        & $probeExe invoke "app.close" '{"appId":"cloudos:browser"}' | Out-Null
    }
    Start-Sleep -Milliseconds 200

    # Acao 4: Settings: abrir -> fechar
    Write-Host "  [$cycle.4] Settings: abrir -> fechar" -ForegroundColor Gray
    if (Test-Path $probeExe) {
        & $probeExe invoke "app.launch" '{"appId":"cloudos:settings"}' | Out-Null
        Start-Sleep -Milliseconds 300
        & $probeExe invoke "app.close" '{"appId":"cloudos:settings"}' | Out-Null
    }
    Start-Sleep -Milliseconds 200

    # Acao 5: Start e Janelas: toggle Start / window snapshot
    Write-Host "  [$cycle.5] Start toggle / window.snapshot" -ForegroundColor Gray
    if (Test-Path $probeExe) {
        & $probeExe invoke "app.launch" '{"appId":"cloudos:start"}' | Out-Null
        Start-Sleep -Milliseconds 150
        & $probeExe invoke "app.close" '{"appId":"cloudos:start"}' | Out-Null
        & $probeExe window.list | Out-Null
        & $probeExe invoke "diagnostics.snapshot" '{}' | Out-Null
    }

    # Acao 6: Sandbox Copy / Move / Delete
    Write-Host "  [$cycle.6] Sandbox copy / move / delete" -ForegroundColor Gray
    $cycleFile = Join-Path $sandboxDir "test_file_$cycle.dat"
    $bytes = New-Object byte[] (2 * 1024 * 1024)
    [System.IO.File]::WriteAllBytes($cycleFile, $bytes)
    if (Test-Path $probeExe) {
        $resSrc = (& $probeExe resolve $cycleFile | ConvertFrom-Json).payload.entryId
        $resDst = (& $probeExe resolve $sandboxDir | ConvertFrom-Json).payload.entryId
        if ($resSrc -and $resDst) {
            $cp = & $probeExe copy $resSrc $resDst "replace" | ConvertFrom-Json
            if ($cp.payload.jobId) {
                Start-Sleep -Milliseconds 300
                & $probeExe jobs-get $cp.payload.jobId | Out-Null
            }
        }
    }
    Remove-Item $cycleFile -Force -ErrorAction SilentlyContinue

    # Medicao ao final do ciclo
    $cycleSnap = Get-ProcessSnapshot
    Print-SnapshotTable "CICLO $cycle" $cycleSnap
    $cycleReports += [PSCustomObject]@{
        Cycle = $cycle
        Snapshot = $cycleSnap
    }
    Start-Sleep -Milliseconds 500
}

# 3. Cooldown
Write-Host "`n>>> [COOLDOWN] Aguardando 5 segundos para estabilizacao de caches..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
[System.GC]::Collect()

$cooldown = Get-ProcessSnapshot
Print-SnapshotTable "POS-COOLDOWN (FINAL)" $cooldown

# 4. Calculo de deltas
Write-Host "`n=================================================================" -ForegroundColor Green
Write-Host " RESUMO COMPARATIVO: BASELINE vs CICLO 5 vs COOLDOWN" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green

$comparison = @()
foreach ($b in $baseline) {
    $c5 = $cycleReports[4].Snapshot | Where-Object { $_.ProcessName -eq $b.ProcessName -and $_.Id -eq $b.Id }
    $cd = $cooldown | Where-Object { $_.ProcessName -eq $b.ProcessName -and $_.Id -eq $b.Id }
    if ($c5 -and $cd) {
        $comparison += [PSCustomObject]@{
            Process = $b.ProcessName
            PID = $b.Id
            Base_WS = $b.WS_MB
            Cycle5_WS = $c5.WS_MB
            Cool_WS = $cd.WS_MB
            WS_Delta = [math]::Round($cd.WS_MB - $b.WS_MB, 2)
            Base_PM = $b.PM_MB
            Cool_PM = $cd.PM_MB
            PM_Delta = [math]::Round($cd.PM_MB - $b.PM_MB, 2)
            Base_Handles = $b.Handles
            Cool_Handles = $cd.Handles
            Handle_Delta = $cd.Handles - $b.Handles
            Base_Threads = $b.Threads
            Cool_Threads = $cd.Threads
            Thread_Delta = $cd.Threads - $b.Threads
            GDI_Delta = $cd.GDI - $b.GDI
            USER_Delta = $cd.USER - $b.USER
        }
    }
}

$comparison | Format-Table Process, PID, Base_WS, Cool_WS, WS_Delta, Base_PM, Cool_PM, PM_Delta, Base_Handles, Cool_Handles, Handle_Delta, Thread_Delta, GDI_Delta, USER_Delta -AutoSize | Out-String | Write-Host

# 5. Salvar relatorio JSON
$report = [ordered]@{
    Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    Baseline = $baseline
    Cycles = $cycleReports
    Cooldown = $cooldown
    Comparison = $comparison
}
$reportPath = Join-Path $PSScriptRoot 'long_session_report_v25.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $reportPath -Encoding utf8
Write-Host "Relatorio completo gravado em: $reportPath" -ForegroundColor Green
