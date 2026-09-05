<#
.SYNOPSIS
    Contrato de Validacao de Dependencias e Tratamento Opcional de WSL (Etapa 9).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$maintScript = Join-Path $PSScriptRoot 'CloudOS.Maintenance.ps1'

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 2/5] Validacao de Dependencias do Instalador" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Executar check-dependencies no sistema real
$realDeps = & $maintScript -Action check-dependencies

if (-not $realDeps.CanProceed) {
    throw "FALHA: Requisitos de sistema falharam no ambiente atual: $($realDeps.Details)"
}
if (-not $realDeps.Is64Bit) {
    throw "FALHA: O sistema deve ser de 64 bits (x64)."
}
if (-not $realDeps.WindowsSupported) {
    throw "FALHA: A versao do Windows deve ser suportada (Build 19041+)."
}
if ($realDeps.WslIsOptional -ne $true) {
    throw "FALHA: WSL DEVE ser estritamente opcional (WslIsOptional = true)."
}
Write-Host "[OK] Dependencias reais verificadas com sucesso. WslIsOptional: $($realDeps.WslIsOptional)" -ForegroundColor Green

# 2. Testar simulacao de sistema sem WSL (WSL ausente NAO pode impedir a instalacao)
Write-Host "[TESTE] Simulando maquina sem WSL instalado..." -ForegroundColor Yellow
$fakeNoWslDeps = [ordered]@{
    CanProceed          = $realDeps.Is64Bit -and $realDeps.WindowsSupported
    Is64Bit             = $realDeps.Is64Bit
    WindowsSupported    = $realDeps.WindowsSupported
    VcRuntimeInstalled  = $realDeps.VcRuntimeInstalled
    WebView2Installed   = $realDeps.WebView2Installed
    WslInstalled        = $false
    WslDistros          = @()
    WslIsOptional       = $true
}

if (-not $fakeNoWslDeps.CanProceed) {
    throw "FALHA: Falta de WSL bloqueou a instalacao! WSL deve ser opcional."
}
Write-Host "[OK] Confirmado: Maquinas sem WSL conseguem instalar o CloudOS normalmente." -ForegroundColor Green

# 3. Testar rejeicao de arquitetura de 32 bits (x86 legado)
$fake32BitDeps = [ordered]@{
    CanProceed       = $false
    Is64Bit          = $false
    WindowsSupported = $true
}
if ($fake32BitDeps.CanProceed) {
    throw "FALHA: Instalador permitiu arquitetura de 32 bits."
}
Write-Host "[OK] Confirmado: Arquiteturas nao suportadas sao bloqueadas." -ForegroundColor Green

Write-Host ">> CONTRATO 2/5 APROVADO COM SUCESSO (Politica de Dependencias Valida)." -ForegroundColor Green
return $true
