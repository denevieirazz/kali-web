# test-shell-update-rollback-v31-contract.ps1
# Valida integridade e rollback de update no contexto de shell replacement

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 8/10] Validacao de Update e Rollback de Shell" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

$testInstallDir = Join-Path $env:LOCALAPPDATA 'CloudOS_Shell_Update_Test'
$maintScript = Join-Path $PSScriptRoot 'CloudOS.Maintenance.ps1'
$packageDir = Join-Path $PSScriptRoot '..\..\dist\CloudOS'

try {
    # 1. Instalar versao N
    Write-Host "[1/3] Instalando versao N em diretorio de teste..." -ForegroundColor Yellow
    & $maintScript -Action install -PackageDir $packageDir -InstallDir $testInstallDir | Out-Null
    Write-Host "  [OK] Versao N instalada com sucesso." -ForegroundColor Green

    # 2. Criar update corrompido (fail-closed check)
    Write-Host "[2/3] Testando rejeicao fail-closed de update adulterado..." -ForegroundColor Yellow
    $corruptPkgDir = Join-Path $env:LOCALAPPDATA 'CloudOS_Corrupt_Pkg_Test'
    New-Item -ItemType Directory -Path $corruptPkgDir -Force | Out-Null
    Copy-Item -Path "$packageDir\*" -Destination $corruptPkgDir -Recurse -Force
    # Corromper um binario
    Set-Content -LiteralPath (Join-Path $corruptPkgDir 'CloudOS.ShellBootstrap.exe') -Value 'CORRUPT_PAYLOAD'

    $rejected = $false
    try {
        & $maintScript -Action update -PackageDir $corruptPkgDir -InstallDir $testInstallDir | Out-Null
    } catch {
        $rejected = $true
        Write-Host "  [OK] Update corrompido rejeitado fail-closed: $($_.Exception.Message)" -ForegroundColor Green
    }
    if (-not $rejected) {
        throw "Update corrompido deveria ter sido rejeitado imediatamente"
    }

    # 3. Validar que a versao original N permaneceu intacta
    Write-Host "[3/3] Verificando integridade da versao N pos-rejeicao..." -ForegroundColor Yellow
    $bootstrapPath = Join-Path $testInstallDir 'CloudOS.ShellBootstrap.exe'
    if ((Get-Item -LiteralPath $bootstrapPath).Length -lt 10000) {
        throw "Binario original da versao N foi corrompido pelo update rejeitado"
    }
    Write-Host "  [OK] Versao N permaneceu 100% integra e valida." -ForegroundColor Green
} finally {
    # Limpeza
    & $maintScript -Action uninstall -InstallDir $testInstallDir -PurgeUserData -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -LiteralPath $corruptPkgDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n>>> [PASS] CONTRATO 8/10: Update e Rollback de Shell aprovados." -ForegroundColor Green
return [pscustomobject]@{
    Contract = "test-shell-update-rollback-v31-contract.ps1"
    Status   = "PASS"
}
