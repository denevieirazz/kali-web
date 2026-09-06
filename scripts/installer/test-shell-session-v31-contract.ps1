# test-shell-session-v31-contract.ps1
# Valida controle de sessao, mutex unico e prevencao de concorrencia

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 9/10] Validacao de Sessao e Prevencao de Concorrencia" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

$bootstrapExe = Join-Path $PSScriptRoot '..\..\desktop\CloudOS.NativeShell\bin\Release\CloudOS.ShellBootstrap.exe'
if (-not (Test-Path -LiteralPath $bootstrapExe)) {
    $bootstrapExe = Join-Path $PSScriptRoot '..\..\dist\CloudOS\CloudOS.ShellBootstrap.exe'
}
if (-not (Test-Path -LiteralPath $bootstrapExe)) {
    throw "CloudOS.ShellBootstrap.exe nao encontrado para teste de sessao"
}

$sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
$mutexName = "Local\CloudOS_ShellBootstrap_Session_$sessionId"

Write-Host "[1/3] Testando aquisicao de mutex unico de sessao ($mutexName)..." -ForegroundColor Yellow
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)

if (-not $createdNew) {
    $mutex.Dispose()
    throw "Nao foi possivel adquirir o mutex inicial de teste de sessao ($mutexName)"
}

try {
    Write-Host "  [OK] Mutex de sessao adquirido com sucesso pelo processo de teste." -ForegroundColor Green

    # 2. Executar uma segunda instancia do bootstrap enquanto o mutex estiver retido
    Write-Host "[2/3] Executando CloudOS.ShellBootstrap.exe concorrente para verificar rejeicao de duplicata..." -ForegroundColor Yellow
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $bootstrapExe
    $psi.Arguments = "--canary"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $finished = $proc.WaitForExit(5000)

    if (-not $finished) {
        $proc.Kill()
        throw "Segunda instancia do CloudOS.ShellBootstrap nao encerrou dentro do timeout de 5s"
    }

    $exitCode = $proc.ExitCode
    Write-Host "  [OK] Segunda instancia encerrou imediatamente com exit code $exitCode (esperado 0 para saida limpa)." -ForegroundColor Green
    if ($exitCode -ne 0) {
        throw "Exit code inesperado da segunda instancia: $exitCode"
    }

    # Verificar log
    $recLog = Join-Path $env:LOCALAPPDATA 'CloudOS\Recovery\shell-bootstrap.log'
    if (Test-Path -LiteralPath $recLog) {
        $logTail = Get-Content -LiteralPath $recLog -Tail 10 -ErrorAction SilentlyContinue
        $foundNotice = $logTail | Where-Object { $_ -match "Another instance of CloudOS.ShellBootstrap is already running" }
        if ($foundNotice) {
            Write-Host "  [OK] Log de recuperacao confirmou rejeicao de duplicata: '$($foundNotice[0])'" -ForegroundColor Green
        }
    }
} finally {
    # 3. Liberar mutex
    Write-Host "[3/3] Liberando mutex de sessao..." -ForegroundColor Yellow
    $mutex.ReleaseMutex()
    $mutex.Dispose()
    Write-Host "  [OK] Mutex liberado com sucesso." -ForegroundColor Green
}

Write-Host "`n>>> [PASS] CONTRATO 9/10: Sessao e Prevencao de Concorrencia aprovados." -ForegroundColor Green
return [pscustomobject]@{
    Contract = "test-shell-session-v31-contract.ps1"
    Status   = "PASS"
}
