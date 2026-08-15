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
Write-Host "Configure $ExpectedScale% em Configuracoes > Sistema > Tela antes de continuar. O script nao muda a escala." -ForegroundColor Yellow

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

$requiredChecks = @(
    'rendered-text-content-viewport',
    'top-bottom-clip-tolerance',
    'caret-visible',
    'selection-visible',
    'omnibox-closeups',
    'menu-complete',
    'downloads-surface',
    'extensions-surface'
)
foreach ($check in $requiredChecks) {
    if ($validation.checks -notcontains $check) {
        throw "BROWSER_PHYSICAL_UI_CHECK_MISSING: $check"
    }
}

$requiredArtifacts = @(
    '01-omnibox-empty-closeup.png',
    '02-omnibox-typed-closeup.png',
    '03-omnibox-selected-closeup.png',
    '04-paste.png',
    '05-long-url-home.png',
    '06-long-url-end.png',
    '07-after-navigation.png',
    '08-compact.png',
    '09-dark-normal.png',
    '10-dark-compact.png',
    '11-light-normal.png',
    '12-light-compact.png',
    '13-menu-complete.png',
    '14-downloads.png',
    '15-extensions.png',
    '16-settings.png'
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

if ($null -eq $validation.omniboxVisuals.typed -or
    $null -eq $validation.omniboxVisuals.selected -or
    $null -eq $validation.omniboxVisuals.'long-url-home' -or
    $null -eq $validation.omniboxVisuals.'long-url-end') {
    throw 'BROWSER_PHYSICAL_UI_OMNIBOX_METRICS_MISSING'
}

Write-Host 'PASS funcional. Aprovacao visual continua obrigatoriamente manual pelo usuario.' -ForegroundColor Green
Write-Host "Sequencia: $output"
Write-Host 'Este script NAO promove integration/cloudos-validated-features.' -ForegroundColor Yellow
