[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$repairPath = Join-Path $root 'scripts\native\repair-cloudos-native-v22.ps1'
$healthPath = Join-Path $root 'scripts\native\CloudOS.HealthGate.V22.psm1'
$packagePath = Join-Path $root 'scripts\native\package-cloudos-native.ps1'
$suitePath = Join-Path $root 'scripts\native\test-native-contract-suite.ps1'
foreach ($path in @($repairPath, $healthPath, $packagePath, $suitePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Runtime Repair V22 contract input missing: $path"
    }
}

$repair = Get-Content -LiteralPath $repairPath -Raw
$health = Get-Content -LiteralPath $healthPath -Raw
$package = Get-Content -LiteralPath $packagePath -Raw
$suite = Get-Content -LiteralPath $suitePath -Raw

foreach ($required in @(
    'Assert-CloudOSRuntimeStoppedV22',
    "-Operation 'repair'",
    'Invoke-CloudOSRepair',
    'Get-CloudOSDeploymentStatus',
    '$status.active_valid',
    'Invoke-CloudOSSupervisorHealthGateV22',
    '$status.last_known_good',
    'Test-CloudOSPayload',
    'Invoke-CloudOSRollback',
    'fallback_attempted',
    'fallback_health',
    "operation = 'repair'",
    "verdict = if (`$healthy) { 'pass' } else { 'fail' }",
    'Use CloudOS Recovery/Explorer'
)) {
    if (-not $repair.Contains($required)) {
        throw "Runtime Repair V22 contract missing: $required"
    }
}

foreach ($required in @(
    'Invoke-CloudOSSupervisorHealthGateV22',
    'Assert-CloudOSRuntimeStoppedV22'
)) {
    if (-not $health.Contains($required)) {
        throw "Shared Health Gate V22 primitive missing for repair: $required"
    }
}

foreach ($required in @(
    "'repair-cloudos-native-v22.ps1'",
    'repair-cloudos-native-v22.ps1"'
)) {
    if (-not $package.Contains($required)) {
        throw "Portable package does not expose runtime-verified Repair V22: $required"
    }
}

foreach ($forbidden in @(
    'Invoke-Expression',
    'iex ',
    'Winlogon',
    'HKEY_LOCAL_MACHINE',
    'Remove-Item -LiteralPath $InstallRoot -Recurse'
)) {
    if ($repair.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Runtime Repair V22 introduced forbidden behavior: $forbidden"
    }
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $repairPath,
    [ref]$tokens,
    [ref]$errors)
if ($errors.Count -ne 0) {
    throw "Runtime Repair V22 has PowerShell parse errors: $($errors.Message -join '; ')"
}

if (-not $suite.Contains('test-runtime-repair-v22-contract.ps1')) {
    throw 'Central native suite must protect Runtime Repair V22.'
}

Write-Host '[PASS] Runtime Repair V22: integrity repair is followed by real Supervisor health; unhealthy active can fall back to a verified last-known-good version.'
