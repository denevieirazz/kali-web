param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',
    [switch]$CheckSourceFingerprint,
    [string]$BuildDirectory
)

$ErrorActionPreference = 'Stop'

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$out = Join-Path $rootPath "desktop\CloudOS.NativeShell\bin\$Configuration"
if ($BuildDirectory) { $out = (Resolve-Path -LiteralPath $BuildDirectory).Path }
$manifestPath = Join-Path $out 'cloudos-native-manifest.json'
$fingerprintStamp = Join-Path $out '.cloudos-build-fingerprint'
$fingerprintScript = Join-Path $PSScriptRoot 'get-native-build-fingerprint.ps1'

if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Native build manifest missing: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1) { throw "Unsupported native build manifest schema: $($manifest.schema)" }
if ($manifest.product -ne 'CloudOS Native Shell' -or $manifest.shell_authority -ne 'C++/Win32') {
    throw 'Native build manifest does not describe the authoritative C++/Win32 CloudOS shell.'
}
if ($manifest.recovery_authority -ne 'CloudOS.Supervisor.exe V11') {
    throw 'Native build manifest does not identify the compatible Supervisor V11 authority contract.'
}
if ([int]$manifest.supervisor_runtime_schema -ne 22 -or
    [int]$manifest.supervisor_compatibility_contract -ne 11 -or
    $manifest.supervisor_job_kill_on_close -ne $true) {
    throw 'Native build manifest does not prove the Supervisor V22 runtime hardening layer.'
}
$requiredStates = @('STARTING', 'HEALTHY', 'DEGRADED', 'RESTARTING', 'CRASH_LOOP', 'SAFE_MODE', 'STOPPING')
foreach ($state in $requiredStates) {
    if (@($manifest.supervisor_states) -notcontains $state) { throw "Supervisor V22 manifest state missing: $state" }
}
if ([string]$manifest.supervisor_state_journal -ne '%LOCALAPPDATA%\CloudOS\Recovery\supervisor-state-v22.json') {
    throw 'Supervisor V22 state journal identity is missing from the native manifest.'
}
if ($manifest.broker_authority -ne 'CloudOS.SystemBroker.exe V21') {
    throw 'Native build manifest does not identify System Broker V21 as broker authority.'
}
if ($manifest.configuration -ne $Configuration -or $manifest.platform -ne 'x64') {
    throw "Native manifest configuration/platform mismatch: $($manifest.configuration)/$($manifest.platform)"
}
if ($manifest.legacy_react_desktop -ne $false) { throw 'Legacy React desktop unexpectedly marked as part of the native release.' }
if ($manifest.source_fingerprint_sha256 -notmatch '^[0-9a-f]{64}$') { throw 'Native manifest contains an invalid source fingerprint.' }

$expectedNames = @('CloudOS.exe','CloudOS.NativeRuntime.dll','CloudOS.Supervisor.exe','CloudOS.SystemBroker.exe','CloudOS.BrokerProbe.exe')
foreach ($name in $expectedNames) {
    $record = @($manifest.files | Where-Object { $_.name -eq $name })
    if ($record.Count -ne 1) { throw "Native manifest must contain exactly one record for $name" }
    $path = Join-Path $out $name
    if (-not (Test-Path -LiteralPath $path)) { throw "Native binary missing: $path" }
    $item = Get-Item -LiteralPath $path
    if ([Int64]$record[0].size -ne [Int64]$item.Length -or $item.Length -le 0) { throw "Native binary size mismatch for $name" }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne ([string]$record[0].sha256).ToLowerInvariant()) { throw "Native binary SHA256 mismatch for $name" }
}

if (Test-Path -LiteralPath (Join-Path $out 'ui')) { throw 'Obsolete web-desktop output exists in the authoritative native release directory.' }
if (-not (Test-Path -LiteralPath $fingerprintStamp)) { throw "Native source fingerprint stamp missing: $fingerprintStamp" }
$stamp = (Get-Content -LiteralPath $fingerprintStamp -Raw).Trim().ToLowerInvariant()
if ($stamp -ne ([string]$manifest.source_fingerprint_sha256).ToLowerInvariant()) { throw 'Native fingerprint stamp and manifest disagree.' }

if ($CheckSourceFingerprint) {
    if (-not (Test-Path -LiteralPath $fingerprintScript)) { throw "Native fingerprint helper missing: $fingerprintScript" }
    $current = (& $fingerprintScript -Root $rootPath | Select-Object -Last 1).Trim().ToLowerInvariant()
    if ($current -ne $stamp) { throw "Native binary is stale for the current source tree. built=$stamp current=$current" }
}

# SHA256/provenance and Authenticode are different guarantees. This verifier
# intentionally proves manifest integrity only; update V22 reports signature
# evidence separately and can enforce it when production signing is configured.
Write-Host "PASS: native V21/V22 runtime integrity verified ($Configuration x64, $($expectedNames.Count) SHA256-verified components, Supervisor V22 evidence, fingerprint=$stamp; Authenticode is a separate policy)."
