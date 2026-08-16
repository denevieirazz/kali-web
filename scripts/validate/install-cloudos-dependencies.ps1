[CmdletBinding()]
param(
    [string]$Root,
    [string]$EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
if (-not $EvidenceDirectory) { $EvidenceDirectory = Join-Path $Root 'test-results\dependency-bootstrap' }

. (Join-Path $PSScriptRoot 'cloudos-node-dependencies.ps1')

$result = Ensure-CloudOSNodeDependencies -Root $Root -EvidenceDirectory $EvidenceDirectory -AllowInstall
Write-Host "CLOUDOS_DEPENDENCIES_OK installPerformed=$($result.installPerformed)"
Write-Host "DEPENDENCY_EVIDENCE=$EvidenceDirectory"
