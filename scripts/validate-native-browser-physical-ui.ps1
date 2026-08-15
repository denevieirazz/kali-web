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
if ($LASTEXITCODE -ne 0) { throw "BROWSER_PHYSICAL_UI_FAILED exit=$LASTEXITCODE" }

$report = Join-Path $output 'validation.json'
if (-not (Test-Path $report)) { throw 'BROWSER_PHYSICAL_UI_REPORT_MISSING' }
Write-Host 'PASS funcional. Revise visualmente TODOS os PNGs antes de aprovar a branch.' -ForegroundColor Green
Write-Host "Relatorio: $report"
Write-Host "Sequencia: $output"
Write-Host 'Este script NAO promove integration/cloudos-validated-features.' -ForegroundColor Yellow
