# Compatibility wrapper retained for older shortcuts and documentation.
# CloudOS V21 is the current Flutter + System Broker preview flow.

[CmdletBinding()]
param(
    [switch]$Run,
    [switch]$SkipBuild,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot 'preview-cloudos-flutter-v21.ps1'

$forward = @{}
if ($Run) { $forward.Run = $true }
if ($SkipBuild) { $forward.SkipBuild = $true }
if ($SkipTests) { $forward.SkipTests = $true }

& $target @forward
exit $LASTEXITCODE
