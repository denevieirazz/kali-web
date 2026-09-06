<#
.SYNOPSIS
    Executor Completo da Suite de Contratos da Etapa 10 (Startup Automatico Seguro + Fallback Explorer).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$contracts = @(
    'test-startup-registration-v30-contract.ps1',
    'test-startup-single-instance-v30-contract.ps1',
    'test-startup-recovery-v30-contract.ps1',
    'test-startup-uninstall-cleanup-v30-contract.ps1',
    'test-startup-installer-integration-v30-contract.ps1'
)

$results = [System.Collections.Generic.List[psobject]]::new()
$passed = 0
$total = $contracts.Count

Write-Host "=========================================================" -ForegroundColor Magenta
Write-Host " EXECUTANDO SUITE COMPLETA DE STARTUP & FALLBACK (ETAPA 10)" -ForegroundColor Magenta
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
    Status  = "ALL_PASSED"
    Results = $results
}
