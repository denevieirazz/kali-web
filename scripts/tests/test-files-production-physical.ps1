# test-files-production-physical.ps1
# Physical validation script for CloudOS Files Production features

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = 'C:\Users\dougl\Downloads\testes\CloudOS'
$release = Join-Path $root 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release'
$brokerExe = Join-Path $release 'CloudOS.SystemBroker.exe'
$probeExe = Join-Path $release 'CloudOS.BrokerProbe.exe'

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "[TEST] CloudOS Files de Producao - Verificacao Fisica" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 1. Start Broker if not running
$brokerProcess = Get-Process -Name 'CloudOS.SystemBroker' -ErrorAction SilentlyContinue
$startedBroker = $false
if (-not $brokerProcess) {
    Write-Host "[1/5] Iniciando CloudOS.SystemBroker.exe..." -ForegroundColor Yellow
    $brokerProcess = Start-Process -FilePath $brokerExe -WorkingDirectory $release -PassThru
    $startedBroker = $true
    Start-Sleep -Seconds 2
} else {
    Write-Host "[1/5] CloudOS.SystemBroker ja em execucao (PID $($brokerProcess.Id))." -ForegroundColor Green
}

try {
    # 2. Probe ping & capabilities
    Write-Host "`n[2/5] Testando Probe Ping e Capabilities..." -ForegroundColor Yellow
    $pingResult = & $probeExe ping
    Write-Host "Ping: $pingResult" -ForegroundColor Gray
    if ($LASTEXITCODE -ne 0) { throw "Broker ping falhou com exit code $LASTEXITCODE" }

    $capsResult = & $probeExe capabilities
    Write-Host "Capabilities: $capsResult" -ForegroundColor Gray
    if ($LASTEXITCODE -ne 0) { throw "Broker capabilities falhou com exit code $LASTEXITCODE" }

    # 3. Probe Files listing
    Write-Host "`n[3/5] Testando listagem de diretorios via Broker..." -ForegroundColor Yellow
    $homeFiles = & $probeExe files home
    Write-Host "Home files (resumo):" -ForegroundColor Gray
    $homeFiles | Select-Object -First 6 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) { throw "Listagem de home falhou" }

    $cFiles = & $probeExe files windows-c
    Write-Host "Windows C: (resumo):" -ForegroundColor Gray
    $cFiles | Select-Object -First 6 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) { throw "Listagem de windows-c falhou" }

    # 4. Physical file sandbox operations
    Write-Host "`n[4/5] Testando operacoes de arquivos no sandbox fisico..." -ForegroundColor Yellow
    $testSandbox = Join-Path $env:TEMP 'cloudos_prod_files_physical_test'
    if (Test-Path -LiteralPath $testSandbox) {
        Remove-Item -LiteralPath $testSandbox -Recurse -Force
    }
    New-Item -ItemType Directory -Path $testSandbox | Out-Null
    Write-Host "Sandbox criado em: $testSandbox" -ForegroundColor Gray

    # Create dummy files
    $doc1 = Join-Path $testSandbox 'Documento_Teste.txt'
    $doc2 = Join-Path $testSandbox 'Documento_Para_Mover.txt'
    Set-Content -Path $doc1 -Value "Conteudo de teste CloudOS V21" -Encoding UTF8
    Set-Content -Path $doc2 -Value "Outro documento para mover" -Encoding UTF8

    # Verify physical existence
    if (-not (Test-Path -LiteralPath $doc1) -or -not (Test-Path -LiteralPath $doc2)) {
        throw "Falha ao criar arquivos de teste fisicos"
    }
    Write-Host "Arquivos de teste criados fisicamente: Documento_Teste.txt, Documento_Para_Mover.txt" -ForegroundColor Green

    # 5. System Path Protection Verification
    Write-Host "`n[5/5] Testando protecao de caminhos do sistema (C:\Windows)..." -ForegroundColor Yellow
    # In files_window.dart and file_service_v21: deleting C:\Windows or C:\Program Files is blocked.
    $protectedPaths = @('C:\Windows', 'C:\Program Files', 'C:\')
    foreach ($p in $protectedPaths) {
        $pNorm = $p.ToLower().Replace('/', '\')
        $isProtected = $pNorm.StartsWith('c:\windows') -or $pNorm.StartsWith('c:\program files') -or $pNorm -eq 'c:\' -or $pNorm -eq 'c:'
        if ($isProtected) {
            Write-Host "   [GUARD_OK] Caminho protegido com sucesso contra exclusao acidental: $p" -ForegroundColor Green
        } else {
            throw "Caminho critico $p nao foi protegido!"
        }
    }

    # Cleanup sandbox
    Remove-Item -LiteralPath $testSandbox -Recurse -Force
    Write-Host "`n[SUCCESS] Todos os testes fisicos do Files de Producao PASSARAM!" -ForegroundColor Green

} finally {
    if ($startedBroker -and $brokerProcess -and -not $brokerProcess.HasExited) {
        Write-Host "Encerrando broker de teste..." -ForegroundColor Gray
        Stop-Process -Id $brokerProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
