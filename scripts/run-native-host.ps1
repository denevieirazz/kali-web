param(
  [switch]$Fullscreen,
  [switch]$Kiosk,
  [switch]$DeveloperMode,
  [string]$NodePath
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $Root 'desktop\CloudOS.Host\CloudOS.Host.csproj'
$PublishedHost = Join-Path $Root 'desktop\publish\CloudOS.Host.exe'

$hostArguments = @('--root', $Root)
if ($NodePath) { $hostArguments += @('--node', $NodePath) }
if ($Fullscreen) { $hostArguments += '--fullscreen' }
if ($Kiosk) { $hostArguments += '--kiosk' }
if ($DeveloperMode) { $hostArguments += '--developer-mode' }

if (Test-Path -LiteralPath $PublishedHost) {
  & $PublishedHost @hostArguments
  exit $LASTEXITCODE
}

$DotnetCommand = Get-Command 'dotnet.exe' -ErrorAction SilentlyContinue
$LocalSdk = $null
$Cursor = Get-Item -LiteralPath $Root
while (-not $LocalSdk -and $Cursor) {
  $Candidate = Join-Path $Cursor.FullName '.dotnet8\dotnet.exe'
  if (Test-Path -LiteralPath $Candidate) { $LocalSdk = $Candidate }
  $Cursor = $Cursor.Parent
}
$Dotnet = if ($DotnetCommand) { $DotnetCommand.Source } elseif ($LocalSdk) { $LocalSdk } else { 'dotnet.exe' }

$arguments = @('run', '--project', $Project, '-c', 'Release', '--') + $hostArguments

& $Dotnet @arguments
exit $LASTEXITCODE
