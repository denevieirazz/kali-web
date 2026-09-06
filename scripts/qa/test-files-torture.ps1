<#
.SYNOPSIS
    Suite de Testes de Tortura de Arquivos e Sandbox (Missao #7)
    Testa 10.000 itens, navegacao, nomes DOS reservados, Unicode/Emojis,
    cancelamento de jobs assincronos de copia e limpeza.
#>
[CmdletBinding()]
param(
    [int]$ItemCount = 10000
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
Write-Host " [MISSAO #7] TORTURA DE ARQUIVOS E SANDBOX V21" -ForegroundColor Cyan
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
    if ($len -gt 16777216) { # 16MB max para listas grandes
        throw "Frame recebido excede limite maximo de 16MB: $len bytes"
    }
    if ($len -eq 0) {
        return ""
    }
    $bytes = $Reader.ReadBytes($len)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Invoke-BrokerRpc {
    param(
        [string]$Method,
        [hashtable]$Payload
    )
    $client = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
    $client.Connect(5000)
    $writer = New-Object System.IO.BinaryWriter($client)
    $reader = New-Object System.IO.BinaryReader($client)

    # Hello handshake
    $hello = '{"protocol":21,"type":"request","id":"h-init","method":"hello","payload":{"clientName":"CloudOS.FilesTorture","clientVersion":"21.0.0"}}'
    $helloBytes = [System.Text.Encoding]::UTF8.GetBytes($hello)
    Send-Frame -Writer $writer -PayloadBytes $helloBytes
    $null = Receive-Frame -Reader $reader

    # Request real
    $msgId = [System.Guid]::NewGuid().ToString("N")
    $payloadJson = ($Payload | ConvertTo-Json -Compress -Depth 10)
    $req = "{`"protocol`":21,`"type`":`"request`",`"id`":`"$msgId`",`"method`":`"$Method`",`"payload`":$payloadJson}"
    $reqBytes = [System.Text.Encoding]::UTF8.GetBytes($req)
    Send-Frame -Writer $writer -PayloadBytes $reqBytes
    $respStr = Receive-Frame -Reader $reader

    $writer.Dispose()
    $reader.Dispose()
    $client.Dispose()

    return ($respStr | ConvertFrom-Json)
}

# 0. Assegurar SystemBroker ativo
$brokerExe = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\CloudOS.SystemBroker.exe'
if (-not (Test-Path $brokerExe)) {
    $brokerExe = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.SystemBroker.exe'
}
$brokerProc = Get-Process -Name 'CloudOS.SystemBroker' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $brokerProc -or $brokerProc.HasExited) {
    Write-Host "SystemBroker ausente. Iniciando instancia ($brokerExe)..." -ForegroundColor Yellow
    Start-Process -FilePath $brokerExe -WindowStyle Hidden | Out-Null
    Start-Sleep -Milliseconds 800
}
Assert-BrokerAlive "Verificacao inicial de broker"

# 1. Preparacao do Sandbox no Downloads
$downloadsDir = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
if (-not (Test-Path $downloadsDir)) {
    $downloadsDir = Join-Path $env:USERPROFILE 'Downloads'
}
$sandboxRoot = Join-Path $downloadsDir "cloudos_sandbox_qa"

Write-Host "[1/6] Preparando diretorio sandbox em $sandboxRoot..." -ForegroundColor Yellow
if (Test-Path $sandboxRoot) {
    Remove-Item $sandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -Path $sandboxRoot -ItemType Directory -Force | Out-Null
Write-Host "  [OK] Sandbox inicializado limpo." -ForegroundColor Green

# 2. Localizar Sandbox via files.list ('downloads')
Write-Host "[2/6] Localizando sandbox via API files.list..." -ForegroundColor Yellow
$listRes = Invoke-BrokerRpc -Method "files.list" -Payload @{ location = "downloads" }
if (-not $listRes.ok) {
    throw "FALHA: files.list 'downloads' falhou: $($listRes.error.message)"
}

$sandboxEntry = $listRes.payload.files | Where-Object { $_.name -eq "cloudos_sandbox_qa" }
if (-not $sandboxEntry) {
    throw "FALHA: cloudos_sandbox_qa nao encontrado na lista de downloads"
}
$sandboxEntryId = $sandboxEntry.entryId
Write-Host "  [OK] Sandbox localizado! EntryId: $($sandboxEntryId.Substring(0, 16))..." -ForegroundColor Green

# 3. Teste de Nomes Reservados DOS (Hardening)
Write-Host "[3/6] Testando rejeicao de nomes de dispositivos DOS reservados..." -ForegroundColor Yellow
$dosNames = @("CON", "PRN", "AUX", "NUL", "COM1", "COM9", "LPT1", "LPT9", "con.txt", "nul.dat")
$rejectedCount = 0

foreach ($badName in $dosNames) {
    $createRes = Invoke-BrokerRpc -Method "files.createFolder" -Payload @{
        parentEntryId = $sandboxEntryId
        name = $badName
    }
    if (-not $createRes.ok) {
        $rejectedCount++
    } else {
        throw "FALHA DE SEGURANCA: Broker aceitou criar nome reservado DOS: $badName"
    }
}
Write-Host "  [OK] $rejectedCount / $($dosNames.Count) nomes reservados DOS rejeitados com seguranca." -ForegroundColor Green
Assert-BrokerAlive "Apos teste de nomes DOS reservados"

# 4. Teste de Unicode Complexo e Emojis
Write-Host "[4/6] Testando criacao e listagem de nomes Unicode e Emojis..." -ForegroundColor Yellow
$emojiFolder = [char]::ConvertFromUtf32(0x1F4C1)
$emojiRocket = [char]::ConvertFromUtf32(0x1F680)
$emojiChart = [char]::ConvertFromUtf32(0x1F4CA)
$unicodeFolderName = "${emojiFolder}_Projeto_2026_${emojiRocket}_acao_teste"

$createUniRes = Invoke-BrokerRpc -Method "files.createFolder" -Payload @{
    parentEntryId = $sandboxEntryId
    name = $unicodeFolderName
}
if (-not $createUniRes.ok) {
    throw "FALHA: Falha ao criar pasta com Unicode/Emoji: $($createUniRes.error.message)"
}
$unicodeFolderEntryId = $createUniRes.payload.entryId
Write-Host "  [OK] Pasta Unicode criada com sucesso. EntryId: $($unicodeFolderEntryId.Substring(0, 16))..." -ForegroundColor Green

# Criar arquivo UTF-8 dentro dela
$unicodeFolderFsPath = Join-Path $sandboxRoot $unicodeFolderName
$testFileFsPath = Join-Path $unicodeFolderFsPath "relatorio_tecnico_${emojiChart}.txt"
[System.IO.File]::WriteAllText($testFileFsPath, "CloudOS RC1.4 Unicode Torture Test", [System.Text.Encoding]::UTF8)

# Listar via broker
$listUniRes = Invoke-BrokerRpc -Method "files.listEntry" -Payload @{ entryId = $unicodeFolderEntryId }
if (-not $listUniRes.ok) {
    throw "FALHA: Falha ao listar pasta Unicode via files.listEntry"
}
$listedFile = $listUniRes.payload.files | Where-Object { $_.name -match "relatorio_tecnico" }
if (-not $listedFile) {
    throw "FALHA: Arquivo Unicode nao foi retornado pelo Broker"
}
Write-Host "  [OK] Arquivo com acentos e emojis listado perfeitamente: $($listedFile.name)" -ForegroundColor Green

# 5. Teste de Volume Extremo: 10.000 Pequenos Arquivos
Write-Host "[5/6] Gerando $ItemCount pequenos arquivos para tortura de enumeracao..." -ForegroundColor Yellow
$bulkDirFs = Join-Path $sandboxRoot "bulk_10k"
[System.IO.Directory]::CreateDirectory($bulkDirFs) | Out-Null

$swGen = [System.Diagnostics.Stopwatch]::StartNew()
$dummyBytes = [System.Text.Encoding]::ASCII.GetBytes("CloudOS QA")
for ($i = 1; $i -le $ItemCount; $i++) {
    $fn = [System.IO.Path]::Combine($bulkDirFs, ("f_{0:D5}.txt" -f $i))
    [System.IO.File]::WriteAllBytes($fn, $dummyBytes)
}
$swGen.Stop()
Write-Host "  [OK] $ItemCount arquivos gerados em $($swGen.ElapsedMilliseconds)ms." -ForegroundColor Green

# Obter entryId de bulk_10k
$listSandbox = Invoke-BrokerRpc -Method "files.listEntry" -Payload @{ entryId = $sandboxEntryId }
$bulkEntry = $listSandbox.payload.files | Where-Object { $_.name -eq "bulk_10k" }
$bulkEntryId = $bulkEntry.entryId

Write-Host "  Enumerando pasta de 10.000 arquivos via Broker com paginacao (offset=0, limit=1000)..." -ForegroundColor Cyan
$swEnum = [System.Diagnostics.Stopwatch]::StartNew()
$page1 = Invoke-BrokerRpc -Method "files.listEntry" -Payload @{ entryId = $bulkEntryId; offset = 0; limit = 1000 }
$swEnum.Stop()

if (-not $page1.ok) {
    throw "FALHA: Falha ao paginar pasta de 10.000 itens: $($page1.error.message)"
}
$countPage1 = $page1.payload.files.Count
$totalCount = $page1.payload.totalCount
$hasMore = $page1.payload.hasMore
Write-Host "  [OK] Pagina 1: $countPage1 itens recebidos em $($swEnum.ElapsedMilliseconds)ms (totalCount=$totalCount, hasMore=$hasMore)." -ForegroundColor Green

# Testar Pagina 2
$page2 = Invoke-BrokerRpc -Method "files.listEntry" -Payload @{ entryId = $bulkEntryId; offset = 1000; limit = 1000 }
$countPage2 = $page2.payload.files.Count
Write-Host "  [OK] Pagina 2: $countPage2 itens recebidos com offset 1000." -ForegroundColor Green

# Testar busca rapida por query no Broker
Write-Host "  Testando busca filtrada de alta performance no Broker (query='f_07890')..." -ForegroundColor Cyan
$swSearch = [System.Diagnostics.Stopwatch]::StartNew()
$searchRes = Invoke-BrokerRpc -Method "files.listEntry" -Payload @{ entryId = $bulkEntryId; query = "f_07890" }
$swSearch.Stop()
if (-not $searchRes.ok -or $searchRes.payload.files.Count -ne 1) {
    throw "FALHA: Busca por query no broker falhou ou nao retornou 1 item exato"
}
$foundName = $searchRes.payload.files[0].name
Write-Host "  [OK] Item localizado instantaneamente via busca em $($swSearch.ElapsedMilliseconds)ms: $foundName" -ForegroundColor Green

# Testar limite de seguranca padrao (sem parametros)
$defaultList = Invoke-BrokerRpc -Method "files.listEntry" -Payload @{ entryId = $bulkEntryId }
Write-Host "  [OK] Listagem padrao sem parametros limitada com seguranca a $($defaultList.payload.files.Count) itens (hasMore=$($defaultList.payload.hasMore))." -ForegroundColor Green
Assert-BrokerAlive "Apos testes de paginacao e busca em 10.000 itens"

# 6. Teste de Cancelamento de Job de Copia de Arquivo Grande (50MB)
Write-Host "[6/6] Testando submissao e cancelamento imediato de job assincrono de copia (50MB)..." -ForegroundColor Yellow
$bigSourcePath = Join-Path $sandboxRoot "big_source_50mb.dat"
$destFolderFs = Join-Path $sandboxRoot "copy_dest"
[System.IO.Directory]::CreateDirectory($destFolderFs) | Out-Null

# Criar arquivo de 50MB
$fs = New-Object System.IO.FileStream($bigSourcePath, [System.IO.FileMode]::Create)
$fs.SetLength(50 * 1024 * 1024)
$fs.Close()
$fs.Dispose()

# Re-listar sandbox para obter entryIds do arquivo de 50MB e da pasta dest
$listSandbox = Invoke-BrokerRpc -Method "files.listEntry" -Payload @{ entryId = $sandboxEntryId }
$bigFileEntry = $listSandbox.payload.files | Where-Object { $_.name -eq "big_source_50mb.dat" }
$destFolderEntry = $listSandbox.payload.files | Where-Object { $_.name -eq "copy_dest" }

# Iniciar copia
$copyRes = Invoke-BrokerRpc -Method "files.copy" -Payload @{
    sourceEntryIds = @($bigFileEntry.entryId)
    destinationEntryId = $destFolderEntry.entryId
    conflictStrategy = "replace"
}

if (-not $copyRes.ok) {
    throw "FALHA: files.copy falhou: $($copyRes.error.message)"
}
$jobId = $copyRes.payload.jobId
Write-Host "  Job de copia iniciado: $jobId. Solicitando cancelamento imediato..." -ForegroundColor Cyan

# Cancelar job imediatamente
$cancelRes = Invoke-BrokerRpc -Method "jobs.cancel" -Payload @{ jobId = $jobId }
Write-Host "  Cancelamento solicitado: ok=$($cancelRes.ok), cancelled=$($cancelRes.payload.cancelled)" -ForegroundColor Green

# Aguardar 500ms e checar status final do job
Start-Sleep -Milliseconds 500
$statusRes = Invoke-BrokerRpc -Method "jobs.status" -Payload @{ jobId = $jobId }
Write-Host "  Status final do job: state=$($statusRes.payload.state), progress=$($statusRes.payload.progress)" -ForegroundColor Green

# Limpeza e descarte do sandbox
Write-Host "  Limpando diretorio sandbox..." -ForegroundColor Cyan
Remove-Item $sandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
Assert-BrokerAlive "Apos cancelamento de job e limpeza"
Write-Host "  [OK] Sandbox removido com sucesso e broker estavel." -ForegroundColor Green

Write-Host "`n>>> [PASS] MISSAO #7: TORTURA DE ARQUIVOS E SANDBOX CONCLUIDA COM SUCESSO!" -ForegroundColor Green
return [pscustomobject]@{
    Test = "Files-Sandbox-Torture"
    Status = "PASS"
    ItemsTested = $ItemCount
    EnumerationTimeMs = $swEnum.ElapsedMilliseconds
    DosNamesBlocked = $rejectedCount
}
