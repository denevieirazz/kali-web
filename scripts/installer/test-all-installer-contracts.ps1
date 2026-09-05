<#
.SYNOPSIS
    Executor Completo da Suite de Contratos da Etapa 9 (Installer, Repair, Update, Rollback).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$contracts = @(
    'test-installer-layout-v29-contract.ps1',
    'test-installer-dependencies-v29-contract.ps1',
    'test-installer-repair-v29-contract.ps1',
    'test-updater-integrity-v29-contract.ps1',
    'test-updater-rollback-v29-contract.ps1'
)

$passed = 0
$total = $contracts.Count

Write-Host "=========================================================" -ForegroundColor Magenta
Write-Host " EXECUTANDO SUITE COMPLETA DE CONTRATOS DO INSTALADOR (ETAPA 9)" -ForegroundColor Magenta
Write-Host "=========================================================" -ForegroundColor Magenta

foreach ($contract in $contracts) {
    $scriptPath = Join-Path $PSScriptRoot $contract
    Write-Host "`n>>> Executando: $contract" -ForegroundColor Cyan
    $result = & $scriptPath
    if ($result -eq $true) {
        $passed++
        Write-Host ">>> [PASS] $contract" -ForegroundColor Green
    } else {
        throw "FALHA no contrato $contract"
    }
}

Write-Host "`n=========================================================" -ForegroundColor Green
Write-Host " RESULTADO FINAL: $passed / $total CONTRATOS APROVADOS (100% PASS)" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green

return [pscustomobject]@{
    Passed = $passed
    Total  = $total
    Status = "ALL_PASSED"
}
