param(
  [switch]$Windowed,
  [switch]$Kiosk,
  [switch]$DeveloperMode,
  [string]$NodePath
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Bootstrap = Join-Path $Root 'desktop\publish\CloudOS.Bootstrap.exe'
$HostExecutable = Join-Path $Root 'desktop\publish\CloudOS.Host.exe'

if (-not (Test-Path -LiteralPath $Bootstrap)) {
  throw 'O supervisor de recuperação ainda não foi publicado em desktop\publish\CloudOS.Bootstrap.exe.'
}
if (-not (Test-Path -LiteralPath $HostExecutable)) {
  throw 'O host CloudOS ainda não foi publicado em desktop\publish\CloudOS.Host.exe.'
}

$arguments = @('--preview', '--host', $HostExecutable, '--root', $Root)
if ($NodePath) { $arguments += @('--node', $NodePath) }
if (-not $Windowed) { $arguments += '--fullscreen' }
if ($Kiosk) { $arguments += '--kiosk' }
if ($DeveloperMode) { $arguments += '--developer-mode' }

Write-Host 'Iniciando a prévia supervisionada. Nenhuma configuração de shell, Registro ou boot será alterada.'
& $Bootstrap @arguments
exit $LASTEXITCODE
