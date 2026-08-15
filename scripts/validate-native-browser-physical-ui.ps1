param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(100, 125, 150)]
    [int]$ExpectedScale,
    [ValidateSet('dark', 'light', 'system')]
    [string]$Theme = 'dark',
    [string]$OutputRoot = '.\test-results\native-browser-physical-ui-local'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'require-powershell7-windows.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$output = Join-Path $repoRoot (Join-Path $OutputRoot ("scale-{0}-{1}" -f $ExpectedScale, $stamp))
New-Item -ItemType Directory -Force -Path $output | Out-Null

Write-Host 'CloudOS Browser - validacao fisica obrigatoria' -ForegroundColor Cyan
Write-Host "Escala esperada do Windows: $ExpectedScale%"
Write-Host "Saida: $output"
Write-Host "Configure $ExpectedScale% em Configuracoes > Sistema > Tela antes de continuar. O script nao muda a escala do sistema." -ForegroundColor Yellow

$project = Join-Path $repoRoot 'desktop\CloudOS.Browser.PhysicalProbe\CloudOS.Browser.PhysicalProbe.csproj'
& dotnet run --project $project -c Release -- --output $output --expected-scale $ExpectedScale --theme $Theme --screen
$probeExitCode = $LASTEXITCODE

$report = Join-Path $output 'validation.json'
if (-not (Test-Path -LiteralPath $report)) {
    throw "BROWSER_PHYSICAL_UI_REPORT_MISSING exit=$probeExitCode"
}

$validation = Get-Content -Raw -LiteralPath $report | ConvertFrom-Json
Write-Host "Relatorio: $report"
Write-Host "Stage: $($validation.stage)"
if ($null -ne $validation.error) {
    Write-Host "Erro: $($validation.error.code) / $($validation.error.classification) / win32=$($validation.error.win32)" -ForegroundColor Yellow
}
if ($null -ne $validation.artifacts) {
    Write-Host ("Artefatos produzidos: {0}" -f (($validation.artifacts | ForEach-Object { [string]$_ }) -join ', '))
}

if ($probeExitCode -ne 0) {
    throw "BROWSER_PHYSICAL_UI_FAILED exit=$probeExitCode report=$report"
}

if ($validation.passed -ne $true -or $validation.physicalValidation -ne $true) {
    throw 'BROWSER_PHYSICAL_UI_REPORT_INVALID: execução retornou sucesso sem validação física aprovada.'
}

$requiredArtifacts = @(
    '01-youtube-typed.png',
    '02-youtube-selected.png',
    '03-paste.png',
    '04-long-url-home.png',
    '05-long-url-end.png',
    '06-after-navigation.png',
    '07-compact.png',
    '08-dark-normal.png',
    '09-dark-compact.png',
    '10-light-normal.png',
    '11-light-compact.png',
    '12-menu-open.png',
    '13-downloads-hub.png',
    '14-settings-hub.png'
)

foreach ($artifact in $requiredArtifacts) {
    $artifactPath = Join-Path $output $artifact
    if (-not (Test-Path -LiteralPath $artifactPath)) {
        throw "BROWSER_PHYSICAL_UI_ARTIFACT_MISSING: $artifact"
    }
    if ($validation.artifacts -notcontains $artifact) {
        throw "BROWSER_PHYSICAL_UI_REPORT_ARTIFACT_MISSING: $artifact"
    }
}

Write-Host 'PASS funcional. Revise visualmente TODOS os PNGs antes de aprovar a branch.' -ForegroundColor Green
Write-Host "Sequencia: $output"
Write-Host 'Este script NAO promove integration/cloudos-validated-features.' -ForegroundColor Yellow
