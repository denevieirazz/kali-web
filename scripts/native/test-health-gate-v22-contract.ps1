[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $root 'scripts\native\CloudOS.HealthGate.V22.psm1'
$installPath = Join-Path $root 'scripts\native\install-cloudos-native-v22.ps1'
$updatePath = Join-Path $root 'scripts\native\update-cloudos-native-v13.ps1'
$repairPath = Join-Path $root 'scripts\native\repair-cloudos-native-v22.ps1'
$suitePath = Join-Path $root 'scripts\native\test-native-contract-suite.ps1'
foreach ($path in @($modulePath, $installPath, $updatePath, $repairPath, $suitePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Health Gate V22 contract input missing: $path"
    }
}

$module = Get-Content -LiteralPath $modulePath -Raw
$install = Get-Content -LiteralPath $installPath -Raw
$update = Get-Content -LiteralPath $updatePath -Raw
$repair = Get-Content -LiteralPath $repairPath -Raw
$suite = Get-Content -LiteralPath $suitePath -Raw

foreach ($required in @(
    'Get-CloudOSAuthenticodeEvidenceV22',
    'Get-AuthenticodeSignature',
    "'CloudOS.exe'",
    "'CloudOS.NativeRuntime.dll'",
    "'CloudOS.Supervisor.exe'",
    "'CloudOS.SystemBroker.exe'",
    "'CloudOS.BrokerProbe.exe'",
    'Get-CloudOSManagedRuntimeProcessesV22',
    "'cloudos_flutter_shell'",
    'StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)',
    'Assert-CloudOSRuntimeStoppedV22',
    'Invoke-CloudOSSupervisorHealthGateV22',
    '[ValidateRange(15, 120)][int]$TimeoutSeconds = 60',
    "'--probe-ready-once'",
    "'--probe-no-explorer'",
    "'--max-failures', '1'",
    "'--ready-timeout-ms', '30000'",
    "'--heartbeat-timeout-ms', '5000'",
    'WaitForExit($TimeoutSeconds * 1000)',
    '$process.Kill($true)',
    "reason = 'supervisor_health_timeout'",
    "'ready_heartbeat_graceful_exit'",
    'elapsed_ms'
)) {
    if (-not $module.Contains($required)) {
        throw "Health Gate V22 contract missing: $required"
    }
}

foreach ($entrypoint in @(
    @{ Name = 'install'; Text = $install },
    @{ Name = 'update'; Text = $update },
    @{ Name = 'repair'; Text = $repair }
)) {
    if (-not $entrypoint.Text.Contains('HealthTimeoutSeconds = 60')) {
        throw "Health Gate V22 default timeout drifted in $($entrypoint.Name) entrypoint."
    }
}

foreach ($forbidden in @(
    'Invoke-Expression',
    'iex ',
    'Winlogon',
    'Set-ItemProperty',
    'New-ItemProperty',
    'reg.exe',
    'taskkill /F',
    'Stop-Process -Force'
)) {
    if ($module.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Health Gate V22 introduced forbidden behavior: $forbidden"
    }
}

foreach ($functionName in @(
    'Get-CloudOSAuthenticodeEvidenceV22',
    'Get-CloudOSManagedRuntimeProcessesV22',
    'Assert-CloudOSRuntimeStoppedV22',
    'Invoke-CloudOSSupervisorHealthGateV22'
)) {
    if (-not $module.Contains("'$functionName'")) {
        throw "Health Gate V22 function is not exported: $functionName"
    }
}

foreach ($path in @($modulePath, $installPath, $updatePath, $repairPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$errors)
    if ($errors.Count -ne 0) {
        throw "Health Gate V22 dependency has PowerShell parse errors [$path]: $($errors.Message -join '; ')"
    }
}

if (-not $suite.Contains('test-health-gate-v22-contract.ps1')) {
    throw 'Central native suite must protect Health Gate V22.'
}

Write-Host '[PASS] Health Gate V22: shared 60-second entrypoint timeout, runtime-stop, Authenticode evidence and Supervisor readiness/heartbeat authority for install/update/repair.'
