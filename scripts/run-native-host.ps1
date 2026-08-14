param(
  [switch]$Fullscreen,
  [switch]$Kiosk,
  [switch]$DeveloperMode,
  [string]$NodePath
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $Root 'desktop\CloudOS.Host\CloudOS.Host.csproj'
$FreshnessScript = Join-Path $PSScriptRoot 'native-host-freshness.ps1'
. $FreshnessScript

$hostArguments = @('--root', $Root)
if ($NodePath) { $hostArguments += @('--node', $NodePath) }
if ($Fullscreen) { $hostArguments += '--fullscreen' }
if ($Kiosk) { $hostArguments += '--kiosk' }
if ($DeveloperMode) { $hostArguments += '--developer-mode' }

$SourceCheckout = Test-Path -LiteralPath $Project
if ($SourceCheckout -and -not (Test-CloudOsFrontendDistFresh -Root $Root)) {
  Write-Warning 'frontend\dist está ausente ou mais antigo que frontend\src. Reconstruindo o bundle antes de iniciar o Host.'
  $Npm = Get-Command 'npm.cmd' -ErrorAction SilentlyContinue
  if (-not $Npm) {
    throw 'FRONTEND_DIST_STALE: npm.cmd não foi encontrado. Execute npm install e npm --prefix frontend run build antes de iniciar o CloudOS.'
  }
  & $Npm.Source --prefix (Join-Path $Root 'frontend') run build
  if ($LASTEXITCODE -ne 0) { throw "FRONTEND_BUILD_FAILED: npm encerrou com código $LASTEXITCODE." }
  if (-not (Test-CloudOsFrontendDistFresh -Root $Root)) {
    throw 'FRONTEND_DIST_STALE: o bundle continuou desatualizado após a reconstrução.'
  }
}

$Published = Get-CloudOsPublishedHostState -Root $Root
if ($Published.Usable) {
  & $Published.Executable @hostArguments
  exit $LASTEXITCODE
}

if ($Published.Exists -and $Published.SourceCheckout) {
  $reasons = @()
  if ($Published.Stale) { $reasons += 'publicação mais antiga que os fontes C#/XAML' }
  if (-not $Published.Complete) { $reasons += ('arquivos ausentes: ' + ($Published.Missing -join ', ')) }
  Write-Warning ('desktop\publish não será usado: ' + ($reasons -join '; ') + '. O Host será compilado a partir dos fontes atuais.')
}
elseif ($Published.Exists -and -not $Published.Complete) {
  throw ('PUBLISHED_HOST_INCOMPLETE: arquivos necessários ausentes: ' + ($Published.Missing -join ', '))
}
elseif (-not $SourceCheckout) {
  throw 'PUBLISHED_HOST_MISSING: CloudOS.Host.exe não foi encontrado e os fontes do Host não estão disponíveis.'
}

$DotnetCommand = Get-Command 'dotnet.exe' -ErrorAction SilentlyContinue
$LocalSdk = $null
$Cursor = Get-Item -LiteralPath $Root
while (-not $LocalSdk -and $Cursor) {
  $Candidate = Join-Path $Cursor.FullName '.dotnet8\dotnet.exe'
  if (Test-Path -LiteralPath $Candidate) { $LocalSdk = $Candidate }
  $Cursor = $Cursor.Parent
}
$Dotnet = if ($DotnetCommand) { $DotnetCommand.Source } elseif ($LocalSdk) { $LocalSdk } else { $null }
if (-not $Dotnet) {
  throw 'HOST_SOURCE_NEWER_THAN_PUBLISH: .NET 8 não foi encontrado para compilar os fontes atuais do CloudOS.Host.'
}

$arguments = @('run', '--project', $Project, '-c', 'Release', '--') + $hostArguments
& $Dotnet @arguments
exit $LASTEXITCODE
