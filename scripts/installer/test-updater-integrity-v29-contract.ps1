<#
.SYNOPSIS
    Contrato de Validacao de Integridade Fail-Closed do Updater (Etapa 9).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$distDir = Join-Path $repoRoot 'dist\CloudOS'
$maintScript = Join-Path $PSScriptRoot 'CloudOS.Maintenance.ps1'

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 4/5] Validacao de Updater Fail-Closed" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $distDir)) {
    & (Join-Path $PSScriptRoot 'build-cloudos-package.ps1') | Out-Null
}

$testRunId = [Guid]::NewGuid().ToString('N')
$testInstallDir = Join-Path $env:TEMP "cloudos-updater-test-$testRunId"
$fakeUpdateDir = Join-Path $env:TEMP "cloudos-fakeupdate-$testRunId"

try {
    # 1. Instalar versao estavel N
    Write-Host "[PASSO 1] Instalando versao N em $testInstallDir..." -ForegroundColor Yellow
    & $maintScript -Action install -PackageDir $distDir -InstallDir $testInstallDir -CreateStartShortcut:$false -CreateDesktopShortcut:$false | Out-Null

    $vN = (Get-Content -LiteralPath (Join-Path $testInstallDir 'version.json') -Raw | ConvertFrom-Json).productVersion
    Write-Host "[OK] Versao base instalada: $vN" -ForegroundColor Green

    # 2. Criar pacote sintetico de atualizacao N+1 com um arquivo adulterado (hash incorreto)
    Write-Host "[PASSO 2] Criando pacote sintetico de update N+1 com hash adulterado..." -ForegroundColor Yellow
    Copy-Item -Path $distDir -Destination $fakeUpdateDir -Recurse -Force

    # Adulterar CloudOS.SystemBroker.exe sem atualizar o manifesto para simular pacote corrompido / ataque man-in-the-middle
    Set-Content -LiteralPath (Join-Path $fakeUpdateDir 'CloudOS.SystemBroker.exe') -Value "MALICIOUS_OR_CORRUPT_PAYLOAD" -Force

    # 3. Tentar executar update com o pacote invalido
    Write-Host "[PASSO 3] Disparando update com payload invalido (deve ser rejeitado fail-closed)..." -ForegroundColor Yellow
    $updateFailed = $false
    $caughtMessage = ""
    try {
        & $maintScript -Action update -InstallDir $testInstallDir -UpdatePackageDir $fakeUpdateDir
    } catch {
        $updateFailed = $true
        $caughtMessage = $_.Exception.Message
    }

    if (-not $updateFailed) {
        throw "FALHA DE SEGURANCA: O updater aceitou um pacote corrompido/adulterado!"
    }
    if ($caughtMessage -notmatch 'UPDATE_REJECTED') {
        throw "FALHA: O updater nao lancou o erro esperado de UPDATE_REJECTED. Mensagem: $caughtMessage"
    }
    Write-Host "[OK] Pacote invalido REJEITADO com sucesso: $caughtMessage" -ForegroundColor Green

    # 4. Validar que a versao original N permaneceu 100% integra e intocada
    Write-Host "[PASSO 4] Verificando se a instalacao original N permaneceu integra..." -ForegroundColor Yellow
    $postCheck = & $maintScript -Action verify-install -InstallDir $testInstallDir
    if (-not $postCheck.IsValid) {
        throw "FALHA: A instalacao original foi danificada pela tentativa de update invalida!"
    }
    $vAfter = (Get-Content -LiteralPath (Join-Path $testInstallDir 'version.json') -Raw | ConvertFrom-Json).productVersion
    if ($vAfter -ne $vN) {
        throw "FALHA: A versao foi alterada indevidamente ($vAfter != $vN)."
    }
    Write-Host "[OK] Instalacao original $vN permaneceu 100% valida e inalterada." -ForegroundColor Green

    Write-Host ">> CONTRATO 4/5 APROVADO COM SUCESSO (Updater Fail-Closed Garantido)." -ForegroundColor Green
    return $true
} finally {
    if (Test-Path -LiteralPath $testInstallDir) {
        Remove-Item -LiteralPath $testInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $fakeUpdateDir) {
        Remove-Item -LiteralPath $fakeUpdateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
