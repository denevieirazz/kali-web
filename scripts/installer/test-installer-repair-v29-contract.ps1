<#
.SYNOPSIS
    Contrato de Validacao de Reparacao (Repair) e Preservacao de Configuracao (Etapa 9).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$distDir = Join-Path $repoRoot 'dist\CloudOS'
$maintScript = Join-Path $PSScriptRoot 'CloudOS.Maintenance.ps1'

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 3/5] Validacao de Reparo e Integridade" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Garantir que dist/CloudOS existe
if (-not (Test-Path -LiteralPath $distDir)) {
    & (Join-Path $PSScriptRoot 'build-cloudos-package.ps1') | Out-Null
}

$testRunId = [Guid]::NewGuid().ToString('N')
$testInstallDir = Join-Path $env:TEMP "cloudos-repair-test-$testRunId"

try {
    # 2. Instalar em diretorio isolado
    Write-Host "[PASSO 1] Instalando versao de teste em $testInstallDir..." -ForegroundColor Yellow
    & $maintScript -Action install -PackageDir $distDir -InstallDir $testInstallDir -CreateStartShortcut:$false -CreateDesktopShortcut:$false | Out-Null

    # 3. Verificar estado integro
    $initialCheck = & $maintScript -Action verify-install -InstallDir $testInstallDir
    if (-not $initialCheck.IsValid -or $initialCheck.CorruptCount -ne 0 -or $initialCheck.MissingCount -ne 0) {
        throw "FALHA: A instalacao inicial ja apresentou defeitos de integridade."
    }
    Write-Host "[OK] Instalacao inicial 100% valida ($($initialCheck.ValidCount) arquivos)." -ForegroundColor Green

    # 4. Injetar corrupcao intencional
    Write-Host "[PASSO 2] Injetando corrupcoes intencionais (adulterar CloudOS.exe e deletar data/app.so)..." -ForegroundColor Yellow
    $corruptTargetExe = Join-Path $testInstallDir 'CloudOS.exe'
    Set-Content -LiteralPath $corruptTargetExe -Value "TAMPERED_BINARY_PAYLOAD_FOR_TESTING" -Force

    $deleteTargetAsset = Join-Path $testInstallDir 'data\app.so'
    Remove-Item -LiteralPath $deleteTargetAsset -Force

    # 5. Confirmar que verify-install detecta o problema
    $damagedCheck = & $maintScript -Action verify-install -InstallDir $testInstallDir
    if ($damagedCheck.IsValid) {
        throw "FALHA: O verificador nao detectou os arquivos adulterados/ausentes!"
    }
    if ($damagedCheck.MissingCount -lt 1 -or $damagedCheck.CorruptCount -lt 1) {
        throw "FALHA: Contagem de defeitos incorreta: Ausentes=$($damagedCheck.MissingCount), Corrompidos=$($damagedCheck.CorruptCount)"
    }
    Write-Host "[OK] Diagnostico detectou com precisao: $($damagedCheck.MissingCount) ausente, $($damagedCheck.CorruptCount) adulterado." -ForegroundColor Green

    # 6. Executar Reparo
    Write-Host "[PASSO 3] Executando rotina de Reparo do CloudOS..." -ForegroundColor Yellow
    $repairResult = & $maintScript -Action repair -InstallDir $testInstallDir -PackageDir $distDir
    if (-not $repairResult.Repaired) {
        throw "FALHA: A rotina de reparo nao marcou o reparo como efetuado."
    }

    # 7. Verificar integridade pos-reparo
    $postRepairCheck = & $maintScript -Action verify-install -InstallDir $testInstallDir
    if (-not $postRepairCheck.IsValid -or $postRepairCheck.MissingCount -ne 0 -or $postRepairCheck.CorruptCount -ne 0) {
        throw "FALHA: O produto continua invalido apos o reparo!"
    }
    Write-Host "[OK] Reparo concluido com sucesso. Todos os $($postRepairCheck.ValidCount) arquivos estao 100% restaurados." -ForegroundColor Green

    # 8. Testar desinstalacao limpa
    Write-Host "[PASSO 4] Testando desinstalacao limpa..." -ForegroundColor Yellow
    & $maintScript -Action uninstall -InstallDir $testInstallDir | Out-Null
    if (Test-Path -LiteralPath $testInstallDir) {
        throw "FALHA: Pasta de instalacao ainda existe apos desinstalacao."
    }
    Write-Host "[OK] Desinstalacao limpa confirmada." -ForegroundColor Green

    Write-Host ">> CONTRATO 3/5 APROVADO COM SUCESSO (Reparo e Integridade 100%)." -ForegroundColor Green
    return $true
} finally {
    if (Test-Path -LiteralPath $testInstallDir) {
        Remove-Item -LiteralPath $testInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
