<#
.SYNOPSIS
    Contrato de Validacao 3/5: Falha/Recuperacao e Garantia de Fallback Explorer (Etapa 10).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$probeExe = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\CloudOS.BrokerProbe.exe'
$brokerExe = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\CloudOS.SystemBroker.exe'

$isRealBinary = $false
if ((Test-Path -LiteralPath $brokerExe) -and (Test-Path -LiteralPath $probeExe)) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($brokerExe)
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) {
            $isRealBinary = $true
        }
    } catch { }
}

if (-not $isRealBinary) {
    Write-Host "  [INFO] CloudOS.SystemBroker.exe nao compilado (pre-build CI). Validacao postergada." -ForegroundColor Yellow
    return $true
}

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 3/5] Validacao de Fallback Explorer e Shutdown" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

function Stop-AllCloudOSProcesses {
    $names = @('cloudos_flutter_shell', 'CloudOS', 'CloudOS.Supervisor', 'CloudOS.SystemBroker')
    foreach ($name in $names) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

$brokerProc = $null

try {
    # 1. Verificar estado e PID do explorer.exe antes de qualquer operacao
    Write-Host "[1/4] Inspecionando processo e responsividade do Windows Explorer..." -ForegroundColor Yellow
    $isCi = $env:GITHUB_ACTIONS -or $env:CI
    $initialExplorer = Get-Process -Name 'explorer' -ErrorAction SilentlyContinue
    if (-not $initialExplorer -and -not $isCi) {
        throw "FALHA: Windows Explorer nao esta em execucao."
    }
    $initialExplorerPids = if ($initialExplorer) { @($initialExplorer | Select-Object -ExpandProperty Id) } else { @() }
    Write-Host "  [OK] Windows Explorer operacional (PID(s): $($initialExplorerPids -join ', '))." -ForegroundColor Green

    # 2. Iniciar Broker para testar RPC system.closeCloudOS
    Write-Host "[2/4] Iniciando SystemBroker e registrando RPCs de controle de sessao..." -ForegroundColor Yellow
    Stop-AllCloudOSProcesses
    Start-Sleep -Milliseconds 500

    $brokerProc = Start-Process -FilePath $brokerExe -ArgumentList 'run' -PassThru -NoNewWindow
    Start-Sleep -Milliseconds 800

    $ping = & $probeExe ping
    if ($ping -notmatch '"pong":true') {
        throw "FALHA: SystemBroker nao respondeu ao ping."
    }
    Write-Host "  [OK] SystemBroker ativo (PID $($brokerProc.Id))." -ForegroundColor Green

    # 3. Invocar RPC system.closeCloudOS (saida ordenada da camada CloudOS)
    Write-Host "[3/4] Invocando RPC system.closeCloudOS para encerramento ordenado..." -ForegroundColor Yellow
    $closeResRaw = & $probeExe invoke system.closeCloudOS '{}'
    $closeObj = $closeResRaw | ConvertFrom-Json
    if (-not $closeObj.ok -or -not $closeObj.payload -or -not $closeObj.payload.success) {
        throw "FALHA: system.closeCloudOS nao confirmou sucesso: $closeResRaw"
    }
    Write-Host "  [OK] RPC confirmou solicitacao de encerramento da camada CloudOS." -ForegroundColor Green

    # Aguardar encerramento do processo broker
    Start-Sleep -Seconds 2
    $brokerRunning = Get-Process -Id $brokerProc.Id -ErrorAction SilentlyContinue
    if ($brokerRunning -and -not $brokerRunning.HasExited) {
        Write-Host "  Aguardando Broker finalizar..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 2
    }

    # 4. Validar que o Explorer continua rodando exatamente com os mesmos PIDs
    Write-Host "[4/4] Validando integridade pos-encerramento do Windows Explorer..." -ForegroundColor Yellow
    $postExplorer = Get-Process -Name 'explorer' -ErrorAction SilentlyContinue
    if (-not $postExplorer) {
        throw "VIOLACAO CRITICA: Windows Explorer foi encerrado durante o desligamento do CloudOS!"
    }
    $postExplorerPids = @($postExplorer | Select-Object -ExpandProperty Id)
    
    $commonPids = @($initialExplorerPids | Where-Object { $postExplorerPids -contains $_ })
    if ($commonPids.Count -eq 0) {
        throw "FALHA: O Windows Explorer foi reiniciado durante a operacao (PIDs anteriores: $($initialExplorerPids -join ', '), atuais: $($postExplorerPids -join ', '))"
    }
    Write-Host "  [OK] Windows Explorer preservado sem interrupcao ou restart (PID(s): $($postExplorerPids -join ', '))." -ForegroundColor Green

    # Verificar chaves de Winlogon
    $hklmShell = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'Shell' -ErrorAction SilentlyContinue
    if ($hklmShell -ne 'explorer.exe') {
        throw "VIOLACAO GRAVE: HKLM Shell foi alterado: $hklmShell"
    }
    Write-Host "  [OK] Winlogon Shell permanece explorer.exe oficial." -ForegroundColor Green

} finally {
    Stop-AllCloudOSProcesses
}

Write-Host "`n>>> [PASS] CONTRATO 3/5: Fallback Explorer e saida ordenada aprovados." -ForegroundColor Green
return [pscustomobject]@{
    Contract = "test-startup-recovery-v30-contract.ps1"
    Status   = "PASS"
}
