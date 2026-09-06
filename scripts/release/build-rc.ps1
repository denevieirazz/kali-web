[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [string]$Architecture = 'x64',
    [switch]$SkipTests,
    [switch]$SkipInstaller,
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  CloudOS Release Pipeline: Release Candidate 1.1     " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# 1. Carregar e validar version.json
$versionFile = Join-Path $repoRoot 'version.json'
if (-not (Test-Path -LiteralPath $versionFile)) {
    throw "Arquivo de versao ausente: $versionFile"
}
$versionData = Get-Content -LiteralPath $versionFile -Raw | ConvertFrom-Json
$productVersion = [string]$versionData.productVersion
$buildNumber = [int]$versionData.buildNumber
$gitSha = (git rev-parse HEAD).Trim()

Write-Host "[1/7] Validando Metadados de Versao..." -ForegroundColor Yellow
Write-Host "  Produto:       $($versionData.productName)" -ForegroundColor Green
Write-Host "  Versao:        $productVersion" -ForegroundColor Green
Write-Host "  Build:         $buildNumber" -ForegroundColor Green
Write-Host "  Commit Git:    $gitSha" -ForegroundColor Green
Write-Host "  Arquitetura:   $Architecture" -ForegroundColor Green

# 2. Localizar ferramentas de build
Write-Host "[2/7] Inspecionando Ambiente de Ferramentas..." -ForegroundColor Yellow

$flutterCmd = Get-Command 'flutter' -ErrorAction SilentlyContinue
if (-not $flutterCmd) { throw "Flutter SDK nao encontrado no PATH." }
Write-Host "  Flutter: $($flutterCmd.Source)" -ForegroundColor Green

function Find-InnoSetupCompiler {
    $cmd = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

$isccExe = Find-InnoSetupCompiler
if (-not $SkipInstaller) {
    if (-not $isccExe) {
        throw "Inno Setup Compiler (ISCC.exe) nao encontrado. Instale via 'winget install JRSoftware.InnoSetup' ou use -SkipInstaller."
    }
    Write-Host "  Inno Setup: $isccExe" -ForegroundColor Green
} else {
    Write-Host "  Inno Setup: IGNORADO (-SkipInstaller)" -ForegroundColor DarkGray
}

# 3. Compilar Binarios Nativos C++/Win32
Write-Host "[3/7] Compilando Binarios Nativos C++/Win32 ($Configuration)..." -ForegroundColor Yellow
$nativeBuildCmd = Join-Path $repoRoot 'scripts\native\build-cloudos-native.cmd'
& cmd.exe /c "`"$nativeBuildCmd`" $Configuration"
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao compilar binarios nativos do CloudOS (Exit code $LASTEXITCODE)."
}

# 4. Executar Testes Automatizados (se nao ignorados)
if (-not $SkipTests) {
    Write-Host "[4/7] Executando Testes e Analise Estatica do Flutter..." -ForegroundColor Yellow
    $flutterDir = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell'
    
    Push-Location $flutterDir
    try {
        Write-Host "  Executando flutter analyze..." -ForegroundColor Cyan
        & flutter analyze
        if ($LASTEXITCODE -ne 0) { throw "flutter analyze reportou problemas." }

        Write-Host "  Executando flutter test..." -ForegroundColor Cyan
        & flutter test
        if ($LASTEXITCODE -ne 0) { throw "flutter test falhou." }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "[4/7] Testes automatizados ignorados (-SkipTests)." -ForegroundColor DarkGray
}

# 5. Compilar Flutter Windows Release
Write-Host "[5/7] Compilando Flutter Shell Windows Release..." -ForegroundColor Yellow
$flutterDir = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell'
Push-Location $flutterDir
try {
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "Falha no build do Flutter Windows (Exit code $LASTEXITCODE)." }
} finally {
    Pop-Location
}

# 6. Realizar Staging Integrado e Pacote Canonico
Write-Host "[6/7] Montando Pacote de Distribuicao Canonico..." -ForegroundColor Yellow
$stageScript = Join-Path $repoRoot 'scripts\stage-integrated-v21.ps1'
& pwsh.exe -NoProfile -File $stageScript
if ($LASTEXITCODE -ne 0) { throw "Falha no staging integrado (stage-integrated-v21.ps1)." }

$packageScript = Join-Path $repoRoot 'scripts\installer\build-cloudos-package.ps1'
& pwsh.exe -NoProfile -File $packageScript
if ($LASTEXITCODE -ne 0) { throw "Falha na geracao do pacote canonico (build-cloudos-package.ps1)." }

# 7. Compilar Instalador Inno Setup Oficial
$releasesBaseDir = if ($OutputDir) { $OutputDir } else { Join-Path $repoRoot "dist\releases\$productVersion" }
if (-not (Test-Path -LiteralPath $releasesBaseDir)) {
    New-Item -ItemType Directory -Path $releasesBaseDir -Force | Out-Null
}

$installerExe = Join-Path $releasesBaseDir "CloudOS-Setup-$productVersion-$Architecture.exe"

if (-not $SkipInstaller) {
    Write-Host "[7/7] Compilando Instalador Inno Setup Oficial..." -ForegroundColor Yellow
    $issScript = Join-Path $repoRoot 'scripts\installer\CloudOS.iss'
    
    & $isccExe "$issScript"
    if ($LASTEXITCODE -ne 0) { throw "Falha na compilacao do Inno Setup (Exit code $LASTEXITCODE)." }

    if (-not (Test-Path -LiteralPath $installerExe)) {
        throw "Instalador esperado nao foi gerado em: $installerExe"
    }

    $setupItem = Get-Item -LiteralPath $installerExe
    $setupHash = (Get-FileHash -LiteralPath $installerExe -Algorithm SHA256).Hash.ToLowerInvariant()
    $setupShaFile = "$installerExe.sha256"
    Set-Content -LiteralPath $setupShaFile -Value "$setupHash *$($setupItem.Name)" -Encoding UTF8

    Write-Host "  Instalador: $installerExe" -ForegroundColor Green
    Write-Host "  Tamanho:    $([math]::Round($setupItem.Length / 1MB, 2)) MB" -ForegroundColor Green
    Write-Host "  SHA256:     $setupHash" -ForegroundColor Green

    # Gerar SHA256SUMS.txt consolidado
    $sumsFile = Join-Path $releasesBaseDir 'SHA256SUMS.txt'
    $sumLines = @(
        "$setupHash  $($setupItem.Name)"
    )

    # Copiar pacote zip caso exista
    $zipSource = Join-Path $repoRoot "dist\CloudOS-v$productVersion-x64.zip"
    if (Test-Path -LiteralPath $zipSource) {
        Copy-Item -LiteralPath $zipSource -Destination (Join-Path $releasesBaseDir "CloudOS-v$productVersion-x64.zip") -Force
        $zipItem = Get-Item -LiteralPath (Join-Path $releasesBaseDir "CloudOS-v$productVersion-x64.zip")
        $zipHash = (Get-FileHash -LiteralPath $zipItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $sumLines += "$zipHash  $($zipItem.Name)"
    }

    Set-Content -LiteralPath $sumsFile -Value ($sumLines -join "`r`n") -Encoding UTF8
    Write-Host "  Checksums:  $sumsFile" -ForegroundColor Green

    # Atualizar informacoes no update-feed do release
    $feedFile = Join-Path $releasesBaseDir 'update-feed.json'
    $feedContent = [ordered]@{
        schema       = 1
        product      = 'CloudOS'
        channel      = 'rc'
        updatedAt    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        releases     = @(
            [ordered]@{
                version          = $productVersion
                build            = $buildNumber
                releaseDate      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                channel          = 'rc'
                minWindowsBuild  = 19041
                installerFileName = $setupItem.Name
                installerUrl     = "https://github.com/doug-cloud/CloudOS/releases/download/v$productVersion/$($setupItem.Name)"
                sha256           = $setupHash
                mandatory        = $false
                releaseNotes     = "CloudOS Release Candidate 1.1: Release Engineering pass with real Inno Setup installer, hardened atomic updater, schema v2 preferences, and crash protection."
            }
        )
    }
    $feedContent | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $feedFile -Encoding UTF8
    Write-Host "  Update Feed:$feedFile" -ForegroundColor Green
} else {
    Write-Host "[7/7] Compilacao de instalador ignorada (-SkipInstaller)." -ForegroundColor DarkGray
}

Write-Host "`n[SUCESSO] Pipeline de Release RC1.1 finalizado com exito!" -ForegroundColor Green
