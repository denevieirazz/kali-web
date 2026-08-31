[CmdletBinding()]
param(
    [switch]$Run,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$uiRoot = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter nao foi encontrado no PATH. Instale Flutter 3.44.7 e habilite Windows desktop.'
}

$versionOutput = (& flutter --version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    throw "flutter --version falhou:`n$versionOutput"
}

Write-Host '[CloudOS Flutter V19] Flutter detectado:' -ForegroundColor Cyan
Write-Host $versionOutput.Trim()

Push-Location $uiRoot
try {
    & flutter config --enable-windows-desktop | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter config falhou.' }

    if (-not (Test-Path (Join-Path $uiRoot 'windows\CMakeLists.txt'))) {
        Write-Host '[CloudOS Flutter V19] Gerando host Windows padrao local...' -ForegroundColor Cyan
        & flutter create --platforms=windows --project-name cloudos_flutter_shell . | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'flutter create falhou.' }
    }

    Write-Host '[CloudOS Flutter V19] Resolvendo dependencias...' -ForegroundColor Cyan
    & flutter pub get | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get falhou.' }

    Write-Host '[CloudOS Flutter V19] Analyzer...' -ForegroundColor Cyan
    & flutter analyze --fatal-infos --fatal-warnings | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze falhou.' }

    Write-Host '[CloudOS Flutter V19] Widget tests...' -ForegroundColor Cyan
    & flutter test | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter test falhou.' }

    if (-not $SkipBuild) {
        Write-Host '[CloudOS Flutter V19] Build Windows Release...' -ForegroundColor Cyan
        & flutter build windows --release | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'flutter build windows falhou.' }
    }

    if ($Run) {
        Write-Host '[CloudOS Flutter V19] Abrindo preview. Nenhum Winlogon/shell activation sera alterado.' -ForegroundColor Green
        & flutter run -d windows
        if ($LASTEXITCODE -ne 0) { throw 'flutter run falhou.' }
    }
    else {
        Write-Host '[CloudOS Flutter V19] PASS' -ForegroundColor Green
    }
}
finally {
    Pop-Location
}
