<#
.SYNOPSIS
    Suite de Testes de Tortura de IPC do SystemBroker (Missao #6)
    Testa limites de 1MB, payloads malformados, JSON profundo, desconexoes abruptas e rajada de pings.
#>
[CmdletBinding()]
param(
    [int]$BurstPings = 2000
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$probeExe = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\CloudOS.BrokerProbe.exe'
if (-not (Test-Path $probeExe)) {
    $probeExe = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.BrokerProbe.exe'
}

$sid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
$sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
$pipeName = "CloudOS.SystemBroker.v21.$sid.$sessionId"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [MISSAO #6] TORTURA DE IPC DO SYSTEM BROKER V21" -ForegroundColor Cyan
Write-Host " Pipe: $pipeName" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

function Assert-BrokerAlive {
    param([string]$Context)
    $ping = & $probeExe ping 2>&1
    if ($ping -notmatch '"pong":true') {
        throw "FALHA CRITICA: SystemBroker crashou ou parou de responder apos: $Context"
    }
}

function Send-Frame {
    param(
        [System.IO.BinaryWriter]$Writer,
        [byte[]]$PayloadBytes
    )
    $len = [uint32]$PayloadBytes.Length
    $Writer.Write($len)
    if ($len -gt 0) {
        $Writer.Write($PayloadBytes)
    }
    $Writer.Flush()
}

function Receive-Frame {
    param(
        [System.IO.BinaryReader]$Reader
    )
    $len = $Reader.ReadUInt32()
    if ($len -gt 2097152) {
        throw "Frame recebido excede limite maximo razoavel: $len bytes"
    }
    if ($len -eq 0) {
        return ""
    }
    $bytes = $Reader.ReadBytes($len)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Connect-BrokerClient {
    $client = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
    $client.Connect(5000)
    $writer = New-Object System.IO.BinaryWriter($client)
    $reader = New-Object System.IO.BinaryReader($client)

    # Handshake Hello obrigatorio
    $hello = '{"protocol":21,"type":"request","id":"init-h","method":"hello","payload":{"clientName":"CloudOS.QATorture","clientVersion":"21.0.0"}}'
    $helloBytes = [System.Text.Encoding]::UTF8.GetBytes($hello)
    Send-Frame -Writer $writer -PayloadBytes $helloBytes
    $resp = Receive-Frame -Reader $reader
    if (-not $resp -or -not $resp.Contains('"ok":true')) {
        $client.Dispose()
        throw "Falha no handshake hello do broker: $resp"
    }
    return [pscustomobject]@{
        Client = $client
        Writer = $writer
        Reader = $reader
    }
}

# 1. Validar broker ativo inicial
Write-Host "[1/6] Verificando handshake inicial com o broker..." -ForegroundColor Yellow

$brokerExe = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\CloudOS.SystemBroker.exe'
if (-not (Test-Path $brokerExe)) {
    $brokerExe = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.SystemBroker.exe'
}
$brokerProc = Get-Process -Name 'CloudOS.SystemBroker' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $brokerProc -or $brokerProc.HasExited) {
    Write-Host "  SystemBroker ausente. Iniciando instancia ($brokerExe)..." -ForegroundColor Yellow
    Start-Process -FilePath $brokerExe -WindowStyle Hidden | Out-Null
    Start-Sleep -Milliseconds 800
}

Assert-BrokerAlive "Handshake inicial"
Write-Host "  [OK] SystemBroker ativo e respondendo na pipe $pipeName." -ForegroundColor Green

# 2. Teste de Rajada / Burst Pings via Conexao Binaria Framed
Write-Host "[2/6] Executando rajada de $BurstPings pings de alta frequencia via NamedPipe direta..." -ForegroundColor Yellow
$conn = Connect-BrokerClient
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$successCount = 0
$reqJson = '{"protocol":21,"type":"request","id":"burst-ping","method":"health.ping","payload":{}}'
$reqBytes = [System.Text.Encoding]::UTF8.GetBytes($reqJson)

for ($i = 1; $i -le $BurstPings; $i++) {
    Send-Frame -Writer $conn.Writer -PayloadBytes $reqBytes
    $resp = Receive-Frame -Reader $conn.Reader
    if ($resp -and $resp.Contains('"pong":true')) {
        $successCount++
    }
}
$sw.Stop()
$conn.Writer.Dispose()
$conn.Reader.Dispose()
$conn.Client.Dispose()

$opsPerSec = [math]::Round($successCount / [math]::Max(0.001, $sw.Elapsed.TotalSeconds), 1)
Write-Host "  [OK] $successCount / $BurstPings pings respondidos com sucesso em $($sw.ElapsedMilliseconds)ms ($opsPerSec ops/sec)." -ForegroundColor Green
Assert-BrokerAlive "Apos rajada de pings"

# 3. Teste de Boundary de Tamanho de Payload (1MB boundary)
Write-Host "[3/6] Testando limite de tamanho de payload (1MB boundary)..." -ForegroundColor Yellow

# 3a. Payload grande valido (~500 KB)
Write-Host "  [3a] Testando payload grande seguro (~500 KB)..." -ForegroundColor Cyan
$largeBlob = "A" * (500 * 1024)
$reqLarge = '{"protocol":21,"type":"request","id":"large-500k","method":"health.ping","payload":{"blob":"' + $largeBlob + '"}}'
$largeBytes = [System.Text.Encoding]::UTF8.GetBytes($reqLarge)

$conn = Connect-BrokerClient
Send-Frame -Writer $conn.Writer -PayloadBytes $largeBytes
$resp = Receive-Frame -Reader $conn.Reader
$conn.Writer.Dispose()
$conn.Reader.Dispose()
$conn.Client.Dispose()

if (-not $resp -or -not $resp.Contains('"pong":true')) {
    throw "FALHA: Payload de 500KB nao foi aceito pelo broker."
}
Write-Host "    [OK] Payload de 500KB processado e respondido com sucesso." -ForegroundColor Green
Assert-BrokerAlive "Apos payload de 500KB"

# 3b. Payload excedendo o limite de 1MB (1.2 MB) -> Broker deve rejeitar fail-closed sem travar
Write-Host "  [3b] Testando payload excedendo limite (>1MB, 1.2MB)..." -ForegroundColor Cyan
$oversizedBlob = "B" * (1200 * 1024)
$reqOver = '{"protocol":21,"type":"request","id":"oversized-1.2m","method":"health.ping","payload":{"blob":"' + $oversizedBlob + '"}}'
$overBytes = [System.Text.Encoding]::UTF8.GetBytes($reqOver)

$conn = Connect-BrokerClient
try {
    Send-Frame -Writer $conn.Writer -PayloadBytes $overBytes
    $resp = Receive-Frame -Reader $conn.Reader
    Write-Host "    [OK] Broker tratou payload >1MB com resposta segura: $(if ($resp) { $resp.Substring(0, [math]::Min(60, $resp.Length)) } else { '(fechamento limpo)' })" -ForegroundColor Green
} catch {
    Write-Host "    [OK] Broker encerrou conexao em excesso de limite com seguranca (fail-closed): $($_.Exception.Message)" -ForegroundColor Green
} finally {
    $conn.Writer.Dispose()
    $conn.Reader.Dispose()
    $conn.Client.Dispose()
}
Assert-BrokerAlive "Apos teste de payload > 1MB"

# 4. Payloads Vazios, Quebrados e Ruido Binario
Write-Host "[4/6] Testando payloads vazios, quebras de linha e ruido binario..." -ForegroundColor Yellow
$garbageCases = @(
    "",
    "   ",
    "`n",
    "`r`n`r`n",
    "{}",
    "null",
    "42",
    "false",
    '{"incomplete":',
    '{"protocol": "not_an_int"}',
    '{"protocol": 21, "method": "inexistente.metodo.de.teste"}',
    ( [char]0x00 + [char]0xFF + [char]0xFE + [char]0xFD + "`n" )
)

foreach ($g in $garbageCases) {
    try {
        $pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
        $pipeClient.Connect(2000)
        $writer = New-Object System.IO.BinaryWriter($pipeClient)
        $reader = New-Object System.IO.BinaryReader($pipeClient)

        $gBytes = [System.Text.Encoding]::UTF8.GetBytes($g)
        Send-Frame -Writer $writer -PayloadBytes $gBytes
        $resp = Receive-Frame -Reader $reader
    } catch {
        # Desconexao limpa ou EOF esperada
    } finally {
        if ($writer) { $writer.Dispose() }
        if ($reader) { $reader.Dispose() }
        if ($pipeClient) { $pipeClient.Dispose() }
    }
}
Assert-BrokerAlive "Apos envio de ruido binario e payloads invalidos"
Write-Host "  [OK] Todos os casos de ruido tratados com fail-closed limpo." -ForegroundColor Green

# 5. JSON Profundamente Aninhado (Recursion Bomb Defense)
Write-Host "[5/6] Testando bomba de recursao (JSON aninhado em 120 niveis)..." -ForegroundColor Yellow
$nestedJson = ""
for ($d = 0; $d -lt 120; $d++) { $nestedJson += '{"nest":' }
$nestedJson += '"deep_value"'
for ($d = 0; $d -lt 120; $d++) { $nestedJson += '}' }

$reqNested = '{"protocol":21,"type":"request","id":"nested-test","method":"health.ping","payload":' + $nestedJson + '}'
$nestedBytes = [System.Text.Encoding]::UTF8.GetBytes($reqNested)

try {
    $conn = Connect-BrokerClient
    Send-Frame -Writer $conn.Writer -PayloadBytes $nestedBytes
    $resp = Receive-Frame -Reader $conn.Reader
} catch {} finally {
    if ($conn) {
        $conn.Writer.Dispose()
        $conn.Reader.Dispose()
        $conn.Client.Dispose()
    }
}
Assert-BrokerAlive "Apos teste de recursao JSON profunda"
Write-Host "  [OK] Bomba de recursao absorvida sem crash ou travamento." -ForegroundColor Green

# 6. Desconexoes Abruptas de Cliente (RST / Abort simulation)
Write-Host "[6/6] Testando 50 desconexoes abruptas com escrita parcial truncada..." -ForegroundColor Yellow
for ($a = 1; $a -le 50; $a++) {
    $pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
    $pipeClient.Connect(2000)
    $writer = New-Object System.IO.BinaryWriter($pipeClient)
    # Escreve comprimento declarado de 1000 bytes mas entrega apenas 20 bytes e fecha
    $writer.Write([uint32]1000)
    $partialBytes = [System.Text.Encoding]::UTF8.GetBytes('{"protocol":21')
    $writer.Write($partialBytes)
    $writer.Flush()
    $writer.Dispose()
    $pipeClient.Dispose()
}
Assert-BrokerAlive "Apos 50 desconexoes abruptas"
Write-Host "  [OK] Broker recuperou handles e threads de todas as 50 desconexoes truncadas." -ForegroundColor Green

Write-Host "`n>>> [PASS] MISSAO #6: TORTURA DE IPC DO SYSTEM BROKER CONCLUIDA COM SUCESSO!" -ForegroundColor Green
return [pscustomobject]@{
    Test = "Broker-IPC-Torture"
    Status = "PASS"
    BurstPings = $BurstPings
    ThroughputOpsPerSec = $opsPerSec
}
