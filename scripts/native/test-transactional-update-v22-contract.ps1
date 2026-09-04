[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$updatePath = Join-Path $root 'scripts\native\update-cloudos-native-v13.ps1'
$v13Path = Join-Path $root 'scripts\native\CloudOS.Deployment.V13.psm1'
$healthPath = Join-Path $root 'scripts\native\CloudOS.HealthGate.V22.psm1'

foreach ($path in @($updatePath, $v13Path, $healthPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Transactional V22 update contract input missing: $path"
    }
}

$update = Get-Content -LiteralPath $updatePath -Raw
$v13 = Get-Content -LiteralPath $v13Path -Raw
$health = Get-Content -LiteralPath $healthPath -Raw

foreach ($required in @(
    'Get-CloudOSPayloadIdentity',
    'CloudOS.HealthGate.V22.psm1',
    'Get-CloudOSAuthenticodeEvidenceV22',
    'RequireAuthenticodeSignature',
    'signature_all_valid',
    'Assert-CloudOSRuntimeStoppedV22',
    "-Operation 'update'",
    'Invoke-CloudOSDeployment',
    'Invoke-CloudOSSupervisorHealthGateV22',
    'Invoke-CloudOSRollback',
    'rollback restored',
    'Invoke-CloudOSUninstall',
    'RetainVersions -lt 2',
    "schema = 22",
    "operation = 'update'",
    'rollback_capacity'
)) {
    if (-not $update.Contains($required)) {
        throw "Transactional V22 update guard missing: $required"
    }
}

foreach ($required in @(
    'Get-AuthenticodeSignature',
    "'cloudos_flutter_shell'",
    "'--probe-ready-once'",
    "'--probe-no-explorer'",
    "'--max-failures', '1'",
    'WaitForExit($TimeoutSeconds * 1000)'
)) {
    if (-not $health.Contains($required)) {
        throw "Shared Health Gate V22 required by update is missing: $required"
    }
}

# The hardened entrypoint still delegates immutable staging/state ownership to
# V13 instead of creating a second deployment database.
foreach ($required in @(
    'deployment-v13.journal.json',
    'last_known_good',
    'Write-CloudOSJsonAtomic',
    'Test-CloudOSPayload',
    "-Phase 'copying'",
    "-Phase 'verifying'",
    "-Phase 'publishing'",
    "-Phase 'activating'",
    'Remove-CloudOSOldVersions'
)) {
    if (-not $v13.Contains($required)) {
        throw "V13 transactional primitive required by V22 is missing: $required"
    }
}

foreach ($forbidden in @(
    'Invoke-Expression',
    'iex ',
    'Winlogon',
    'HKEY_LOCAL_MACHINE',
    'Set-ItemProperty',
    'New-ItemProperty',
    'reg.exe add'
)) {
    if ($update.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $health.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Transactional V22 update introduced forbidden behavior: $forbidden"
    }
}

foreach ($path in @($updatePath, $healthPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$errors)
    if ($errors.Count -ne 0) {
        throw "Transactional V22 update dependency has PowerShell parse errors [$path]: $($errors.Message -join '; ')"
    }
}

Write-Host '[PASS] Transactional Update V22 contract: immutable V13 staging + shared Authenticode/runtime-stop gate + active Supervisor health + rollback.'
