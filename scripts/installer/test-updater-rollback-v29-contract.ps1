<#
.SYNOPSIS
    Contrato de Validacao de Reversao Automatica (Rollback) do Updater (Etapa 9).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$distDir = Join-Path $repoRoot 'dist\CloudOS'
$maintScript = Join-Path $PSScriptRoot 'CloudOS.Maintenance.ps1'

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 5/5] Validacao de Reversao Automatica (Rollback)" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $distDir)) {
    & (Join-Path $PSScriptRoot 'build-cloudos-package.ps1') | Out-Null
}

$testRunId = [Guid]::NewGuid().ToString('N')
$testInstallDir = Join-Path $env:TEMP "cloudos-rollback-test-$testRunId"
$failingUpdateDir = Join-Path $env:TEMP "cloudos-failingupdate-$testRunId"

try {
    # 1. Instalar versao comprovada estavel N (21.0.0)
    Write-Host "[PASSO 1] Instalando versao N em $testInstallDir..." -ForegroundColor Yellow
    & $maintScript -Action install -PackageDir $distDir -InstallDir $testInstallDir -CreateStartShortcut:$false -CreateDesktopShortcut:$false | Out-Null

    $vN = (Get-Content -LiteralPath (Join-Path $testInstallDir 'version.json') -Raw | ConvertFrom-Json).productVersion
    Write-Host "[OK] Versao base instalada: $vN" -ForegroundColor Green

    # 2. Construir pacote sintetico N+1 valido em integridade, mas com Broker inoperante
    Write-Host "[PASSO 2] Montando pacote N+1 (21.1.0) com Broker com falha de startup..." -ForegroundColor Yellow
    Copy-Item -Path $distDir -Destination $failingUpdateDir -Recurse -Force

    # Atualizar version.json para 21.1.0
    $vNPlus1Data = [ordered]@{
        productName     = "CloudOS"
        productVersion  = "21.1.0"
        build           = 30
        gitSha          = "f000000000000000000000000000000000000000"
        protocolVersion = 21
        architecture    = "x64"
        channel         = "stable"
    }
    $vNPlus1Data | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $failingUpdateDir 'version.json') -Encoding UTF8

    # Substituir CloudOS.SystemBroker.exe por um binario/script que falha imediatamente no startup
    # Vamos usar cmd.exe renomeado ou arquivo que falha o handshake do named pipe
    $cmdExe = Join-Path $env:WINDIR 'System32\cmd.exe'
    Copy-Item -LiteralPath $cmdExe -Destination (Join-Path $failingUpdateDir 'CloudOS.SystemBroker.exe') -Force

    # Re-gerar o manifesto canônico para este pacote para que a verificacao de integridade inicial passe
    $allFiles = Get-ChildItem -Path $failingUpdateDir -Recurse -File | Where-Object { $_.Name -ne 'cloudos-package-manifest.json' } | Sort-Object FullName
    $manifestItems = [System.Collections.Generic.List[object]]::new()
    $totalBytes = 0
    foreach ($file in $allFiles) {
        $rel = $file.FullName.Substring($failingUpdateDir.Length).TrimStart('\', '/') -replace '\\', '/'
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifestItems.Add([ordered]@{ path = $rel; size = $file.Length; sha256 = $hash })
        $totalBytes += $file.Length
    }
    $newManifest = [ordered]@{
        schema          = 1
        product         = 'CloudOS Canonical Distribution Package'
        version         = "21.1.0"
        build           = 30
        gitSha          = "f000000000000000000000000000000000000000"
        protocolVersion = 21
        architecture    = "x64"
        generatedAt     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        totalFiles      = $manifestItems.Count
        totalBytes      = $totalBytes
        files           = $manifestItems
    }
    $json = $newManifest | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath (Join-Path $failingUpdateDir 'manifests\cloudos-package-manifest.json') -Value $json -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $failingUpdateDir 'cloudos-package-manifest.json') -Value $json -Encoding UTF8
    Write-Host "[OK] Pacote N+1 preparado com manifesto valido e broker falho." -ForegroundColor Green

    # 3. Disparar update: os arquivos serao staged, swapped, e no health check o broker falhara
    Write-Host "[PASSO 3] Disparando atualizacao (espera-se falha de health check e rollback automatico)..." -ForegroundColor Yellow
    $rollbackTriggered = $false
    try {
        & $maintScript -Action update -InstallDir $testInstallDir -NewPackageSource $failingUpdateDir -HealthCheckTimeoutSeconds 3
    } catch {
        $rollbackTriggered = $true
        Write-Host "  Excecao capturada como esperado: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    if (-not $rollbackTriggered) {
        throw "FALHA: O updater nao detectou a falha de health check!"
    }

    # 4. Validar que o rollback restaurou a versao original N (21.0.0)
    Write-Host "[PASSO 4] Verificando se o Rollback restaurou com sucesso a versao estavel N..." -ForegroundColor Yellow
    $restoredVersion = (Get-Content -LiteralPath (Join-Path $testInstallDir 'version.json') -Raw | ConvertFrom-Json).productVersion
    if ($restoredVersion -ne $vN) {
        throw "FALHA NO ROLLBACK: A versao restaurada e $restoredVersion, esperava $vN."
    }
    Write-Host "[OK] Versao restaurada com precisao: $restoredVersion" -ForegroundColor Green

    # 5. Validar integridade da versao restaurada
    $restoredCheck = & $maintScript -Action verify-install -InstallDir $testInstallDir
    if (-not $restoredCheck.IsValid) {
        throw "FALHA NO ROLLBACK: A instalacao restaurada contem arquivos corrompidos ou ausentes!"
    }
    Write-Host "[OK] Todos os $($restoredCheck.ValidCount) arquivos da versao $vN estao 100% integros pos-rollback." -ForegroundColor Green

    Write-Host ">> CONTRATO 5/5 APROVADO COM SUCESSO (Reversao Automatica Garantida)." -ForegroundColor Green
    return $true
} finally {
    if (Test-Path -LiteralPath $testInstallDir) {
        Remove-Item -LiteralPath $testInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $failingUpdateDir) {
        Remove-Item -LiteralPath $failingUpdateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
