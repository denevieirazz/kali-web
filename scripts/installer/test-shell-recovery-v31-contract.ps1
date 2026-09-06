# test-shell-recovery-v31-contract.ps1
# Valida executavel de recuperacao CloudOS.Recovery.exe e instrucoes de emergencia

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 6/10] Validacao de Executavel e Hotpath de Recovery" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

$recoveryExe = Join-Path $PSScriptRoot '..\..\dist\CloudOS\CloudOS.Recovery.exe'
if (-not (Test-Path -LiteralPath $recoveryExe)) {
    $recoveryExe = Join-Path $PSScriptRoot '..\..\desktop\CloudOS.NativeShell\bin\Release\CloudOS.Recovery.exe'
}

if (-not (Test-Path -LiteralPath $recoveryExe)) {
    throw "Executavel CloudOS.Recovery.exe ausente em: $recoveryExe"
}

# 1. Testar verbo status
Write-Host "[1/4] Testando CloudOS.Recovery.exe status..." -ForegroundColor Yellow
$statusOut = & $recoveryExe status | Out-String
$statusJson = $statusOut | ConvertFrom-Json
if (-not $statusJson.status -or -not $statusJson.effective_shell) {
    throw "Saida de status de CloudOS.Recovery.exe invalida"
}
Write-Host "  [OK] Status retornado com sucesso: Status=$($statusJson.status), Shell=$($statusJson.effective_shell)" -ForegroundColor Green

# 2. Testar verbo verify
Write-Host "[2/4] Testando CloudOS.Recovery.exe verify..." -ForegroundColor Yellow
$verifyOut = & $recoveryExe verify | Out-String
$verifyJson = $verifyOut | ConvertFrom-Json
if (-not $verifyJson.verified) {
    throw "Verificacao de componentes de recovery falhou: $($verifyJson.missing_components) ausentes"
}
Write-Host "  [OK] Todos os componentes obrigatorios verificados com exito." -ForegroundColor Green

# 3. Testar verbo restore-explorer-shell
Write-Host "[3/4] Testando execucao limpa de CloudOS.Recovery.exe restore-explorer-shell..." -ForegroundColor Yellow
$restoreOut = & $recoveryExe restore-explorer-shell | Out-String
$restoreJson = $restoreOut | ConvertFrom-Json
if (-not $restoreJson.success -or -not $restoreJson.explorer_running) {
    throw "Restauracao do Windows Explorer retornou falha: $restoreOut"
}
Write-Host "  [OK] Hotpath de restauracao do Explorer validado (explorer_running=$($restoreJson.explorer_running))." -ForegroundColor Green

# 4. Validar arquivo de instrucao de emergencia local
Write-Host "[4/4] Validando presenca e conteudo de CLOUDOS_SHELL_RECOVERY.txt..." -ForegroundColor Yellow
$recTxt = Join-Path $PSScriptRoot '..\..\CLOUDOS_SHELL_RECOVERY.txt'
if (-not (Test-Path -LiteralPath $recTxt)) {
    throw "Arquivo CLOUDOS_SHELL_RECOVERY.txt ausente na raiz"
}
$txtContent = Get-Content -LiteralPath $recTxt -Raw
$requiredTerms = @(
    'Ctrl + Shift + Esc',
    'explorer.exe',
    'CloudOS.Recovery.exe restore-explorer-shell',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
)
foreach ($term in $requiredTerms) {
    if (-not $txtContent.Contains($term)) {
        throw "Termo obrigatorio ausente no guia de emergencia: $term"
    }
}
Write-Host "  [OK] Guia de emergencia offline verificado e integro." -ForegroundColor Green

Write-Host "`n>>> [PASS] CONTRATO 6/10: Recovery Executavel e Hotpath aprovados." -ForegroundColor Green
return [pscustomobject]@{
    Contract = "test-shell-recovery-v31-contract.ps1"
    Status   = "PASS"
}
