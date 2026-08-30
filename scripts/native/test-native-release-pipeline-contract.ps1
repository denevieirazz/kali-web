$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$paths = @{
    Fingerprint = Join-Path $PSScriptRoot 'get-native-build-fingerprint.ps1'
    Writer = Join-Path $PSScriptRoot 'write-native-build-manifest.ps1'
    Verifier = Join-Path $PSScriptRoot 'verify-native-build-manifest.ps1'
    Build = Join-Path $PSScriptRoot 'build-cloudos-native.cmd'
    Start = Join-Path $PSScriptRoot 'start-cloudos-native.cmd'
    Workflow = Join-Path $root '.github\workflows\cloudos-native-full-system.yml'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Native release pipeline contract path missing [$($entry.Key)]: $($entry.Value)"
    }
}

$content = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

function Require([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) {
            throw "$Name contract missing: $token"
        }
    }
}

Require 'Deterministic native fingerprint' $content.Fingerprint @(
    'desktop\CloudOS.NativeRuntime',
    'desktop\CloudOS.NativeShell',
    'scripts\native',
    "'bin', 'obj', 'packages', '.vs'",
    'Get-FileHash',
    'SHA256',
    'Sort-Object'
)

Require 'Native provenance manifest writer' $content.Writer @(
    'cloudos-native-manifest.json',
    '.cloudos-build-head',
    '.cloudos-build-fingerprint',
    "shell_authority = 'C++/Win32'",
    "legacy_react_desktop = `$false",
    'source_fingerprint_sha256',
    'CloudOS.exe',
    'CloudOS.NativeRuntime.dll',
    'Get-FileHash'
)

Require 'Native integrity verifier' $content.Verifier @(
    'Native binary SHA256 mismatch',
    'Native binary size mismatch',
    'Obsolete web-desktop output',
    'CheckSourceFingerprint',
    'Native binary is stale for the current source tree'
)

Require 'Native build entrypoint provenance' $content.Build @(
    'test-native-release-pipeline-contract.ps1',
    'write-native-build-manifest.ps1',
    'verify-native-build-manifest.ps1',
    'cloudos-native-manifest.json',
    '.cloudos-build-fingerprint'
)

Require 'Native launcher integrity gate' $content.Start @(
    'get-native-build-fingerprint.ps1',
    'verify-native-build-manifest.ps1',
    '.cloudos-build-fingerprint',
    'SOURCE_FINGERPRINT',
    'taskkill /F /IM CloudOS.exe'
)

Require 'CI release artifact' $content.Workflow @(
    'build-cloudos-native.cmd',
    'verify-native-build-manifest.ps1',
    'actions/upload-artifact@v4',
    'cloudos-native-manifest.json'
)

Write-Host 'PASS: deterministic source fingerprint, binary integrity manifest, stale-build gate and CI release artifact contracts are protected.'
