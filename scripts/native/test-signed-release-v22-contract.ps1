[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$finalizerPath = Join-Path $root 'scripts\native\finalize-cloudos-signed-release-v22.ps1'
$healthGatePath = Join-Path $root 'scripts\native\CloudOS.HealthGate.V22.psm1'
$installPath = Join-Path $root 'scripts\native\install-cloudos-native-v22.ps1'
$updatePath = Join-Path $root 'scripts\native\update-cloudos-native-v13.ps1'
$repairPath = Join-Path $root 'scripts\native\repair-cloudos-native-v22.ps1'

foreach ($path in @($finalizerPath, $healthGatePath, $installPath, $updatePath, $repairPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Signed Release V22 contract input missing: $path"
    }
}

$finalizer = Get-Content -LiteralPath $finalizerPath -Raw
$healthGate = Get-Content -LiteralPath $healthGatePath -Raw
$install = Get-Content -LiteralPath $installPath -Raw
$update = Get-Content -LiteralPath $updatePath -Raw
$repair = Get-Content -LiteralPath $repairPath -Raw

foreach ($required in @(
    'CertificateThumbprint',
    'TimestampServer',
    'HasPrivateKey',
    '1.3.6.1.5.5.7.3.3',
    'Set-AuthenticodeSignature',
    'Get-AuthenticodeSignature',
    'HashAlgorithm SHA256',
    'cloudos-authenticode-v22.json',
    'SHA256SUMS.txt',
    'package_authenticode_v22',
    'package_signer_thumbprint',
    'private_key_material_in_package',
    "@('.pfx', '.p12', '.key', '.pem')",
    'CloudOS-Native-Release-x64-signed.zip'
)) {
    if (-not $finalizer.Contains($required)) {
        throw "Signed Release V22 finalizer missing fail-closed requirement: $required"
    }
}

if ($finalizer -match 'New-SelfSignedCertificate' -or
    $finalizer -match 'CertificateThumbprint\s*=\s*["''][0-9A-Fa-f]+' -or
    $finalizer -match 'ConvertTo-SecureString.+AsPlainText') {
    throw 'Production signing must not mint a self-signed certificate, hard-code a signer, or embed a private-key password.'
}

foreach ($requiredPayload in @(
    "'CloudOS.exe'",
    "'CloudOS.NativeRuntime.dll'",
    "'CloudOS.Supervisor.exe'",
    "'CloudOS.SystemBroker.exe'",
    "'CloudOS.BrokerProbe.exe'",
    "'install-cloudos-native-v22.ps1'",
    "'update-cloudos-native-v13.ps1'",
    "'repair-cloudos-native-v22.ps1'",
    "'CloudOS.Deployment.V13.psm1'",
    "'CloudOS.HealthGate.V22.psm1'"
)) {
    if (-not $healthGate.Contains($requiredPayload)) {
        throw "Health Gate V22 does not enforce Authenticode evidence for critical payload: $requiredPayload"
    }
}

foreach ($required in @(
    'Test-CloudOSFinalizedSignedPackageV22',
    'signed-package marker/evidence mismatch',
    'CloudOS.Release.Authenticode',
    'private_key_material_in_package'
)) {
    if (-not $healthGate.Contains($required)) {
        throw "Health Gate V22 signed-package auto-enforcement missing: $required"
    }
}

foreach ($entry in @(
    @{ Name = 'install'; Content = $install },
    @{ Name = 'update'; Content = $update },
    @{ Name = 'repair'; Content = $repair }
)) {
    if ($entry.Content -notmatch 'RequireAuthenticodeSignature') {
        throw "CloudOS $($entry.Name) path must expose Authenticode enforcement."
    }
}
if ($update -notmatch 'Test-CloudOSFinalizedSignedPackageV22' -or
    $update -notmatch 'effectiveRequireSignature') {
    throw 'Update/install authority must automatically enforce Authenticode when the package was finalized as signed.'
}
if ($repair -notmatch 'Test-CloudOSFinalizedSignedPackageV22' -or
    $repair -notmatch 'effectiveRequireSignature') {
    throw 'Repair authority must automatically enforce Authenticode for finalized signed active/LKG payloads.'
}

$tokens = $null
$errors = $null
foreach ($path in @($finalizerPath, $healthGatePath, $updatePath, $repairPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$errors)
    if ($errors.Count -ne 0) {
        throw "Signed Release V22 script has PowerShell parse errors in $path: $($errors.Message -join '; ')"
    }
}

Write-Host '[PASS] Signed Release V22 contract: real Code Signing certificate + timestamp are mandatory, critical runtime/deployment files are covered, private-key material is rejected, finalized signed packages auto-enforce Authenticode, signed bytes drive final manifest/SHA256 and no self-signed fallback exists.'
