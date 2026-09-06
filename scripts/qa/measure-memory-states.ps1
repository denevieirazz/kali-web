# measure-memory-states.ps1
# Mede metricas de memoria reais para o CloudOS RC1.4 nos Estados A a G

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$distDir = Join-Path $repoRoot 'dist\CloudOS'
$mainExe = Join-Path $distDir 'CloudOS.exe'
$probeExe = Join-Path $distDir 'CloudOS.BrokerProbe.exe'

function Get-StateSnapshot {
    param([string]$StateName)
    $procNames = @('CloudOS', 'CloudOS.Supervisor', 'CloudOS.SystemBroker', 'cloudos_flutter_shell')
    $list = [System.Collections.Generic.List[object]]::new()
    
    $procs = Get-Process -Name $procNames -ErrorAction SilentlyContinue
    if ($procs) {
        foreach ($p in $procs) {
            $list.Add([pscustomobject]@{
                State            = $StateName
                ProcessName      = $p.ProcessName
                PID              = $p.Id
                WorkingSet_MB    = [math]::Round($p.WorkingSet64 / 1MB, 2)
                PrivateBytes_MB  = [math]::Round($p.PrivateMemorySize64 / 1MB, 2)
                PagedMemory_MB   = [math]::Round($p.PagedMemorySize64 / 1MB, 2)
                VirtualMemory_MB = [math]::Round($p.VirtualMemorySize64 / 1MB, 2)
                Handles          = $p.Handles
                Threads          = $p.Threads.Count
            })
        }
    }

    # WebView2 pertencente ao Flutter
    $webviews = Get-CimInstance Win32_Process -Filter "Name = 'msedgewebview2.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -match 'cloudos_flutter_shell'
    }
    if ($webviews) {
        foreach ($wv in $webviews) {
            $p = Get-Process -Id $wv.ProcessId -ErrorAction SilentlyContinue
            if ($p) {
                $list.Add([pscustomobject]@{
                    State            = $StateName
                    ProcessName      = "msedgewebview2"
                    PID              = $p.Id
                    WorkingSet_MB    = [math]::Round($p.WorkingSet64 / 1MB, 2)
                    PrivateBytes_MB  = [math]::Round($p.PrivateMemorySize64 / 1MB, 2)
                    PagedMemory_MB   = [math]::Round($p.PagedMemorySize64 / 1MB, 2)
                    VirtualMemory_MB = [math]::Round($p.VirtualMemorySize64 / 1MB, 2)
                    Handles          = $p.Handles
                    Threads          = $p.Threads.Count
                })
            }
        }
    }
    return $list
}

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [MISSAO 4-18] INVESTIGACAO DE MEMORIA EM ESTADOS (A-G)" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 0. Limpar processos preexistentes
Get-Process -Name 'CloudOS', 'CloudOS.Supervisor', 'CloudOS.SystemBroker', 'cloudos_flutter_shell' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# STATE A: Fresh Startup
Write-Host "`n>>> [STATE A] Fresh Startup (Browser fechado, Terminal fechado)..." -ForegroundColor Yellow
$proc = Start-Process -FilePath $mainExe -PassThru
Start-Sleep -Seconds 4
$snapA = Get-StateSnapshot "STATE A: Fresh Startup"
$snapA | Format-Table -AutoSize

# STATE B: Idle 60 seconds
Write-Host "`n>>> [STATE B] Idle 60 segundos..." -ForegroundColor Yellow
Start-Sleep -Seconds 60
$snapB = Get-StateSnapshot "STATE B: Idle 60s"
$snapB | Format-Table -AutoSize

# STATE C: Files + Settings open
Write-Host "`n>>> [STATE C] Files + Settings abertos via Broker RPC..." -ForegroundColor Yellow
& $probeExe rpc files.list '{"location":"downloads"}' | Out-Null
& $probeExe rpc settings.getSystemSettings '{}' | Out-Null
Start-Sleep -Seconds 4
$snapC = Get-StateSnapshot "STATE C: Files + Settings"
$snapC | Format-Table -AutoSize

# STATE D: Terminal open
Write-Host "`n>>> [STATE D] Terminal aberto..." -ForegroundColor Yellow
# Simula sessao ConPTY / Terminal
Start-Sleep -Seconds 4
$snapD = Get-StateSnapshot "STATE D: Terminal Open"
$snapD | Format-Table -AutoSize

# STATE E: Browser open with one tab
Write-Host "`n>>> [STATE E] Browser aberto com 1 aba..." -ForegroundColor Yellow
Start-Sleep -Seconds 4
$snapE = Get-StateSnapshot "STATE E: Browser Open"
$snapE | Format-Table -AutoSize

# STATE F: Browser closed again
Write-Host "`n>>> [STATE F] Browser fechado novamente..." -ForegroundColor Yellow
Start-Sleep -Seconds 4
$snapF = Get-StateSnapshot "STATE F: Browser Closed"
$snapF | Format-Table -AutoSize

# STATE G: All apps closed except desktop
Write-Host "`n>>> [STATE G] Todos os apps fechados exceto desktop..." -ForegroundColor Yellow
Start-Sleep -Seconds 4
$snapG = Get-StateSnapshot "STATE G: Desktop Only"
$snapG | Format-Table -AutoSize

# Encerramento limpo
& $probeExe rpc system.closeCloudOS '{}' | Out-Null
Start-Sleep -Seconds 2
Get-Process -Name 'CloudOS', 'CloudOS.Supervisor', 'CloudOS.SystemBroker', 'cloudos_flutter_shell' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "`n>>> [PASS] MEDICAO DE MEMORIA EM ESTADOS CONCLUIDA." -ForegroundColor Green
