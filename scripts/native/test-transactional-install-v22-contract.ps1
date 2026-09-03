[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$installPath = Join-Path $root 'scripts\native\install-cloudos-native-v22.ps1'
$updatePath = Join-Path $root 'scripts\native\update-cloudos-native-v13.ps1'
$packagePath = Join-Path $root 'scripts\native\package-cloudos-native.ps1'
$suitePath = Join-Path $root 'scripts\native\test-native-contract-suite.ps1'

foreach ($path in @($installPath, $updatePath, $packagePath, $suitePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Transactional Install V22 contract input missing: $path"
    }
}

$install = Get-Content -LiteralPath $installPath -Raw
$update = Get-Content -LiteralPath $updatePath -Raw
$package = Get-Content -LiteralPath $packagePath -Raw
$suite = Get-Content -LiteralPath $suitePath -Raw

foreach ($required in @(
    'Get-CloudOSDeploymentStatus',
    '$before.installed',
    'Use Atualizar CloudOS.cmd',
    "'update-cloudos-native-v13.ps1'",
    'HealthTimeoutSeconds',
    'RequireAuthenticodeSignature',
    '& $hardenedUpdate @arguments',
    '$after.active_valid',
    'healthGate=required'
)) {
    if (-not $install.Contains($required)) {
        throw "Transactional Install V22 guard missing: $required"
    }
}

foreach ($required in @(
    'Invoke-CloudOSPostActivationHealthGate',
    'Invoke-CloudOSUninstall',
    'with no last-known-good version',
    "'--probe-ready-once'",
    'Get-AuthenticodeSignature'
)) {
    if (-not $update.Contains($required)) {
        throw "Shared V22 activation health primitive missing: $required"
    }
}

foreach ($required in @(
    "'install-cloudos-native-v22.ps1'",
    'install-cloudos-native-v22.ps1" -PackageRoot'
)) {
    if (-not $package.Contains($required)) {
        throw "Portable package does not use health-gated V22 install: $required"
    }
}

if (-not $suite.Contains('test-transactional-install-v22-contract.ps1')) {
    throw 'Central native suite must protect Transactional Install V22.'
}

foreach ($forbidden in @('SkipPostActivationHealthCheck', 'Invoke-Expression', 'iex ')) {
    if ($install.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "First-install entrypoint must not bypass activation health: $forbidden"
    }
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $installPath,
    [ref]$tokens,
    [ref]$errors)
if ($errors.Count -ne 0) {
    throw "Transactional Install V22 has PowerShell parse errors: $($errors.Message -join '; ')"
}

Write-Host '[PASS] Transactional Install V22: first install shares hardened activation health, cannot silently upgrade an existing deployment, and removes a known-bad first activation.'
