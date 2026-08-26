param(
  [switch]$Windowed,
  [switch]$Kiosk,
  [switch]$DeveloperMode,
  [string]$NodePath
)

$ErrorActionPreference = 'Stop'
$Launcher = Join-Path $PSScriptRoot 'run-native-host.ps1'
$arguments = @{}
if (-not $Windowed) { $arguments.Fullscreen = $true }
if ($Kiosk) { $arguments.Kiosk = $true }
if ($DeveloperMode) { $arguments.DeveloperMode = $true }
if ($NodePath) { $arguments.NodePath = $NodePath }

& $Launcher @arguments
exit $LASTEXITCODE
