<#
.SYNOPSIS
    Contrato de Validacao 2/5: Single-Instance e Prevensao de Concorrencia no Startup (Etapa 10).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$startScript = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\start-cloudos-v21-integrated.ps1'
$probeExe = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\CloudOS.BrokerProbe.exe'

$isRealBinary = $false
if (Test-Path -LiteralPath $probeExe) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($probeExe)
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) {
            $isRealBinary = $true
        }
    } catch { }
}

if (-not $isRealBinary -or -not (Test-Path -LiteralPath $startScript)) {
    Write-Host "  [INFO] Ambiente de execucao real nao compilado (pre-build CI). Validacao postergada." -ForegroundColor Yellow
    return $true
}

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 2/5] Validacao de Single-Instance no Startup" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

function Stop-AllCloudOSProcesses {
    $names = @('cloudos_flutter_shell', 'CloudOS', 'CloudOS.Supervisor', 'CloudOS.SystemBroker')
    foreach ($name in $names) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

try {
    # 1. Garantir ambiente limpo
    Write-Host "[1/4] Garantindo encerramento de instancias previas..." -ForegroundColor Yellow
    Stop-AllCloudOSProcesses
    Start-Sleep -Seconds 1

    # 2. Iniciar primeira instancia do CloudOS
    Write-Host "[2/4] Iniciando primeira instancia do CloudOS via script integrado..." -ForegroundColor Yellow
    $firstJob = Start-Process -FilePath 'powershell.exe' -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$startScript`"" -PassThru -NoNewWindow
    
    # Aguardar subida do Broker e Flutter Shell
    $deadline = [DateTime]::UtcNow.AddSeconds(25)
    $ready = $false
    do {
        try {
            $pong = & $probeExe ping
            $flutterProc = Get-Process -Name 'cloudos_flutter_shell' -ErrorAction SilentlyContinue
            if ($pong -match '"pong":true' -and $flutterProc) {
                $ready = $true
                break
            }
        } catch {}
        Start-Sleep -Milliseconds 600
    } while ([DateTime]::UtcNow -lt $deadline)

    if (-not $ready) {
        throw "FALHA: Primeira instancia do CloudOS nao subiu em tempo habil."
    }
    Write-Host "  [OK] Primeira instancia ativa e respondendo." -ForegroundColor Green

    # Contar processos ativos
    $flutterCount1 = @(Get-Process -Name 'cloudos_flutter_shell' -ErrorAction SilentlyContinue).Count
    $supervisorCount1 = @(Get-Process -Name 'CloudOS.Supervisor' -ErrorAction SilentlyContinue).Count
    $brokerCount1 = @(Get-Process -Name 'CloudOS.SystemBroker' -ErrorAction SilentlyContinue).Count

    Write-Host "  [OK] Processos da instancia 1: Flutter=$flutterCount1, Supervisor=$supervisorCount1, Broker=$brokerCount1" -ForegroundColor DarkGray
    if ($flutterCount1 -lt 1 -or $supervisorCount1 -lt 1 -or $brokerCount1 -lt 1) {
        throw "FALHA: Pilha de processos CloudOS incompleta na primeira instancia."
    }

    # 3. Invocar segunda vez com flag -Startup (simulando corrida ou duplo gatilho de login)
    Write-Host "[3/4] Invocando segunda instancia concorrente com -Startup..." -ForegroundColor Yellow
    $secondProc = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`" -Startup" -PassThru -NoNewWindow -Wait

    if ($secondProc.ExitCode -ne 0) {
        throw "FALHA: Segunda chamada retornou codigo de saida diferente de 0: $($secondProc.ExitCode)"
    }
    Write-Host "  [OK] Segunda chamada finalizou com ExitCode 0 (detectou instancia existente)." -ForegroundColor Green

    # 4. Verificar se a contagem de processos NAO se multiplicou
    Write-Host "[4/4] Verificando integridade de contagem de processos..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 800

    $flutterCount2 = @(Get-Process -Name 'cloudos_flutter_shell' -ErrorAction SilentlyContinue).Count
    $supervisorCount2 = @(Get-Process -Name 'CloudOS.Supervisor' -ErrorAction SilentlyContinue).Count
    $brokerCount2 = @(Get-Process -Name 'CloudOS.SystemBroker' -ErrorAction SilentlyContinue).Count

    Write-Host "  [OK] Processos apos segunda chamada: Flutter=$flutterCount2, Supervisor=$supervisorCount2, Broker=$brokerCount2" -ForegroundColor DarkGray

    if ($flutterCount2 -ne $flutterCount1) {
        throw "FALHA: Processo Flutter duplicado detectado: antes=$flutterCount1, depois=$flutterCount2"
    }
    if ($supervisorCount2 -ne $supervisorCount1) {
        throw "FALHA: Supervisor duplicado detectado: antes=$supervisorCount1, depois=$supervisorCount2"
    }
    if ($brokerCount2 -ne $brokerCount1) {
        throw "FALHA: SystemBroker duplicado detectado: antes=$brokerCount1, depois=$brokerCount2"
    }

    Write-Host "  [OK] Zero duplicatas criadas. Mutex de sessao e deteccao de instancia operacional." -ForegroundColor Green

} finally {
    Write-Host "  Limpando processos de teste..." -ForegroundColor DarkGray
    Stop-AllCloudOSProcesses
}

Write-Host "`n>>> [PASS] CONTRATO 2/5: Single-Instance e prevencao de concorrencia aprovados." -ForegroundColor Green
return [pscustomobject]@{
    Contract = "test-startup-single-instance-v30-contract.ps1"
    Status   = "PASS"
}
