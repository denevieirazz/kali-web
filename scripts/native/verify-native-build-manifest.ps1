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

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Native build manifest missing: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1) {
    throw "Unsupported native build manifest schema: $($manifest.schema)"
}
if ($manifest.product -ne 'CloudOS Native Shell' -or $manifest.shell_authority -ne 'C++/Win32') {
    throw 'Native build manifest does not describe the authoritative C++/Win32 CloudOS shell.'
}
if ($manifest.recovery_authority -ne 'CloudOS.Supervisor.exe V11') {
    throw 'Native build manifest does not identify Shell Supervisor V11 as recovery authority.'
}
if ($manifest.configuration -ne $Configuration -or $manifest.platform -ne 'x64') {
    throw "Native manifest configuration/platform mismatch: $($manifest.configuration)/$($manifest.platform)"
}
if ($manifest.legacy_react_desktop -ne $false) {
    throw 'Legacy React desktop unexpectedly marked as part of the native release.'
}
if ($manifest.source_fingerprint_sha256 -notmatch '^[0-9a-f]{64}$') {
    throw 'Native manifest contains an invalid source fingerprint.'
}

$expectedNames = @('CloudOS.exe', 'CloudOS.NativeRuntime.dll', 'CloudOS.Supervisor.exe')
foreach ($name in $expectedNames) {
    $record = @($manifest.files | Where-Object { $_.name -eq $name })
    if ($record.Count -ne 1) {
        throw "Native manifest must contain exactly one record for $name"
    }

    $path = Join-Path $out $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Native binary missing: $path"
    }

    $item = Get-Item -LiteralPath $path
    if ([Int64]$record[0].size -ne [Int64]$item.Length -or $item.Length -le 0) {
        throw "Native binary size mismatch for $name"
    }

    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne ([string]$record[0].sha256).ToLowerInvariant()) {
        throw "Native binary SHA256 mismatch for $name"
    }
}

if (Test-Path -LiteralPath (Join-Path $out 'ui')) {
    throw 'Obsolete web-desktop output exists in the authoritative native release directory.'
}

if (-not (Test-Path -LiteralPath $fingerprintStamp)) {
    throw "Native source fingerprint stamp missing: $fingerprintStamp"
}
$stamp = (Get-Content -LiteralPath $fingerprintStamp -Raw).Trim().ToLowerInvariant()
if ($stamp -ne ([string]$manifest.source_fingerprint_sha256).ToLowerInvariant()) {
    throw 'Native fingerprint stamp and manifest disagree.'
}

if ($CheckSourceFingerprint) {
    if (-not (Test-Path -LiteralPath $fingerprintScript)) {
        throw "Native fingerprint helper missing: $fingerprintScript"
    }
    $current = (& $fingerprintScript -Root $rootPath | Select-Object -Last 1).Trim().ToLowerInvariant()
    if ($current -ne $stamp) {
        throw "Native binary is stale for the current source tree. built=$stamp current=$current"
    }
}

Write-Host "PASS: native release integrity verified ($Configuration x64, Supervisor V11, fingerprint=$stamp)."
