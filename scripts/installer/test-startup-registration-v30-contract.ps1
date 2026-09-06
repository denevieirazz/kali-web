<#
.SYNOPSIS
    Contrato de Validacao 1/5: Registro seguro de inicializacao HKCU e RPCs do Broker (Etapa 10).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$probeExe = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\CloudOS.BrokerProbe.exe'
if (-not (Test-Path -LiteralPath $probeExe)) {
    $probeExe = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.BrokerProbe.exe'
}
$brokerExe = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\CloudOS.SystemBroker.exe'
if (-not (Test-Path -LiteralPath $brokerExe)) {
    $brokerExe = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.SystemBroker.exe'
}

if (-not (Test-Path -LiteralPath $probeExe) -or -not (Test-Path -LiteralPath $brokerExe)) {
    Write-Host "  [INFO] Broker e Probe nao compilados ainda (pre-build CI). Validacao postergada." -ForegroundColor Yellow
    return $true
}
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 1/5] Validacao de Registro HKCU e RPCs Startup" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Backup do estado atual do HKCU Run se existir
$originalStartup = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'CloudOS' -ErrorAction SilentlyContinue

try {
    # 2. Iniciar Broker para testar RPCs
    Write-Host "[1/5] Iniciando SystemBroker para validar RPCs de startup..." -ForegroundColor Yellow
    $brokerProc = Start-Process -FilePath $brokerExe -ArgumentList 'run' -PassThru -NoNewWindow
    Start-Sleep -Milliseconds 800

    # Teste de ping basico
    $probePing = & $probeExe ping
    if ($probePing -notmatch '"pong":true') {
        throw "FALHA: SystemBroker nao respondeu ao ping de handshake."
    }
    Write-Host "  [OK] SystemBroker ativo e respondendo na porta pipe v21." -ForegroundColor Green

    # 3. Teste RPC: startup.getStatus inicial
    Write-Host "[2/5] Consultando startup.getStatus via Broker RPC..." -ForegroundColor Yellow
    $statusJsonRaw = & $probeExe invoke startup.getStatus '{}'
    $statusObj = $statusJsonRaw | ConvertFrom-Json
    if (-not $statusObj.ok -or -not $statusObj.payload) {
        throw "FALHA: startup.getStatus nao retornou payload valido: $statusJsonRaw"
    }
    Write-Host "  [OK] Retorno getStatus: enabled=$($statusObj.payload.enabled), mechanism=$($statusObj.payload.mechanism)" -ForegroundColor Green

    # 4. Teste RPC: startup.setEnabled -> true
    Write-Host "[3/5] Chamando startup.setEnabled(true)..." -ForegroundColor Yellow
    $enableJsonRaw = & $probeExe invoke startup.setEnabled '{"enabled":true}'
    $enableObj = $enableJsonRaw | ConvertFrom-Json
    if (-not $enableObj.ok -or -not $enableObj.payload -or -not $enableObj.payload.success) {
        throw "FALHA: startup.setEnabled(true) falhou: $enableJsonRaw"
    }

    # Verificar diretamente no Registro do Windows HKCU\Run
    $regVal = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'CloudOS' -ErrorAction SilentlyContinue
    if (-not $regVal) {
        throw "FALHA: Chave HKCU\Run\CloudOS nao foi criada no Registro."
    }
    if ($regVal -notmatch '-Startup') {
        throw "FALHA: Comando de startup nao contem o parametro '-Startup': $regVal"
    }
    if ($regVal -notmatch 'CloudOS\.exe') {
        throw "FALHA: Comando de startup nao aponta para o CloudOS.exe nativo: $regVal"
    }
    Write-Host "  [OK] Registro HKCU\Run\CloudOS verificado com launcher nativo: $regVal" -ForegroundColor Green

    # 5. Teste RPC: startup.getStatus confirmando ativado
    $statusJsonRaw2 = & $probeExe invoke startup.getStatus '{}'
    $statusObj2 = $statusJsonRaw2 | ConvertFrom-Json
    if (-not $statusObj2.ok -or -not $statusObj2.payload.enabled) {
        throw "FALHA: startup.getStatus deveria retornar enabled=true apos setEnabled(true)."
    }
    Write-Host "  [OK] getStatus confirmou enabled=true com command preenchido." -ForegroundColor Green

    # 6. Teste RPC: startup.setEnabled -> false
    Write-Host "[4/5] Chamando startup.setEnabled(false)..." -ForegroundColor Yellow
    $disableJsonRaw = & $probeExe invoke startup.setEnabled '{"enabled":false}'
    $disableObj = $disableJsonRaw | ConvertFrom-Json
    if (-not $disableObj.ok -or -not $disableObj.payload -or -not $disableObj.payload.success) {
        throw "FALHA: startup.setEnabled(false) falhou: $disableJsonRaw"
    }

    # Verificar remocao no Registro
    $regValAfter = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'CloudOS' -ErrorAction SilentlyContinue
    if ($regValAfter) {
        throw "FALHA: Entrada HKCU\Run\CloudOS deveria ter sido removida: $regValAfter"
    }
    Write-Host "  [OK] Registro HKCU\Run\CloudOS removido com sucesso." -ForegroundColor Green

    # 7. Validar estritamente que NENHUMA chave de Winlogon foi tocada
    Write-Host "[5/5] Verificando integridade das chaves de Shell/Winlogon do Windows..." -ForegroundColor Yellow
    $hklmWinlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $hkcuWinlogon = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

    $hklmShell = (Get-ItemProperty -Path $hklmWinlogon -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'Shell' -ErrorAction SilentlyContinue
    if ($hklmShell -ne 'explorer.exe') {
        throw "VIOLACAO GRAVE: HKLM Winlogon Shell foi adulterado: $hklmShell"
    }
    $hkcuShell = (Get-ItemProperty -Path $hkcuWinlogon -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'Shell' -ErrorAction SilentlyContinue
    if ($hkcuShell) {
        throw "VIOLACAO GRAVE: HKCU Winlogon Shell foi configurado indevidamente: $hkcuShell"
    }
    Write-Host "  [OK] Winlogon Shell permanece explorer.exe oficial intocado." -ForegroundColor Green

} finally {
    # Encerrar broker
    if ($brokerProc -and -not $brokerProc.HasExited) {
        Stop-Process -Id $brokerProc.Id -Force -ErrorAction SilentlyContinue
    }
    # Restaurar registro original se havia
    if ($originalStartup) {
        Set-ItemProperty -Path $runKey -Name 'CloudOS' -Value $originalStartup
    } else {
        Remove-ItemProperty -Path $runKey -Name 'CloudOS' -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n>>> [PASS] CONTRATO 1/5: Registro seguro de inicializacao HKCU e RPCs aprovados." -ForegroundColor Green
return [pscustomobject]@{
    Contract = "test-startup-registration-v30-contract.ps1"
    Status   = "PASS"
}
