# test-shell-uninstall-restore-v31-contract.ps1
# Valida que o uninstall obrigatoriamente restaura o Windows Explorer antes de remover arquivos

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 7/10] Validacao de Restauracao de Shell no Uninstall" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

$testInstallDir = Join-Path $env:LOCALAPPDATA 'CloudOS_Shell_Uninstall_Test'
$maintScript = Join-Path $PSScriptRoot 'CloudOS.Maintenance.ps1'

# 1. Preparar cenario com instalacao em pasta de teste
Write-Host "[1/4] Instalando versao de teste em diretorio isolado..." -ForegroundColor Yellow
$packageDir = Join-Path $PSScriptRoot '..\..\dist\CloudOS'
& $maintScript -Action install -PackageDir $packageDir -InstallDir $testInstallDir | Out-Null

if (-not (Test-Path -LiteralPath $testInstallDir)) {
    throw "Falha ao preparar instalacao de teste para uninstall"
}
Write-Host "  [OK] Ambiente de teste montado." -ForegroundColor Green

# 2. Simular configuracao de shell de teste em HKCU Winlogon
Write-Host "[2/4] Simulando presenca de custom shell policy..." -ForegroundColor Yellow
$policyPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
if (-not (Test-Path -LiteralPath $policyPath)) {
    New-Item -Path $policyPath -Force | Out-Null
}
$dummyShell = (Join-Path $testInstallDir 'CloudOS.ShellBootstrap.exe')
Set-ItemProperty -Path $policyPath -Name 'Shell' -Value $dummyShell

$checkBefore = (Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'Shell' -ErrorAction SilentlyContinue
if (-not $checkBefore) {
    throw "Falha ao simular politica de shell"
}
Write-Host "  [OK] Politica de shell configurada temporariamente para o teste." -ForegroundColor Green

# 3. Executar desinstalacao
Write-Host "[3/4] Executando Invoke-Uninstall..." -ForegroundColor Yellow
& $maintScript -Action uninstall -InstallDir $testInstallDir -PurgeUserData | Out-Null
Write-Host "  [OK] Desinstalacao finalizada." -ForegroundColor Green

# 4. Validar que o shell foi expurgado e restaurado para o Explorer oficial
Write-Host "[4/4] Validando se a politica de shell foi purgada antes do término..." -ForegroundColor Yellow
$checkAfter = (Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'Shell' -ErrorAction SilentlyContinue
if ($checkAfter) {
    # Tentar limpar para seguranca
    Remove-ItemProperty -Path $policyPath -Name 'Shell' -Force -ErrorAction SilentlyContinue
    throw "BLOCKER: O uninstall terminou mas a chave de custom shell ainda existia apontando para binario inexistente!"
}
Write-Host "  [OK] Politica de shell purgada com sucesso. Zero risco de tela preta pós-uninstall." -ForegroundColor Green

# Validar que HKLM Winlogon Shell permanece explorer.exe
$hklmWinlogon = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
if ($hklmWinlogon.Shell -ne 'explorer.exe') {
    throw "HKLM Winlogon Shell violado: $($hklmWinlogon.Shell)"
}
Write-Host "  [OK] Shell oficial do Windows (explorer.exe) estritamente preservado." -ForegroundColor Green

Write-Host "`n>>> [PASS] CONTRATO 7/10: Restauracao de Shell no Uninstall aprovada." -ForegroundColor Green
return [pscustomobject]@{
    Contract = "test-shell-uninstall-restore-v31-contract.ps1"
    Status   = "PASS"
}
