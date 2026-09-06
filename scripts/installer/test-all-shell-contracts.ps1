<#
.SYNOPSIS
    Executor Completo da Suite de Contratos da Etapa 11 (Shell Replacement Seguro + Fallback Automatico + Recovery).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$contracts = @(
    'test-shell-mechanism-v31-contract.ps1',
    'test-shell-backup-v31-contract.ps1',
    'test-shell-health-gate-v31-contract.ps1',
    'test-shell-explorer-fallback-v31-contract.ps1',
    'test-shell-crash-loop-v31-contract.ps1',
    'test-shell-recovery-v31-contract.ps1',
    'test-shell-uninstall-restore-v31-contract.ps1',
    'test-shell-update-rollback-v31-contract.ps1',
    'test-shell-session-v31-contract.ps1',
    'test-shell-security-v31-contract.ps1'
)

$results = [System.Collections.Generic.List[psobject]]::new()
$passed = 0
$total = $contracts.Count

Write-Host "=========================================================" -ForegroundColor Magenta
Write-Host " EXECUTANDO SUITE COMPLETA DE SHELL REPLACEMENT (ETAPA 11)" -ForegroundColor Magenta
Write-Host "=========================================================" -ForegroundColor Magenta

foreach ($contract in $contracts) {
    $scriptPath = Join-Path $PSScriptRoot $contract
    Write-Host "`n>>> Executando: $contract" -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $res = & $scriptPath
        $sw.Stop()
        $passed++
        $results.Add([pscustomobject]@{
            Contract = $contract
            Status   = "PASS"
            Duration = "$([Math]::Round($sw.Elapsed.TotalSeconds, 2))s"
        })
        Write-Host ">>> [PASS] $contract ($([Math]::Round($sw.Elapsed.TotalSeconds, 2))s)" -ForegroundColor Green
    } catch {
        $sw.Stop()
        $results.Add([pscustomobject]@{
            Contract = $contract
            Status   = "FAIL"
            Duration = "$([Math]::Round($sw.Elapsed.TotalSeconds, 2))s"
        })
        Write-Host ">>> [FAIL] $contract : $_" -ForegroundColor Red
        throw "FALHA no contrato $contract"
    }
}

Write-Host "`n=========================================================" -ForegroundColor Green
Write-Host " RESULTADO FINAL: $passed / $total CONTRATOS APROVADOS (100% PASS)" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green

$results | Format-Table -AutoSize

return [pscustomobject]@{
    Passed  = $passed
    Total   = $total
    Success = ($passed -eq $total)
    Results = $results
}
