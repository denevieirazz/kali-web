<#
.SYNOPSIS
    Contrato de Validacao 4/5: Limpeza Total de Startup na Desinstalacao (Etapa 10).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$maintScript = Join-Path $PSScriptRoot 'CloudOS.Maintenance.ps1'
$testInstallDir = Join-Path $env:LOCALAPPDATA 'CloudOS_Uninstall_Test'

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 4/5] Validacao de Limpeza de Startup Uninstall" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startupFolder = [Environment]::GetFolderPath('Startup')
$startupLnk = Join-Path $startupFolder 'CloudOS.lnk'

# Salvar valor previo se existir
$backupVal = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'CloudOS' -ErrorAction SilentlyContinue

try {
    # 1. Preparar diretorio de teste e simular entradas ativas de startup
    Write-Host "[1/4] Preparando cenario de teste com startup ativado..." -ForegroundColor Yellow
    if (-not (Test-Path -LiteralPath $testInstallDir)) {
        New-Item -ItemType Directory -Path $testInstallDir -Force | Out-Null
    }

    # Criar chave de Run
    $dummyCmd = 'powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "C:\dummy\start-cloudos-v21-integrated.ps1" -Startup'
    Set-ItemProperty -Path $runKey -Name 'CloudOS' -Value $dummyCmd

    # Criar atalho na pasta Startup
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($startupLnk)
    $sc.TargetPath = 'powershell.exe'
    $sc.Arguments = '-NoProfile -Command "exit 0"'
    $sc.Save()

    # 2. Confirmar presenca de ambas as entradas
    Write-Host "[2/4] Confirmando presenca das entradas de inicializacao antes do uninstall..." -ForegroundColor Yellow
    $regCheck = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'CloudOS' -ErrorAction SilentlyContinue
    if (-not $regCheck) {
        throw "FALHA: Nao foi possivel criar a chave de teste HKCU\Run\CloudOS."
    }
    if (-not (Test-Path -LiteralPath $startupLnk)) {
        throw "FALHA: Nao foi possivel criar o atalho de teste na pasta Startup."
    }
    Write-Host "  [OK] Entradas de teste registradas (HKCU\Run e shell:startup)." -ForegroundColor Green

    # 3. Executar desinstalacao com CloudOS.Maintenance.ps1
    Write-Host "[3/4] Executando Invoke-Uninstall via script de manutencao..." -ForegroundColor Yellow
    & $maintScript -Action uninstall -InstallDir $testInstallDir -PurgeUserData

    # 4. Validar remocao completa
    Write-Host "[4/4] Validando expurgo total de entradas de startup..." -ForegroundColor Yellow
    $regAfter = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'CloudOS' -ErrorAction SilentlyContinue
    if ($regAfter) {
        throw "FALHA: HKCU\Run\CloudOS ainda existe apos desinstalacao: $regAfter"
    }
    Write-Host "  [OK] HKCU\Run\CloudOS purgado com sucesso." -ForegroundColor Green

    if (Test-Path -LiteralPath $startupLnk) {
        throw "FALHA: Atalho na pasta Startup ainda existe apos desinstalacao: $startupLnk"
    }
    Write-Host "  [OK] Atalho shell:startup purgado com sucesso." -ForegroundColor Green

    # Confirmar chaves de Winlogon
    $hklmShell = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'Shell' -ErrorAction SilentlyContinue
    if ($hklmShell -ne 'explorer.exe') {
        throw "VIOLACAO GRAVE: HKLM Shell foi adulterado: $hklmShell"
    }
    Write-Host "  [OK] Winlogon Shell permanece explorer.exe intocado." -ForegroundColor Green

} finally {
    # Limpar diretorio de teste
    if (Test-Path -LiteralPath $testInstallDir) {
        Remove-Item -LiteralPath $testInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $startupLnk) {
        Remove-Item -LiteralPath $startupLnk -Force -ErrorAction SilentlyContinue
    }
    # Restaurar backup se existia
    if ($backupVal) {
        Set-ItemProperty -Path $runKey -Name 'CloudOS' -Value $backupVal
    } else {
        Remove-ItemProperty -Path $runKey -Name 'CloudOS' -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n>>> [PASS] CONTRATO 4/5: Limpeza total de inicializacao no uninstall aprovada." -ForegroundColor Green
return [pscustomobject]@{
    Contract = "test-startup-uninstall-cleanup-v30-contract.ps1"
    Status   = "PASS"
}
