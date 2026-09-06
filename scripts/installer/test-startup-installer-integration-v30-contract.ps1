<#
.SYNOPSIS
    Contrato de Validacao 5/5: Integracao do Startup com Instalador, Repair e Update (Etapa 10).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$maintScript = Join-Path $PSScriptRoot 'CloudOS.Maintenance.ps1'
$distDir = Join-Path $repoRoot 'dist\CloudOS'
$testInstallDir = Join-Path $env:LOCALAPPDATA 'CloudOS_Installer_Integration_Test'

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 5/5] Integracao Startup com Instalador/Repair" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

# Backup do estado original
$backupVal = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'CloudOS' -ErrorAction SilentlyContinue

try {
    # 1. Testar Instalacao com -EnableStartup
    Write-Host "[1/4] Testando instalacao com chave -EnableStartup..." -ForegroundColor Yellow
    if (Test-Path -LiteralPath $testInstallDir) {
        Remove-Item -LiteralPath $testInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    & $maintScript -Action install -PackageDir $distDir -InstallDir $testInstallDir -EnableStartup -CreateStartShortcut:$false

    $installedRun = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'CloudOS' -ErrorAction SilentlyContinue
    if (-not $installedRun) {
        throw "FALHA: Instalador com -EnableStartup nao registrou a chave HKCU\Run\CloudOS."
    }
    if ($installedRun -notmatch '-Startup') {
        throw "FALHA: Comando registrado pelo instalador nao contem '-Startup': $installedRun"
    }
    Write-Host "  [OK] Instalador registrou inicializacao automatica per-user: $installedRun" -ForegroundColor Green

    # 2. Testar Repair restaurando registro de startup adulterado
    Write-Host "[2/4] Adulterando comando de startup e testando reparo..." -ForegroundColor Yellow
    $tamperedCmd = 'powershell.exe -File "C:\corrompido\script.ps1"'
    Set-ItemProperty -Path $runKey -Name 'CloudOS' -Value $tamperedCmd

    & $maintScript -Action repair -InstallDir $testInstallDir -PackageDir $distDir

    $repairedRun = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'CloudOS' -ErrorAction SilentlyContinue
    $expectedExe = Join-Path $testInstallDir 'CloudOS.exe'
    if ($repairedRun -notmatch [regex]::Escape($expectedExe)) {
        throw "FALHA: Repair nao corrigiu o caminho adulterado de startup: $repairedRun"
    }
    Write-Host "  [OK] Repair detectou e corrigiu o registro de startup com sucesso." -ForegroundColor Green

    # 3. Testar Repair preservando opcao desativada do usuario (sem forcar ativacao)
    Write-Host "[3/4] Testando Repair com startup desativado pelo usuario..." -ForegroundColor Yellow
    Remove-ItemProperty -Path $runKey -Name 'CloudOS' -Force -ErrorAction SilentlyContinue

    & $maintScript -Action repair -InstallDir $testInstallDir -PackageDir $distDir

    $afterRepairDisabled = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'CloudOS' -ErrorAction SilentlyContinue
    if ($afterRepairDisabled) {
        throw "FALHA: Repair nao deve forcar ativacao de startup se o usuario o desativou: $afterRepairDisabled"
    }
    Write-Host "  [OK] Repair respeitou a escolha do usuario e nao forcou inicializacao." -ForegroundColor Green

    # 4. Desinstalacao e verificacao de Winlogon
    Write-Host "[4/4] Limpando ambiente de teste e verificando Winlogon..." -ForegroundColor Yellow
    & $maintScript -Action uninstall -InstallDir $testInstallDir -PurgeUserData

    $hklmShell = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'Shell' -ErrorAction SilentlyContinue
    if ($hklmShell -ne 'explorer.exe') {
        throw "VIOLACAO GRAVE: HKLM Shell alterado: $hklmShell"
    }
    $hkcuShell = (Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'Shell' -ErrorAction SilentlyContinue
    if ($hkcuShell) {
        throw "VIOLACAO GRAVE: HKCU Shell configurado indevidamente: $hkcuShell"
    }
    Write-Host "  [OK] Shell oficial do Windows (explorer.exe) estritamente preservado." -ForegroundColor Green

} finally {
    if (Test-Path -LiteralPath $testInstallDir) {
        Remove-Item -LiteralPath $testInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($backupVal) {
        Set-ItemProperty -Path $runKey -Name 'CloudOS' -Value $backupVal
    } else {
        Remove-ItemProperty -Path $runKey -Name 'CloudOS' -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n>>> [PASS] CONTRATO 5/5: Integracao do Startup com Instalador e Repair aprovada." -ForegroundColor Green
return [pscustomobject]@{
    Contract = "test-startup-installer-integration-v30-contract.ps1"
    Status   = "PASS"
}
