param(
    [switch]$AllowNonCi
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$previousDataDir = $env:CLOUDOS_DATA_DIR
$smokeDataRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('cloudos-host-smoke-data-' + [Guid]::NewGuid().ToString('N'))
$smokeScript = Join-Path $PSScriptRoot 'test-native-browser-host-smoke.ps1'

if (-not (Test-Path -LiteralPath $smokeScript)) {
    throw 'SMOKE_SCRIPT_MISSING: test-native-browser-host-smoke.ps1 não foi encontrado.'
}

try {
    New-Item -ItemType Directory -Force -Path $smokeDataRoot | Out-Null
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $resolvedDataRoot = [System.IO.Path]::GetFullPath($smokeDataRoot)
    if (-not $resolvedDataRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'SMOKE_DATA_DIR_NOT_TEMP: diretório efêmero não está sob o temp do Windows.'
    }

    $env:CLOUDOS_DATA_DIR = $resolvedDataRoot
    if ($AllowNonCi) {
        & $smokeScript -AllowNonCi
    } else {
        & $smokeScript
    }
    if ($LASTEXITCODE -ne 0) {
        throw "HOST_SMOKE_FAILED: smoke encerrou com código $LASTEXITCODE."
    }

    $databaseFiles = @(Get-ChildItem -LiteralPath $resolvedDataRoot -Recurse -File -Filter '*.db' -ErrorAction SilentlyContinue)
    if ($databaseFiles.Count -eq 0) {
        throw 'SMOKE_DATA_DIR_UNUSED: backend não criou banco no diretório efêmero.'
    }

    Write-Host 'PASS isolated native browser host smoke'
}
finally {
    if ($null -eq $previousDataDir) {
        Remove-Item Env:CLOUDOS_DATA_DIR -ErrorAction SilentlyContinue
    } else {
        $env:CLOUDOS_DATA_DIR = $previousDataDir
    }

    if (Test-Path -LiteralPath $smokeDataRoot) {
        Remove-Item -LiteralPath $smokeDataRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
