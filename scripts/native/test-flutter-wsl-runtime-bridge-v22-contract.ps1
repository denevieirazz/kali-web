# test-flutter-wsl-runtime-bridge-v22-contract.ps1
# Verifies the additive WSL runtime evidence path from SystemBroker -> native
# Flutter bridge -> Dart snapshot -> terminal/settings policy.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Get-Item "$PSScriptRoot\..\..").FullName
$brokerHeader = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_broker_client_v21.h'
$brokerSource = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_broker_client_v21.cpp'
$bridgeHeader = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_flutter_bridge_v20.h'
$bridgeSource = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_flutter_bridge_v20.cpp'
$dartBridge = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\services\cloudos_bridge.dart'
$snapshotModel = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\models\cloud_system_snapshot.dart'
$policy = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\features\terminal\domain\wsl_runtime_policy.dart'
$terminal = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\features\terminal\presentation\terminal_window.dart'
$settings = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\features\settings\presentation\settings_window.dart'

$paths = @(
    $brokerHeader,
    $brokerSource,
    $bridgeHeader,
    $bridgeSource,
    $dartBridge,
    $snapshotModel,
    $policy,
    $terminal,
    $settings
)
foreach ($path in $paths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required typed WSL bridge source is missing: $path"
    }
}

$brokerHeaderText = Get-Content -LiteralPath $brokerHeader -Raw
$brokerSourceText = Get-Content -LiteralPath $brokerSource -Raw
$bridgeHeaderText = Get-Content -LiteralPath $bridgeHeader -Raw
$bridgeSourceText = Get-Content -LiteralPath $bridgeSource -Raw
$dartBridgeText = Get-Content -LiteralPath $dartBridge -Raw
$snapshotText = Get-Content -LiteralPath $snapshotModel -Raw
$policyText = Get-Content -LiteralPath $policy -Raw
$terminalText = Get-Content -LiteralPath $terminal -Raw
$settingsText = Get-Content -LiteralPath $settings -Raw

# Native broker client must carry richer evidence instead of collapsing back to
# the legacy wslAvailable + names-only shape.
foreach ($token in @(
    'BrokerClientWslDistributionSnapshot',
    'wsl_engine_available',
    'wsl_passive_ready',
    'wsl_distros',
    'preferred_security_distro',
    'wsl_launch_candidate_count',
    'wsl1_count',
    'wsl2_count'
)) {
    if ($brokerHeaderText -notmatch [Regex]::Escape($token)) {
        throw "Broker client header dropped required WSL runtime evidence: $token"
    }
}

foreach ($jsonField in @(
    'wslEngineAvailable',
    'wslPassiveReady',
    'wslDistros',
    'preferredSecurityDistro',
    'wslRegisteredCount',
    'wslLaunchCandidateCount',
    'wsl1Count',
    'wsl2Count',
    'basePathPresent',
    'securityCandidate'
)) {
    if ($brokerSourceText -notmatch ('"' + [Regex]::Escape($jsonField) + '"')) {
        throw "Native broker client does not parse expected WSL field: $jsonField"
    }
    if ($bridgeSourceText -notmatch ('"' + [Regex]::Escape($jsonField) + '"')) {
        throw "Flutter native bridge does not publish expected WSL field: $jsonField"
    }
}

foreach ($token in @(
    'NativeWslDistributionSnapshot',
    'wsl_engine_available',
    'wsl_passive_ready_known',
    'wsl_distros',
    'preferred_security_distro'
)) {
    if ($bridgeHeaderText -notmatch [Regex]::Escape($token)) {
        throw "Native Flutter snapshot dropped required WSL evidence: $token"
    }
}

# Dart parser must preserve unknown evidence as null rather than inventing
# success/failure values.
foreach ($token in @(
    'basePathPresent: entry[''basePathPresent''] as bool?',
    'securityCandidate: entry[''securityCandidate''] as bool?',
    'wslPassiveReady: raw[''wslPassiveReady''] as bool?',
    'preferredSecurityDistro:',
    'wslLaunchCandidateCount:'
)) {
    if ($dartBridgeText -notmatch [Regex]::Escape($token)) {
        throw "Dart bridge is not preserving typed WSL evidence: $token"
    }
}

foreach ($token in @(
    'bool? basePathPresent',
    'bool? securityCandidate',
    'bool? wslPassiveReady',
    'effectiveLaunchCandidateCount',
    'distroStorageEvidence'
)) {
    if ($snapshotText -notmatch [Regex]::Escape($token)) {
        throw "CloudSystemSnapshot does not model WSL evidence: $token"
    }
}

# Session policy must make an explicit distinction between generic compatibility
# launches and stricter security-runtime readiness.
foreach ($token in @(
    'WslSessionPlan',
    'WslSessionRequirement',
    'WSL_DISTRO_STORAGE_MISSING',
    'KALI_STORAGE_NOT_PROVEN',
    'preferredSecurityPassiveReadyDistro',
    'storageFor('
)) {
    if ($policyText -notmatch [Regex]::Escape($token)) {
        throw "WSL runtime policy guard is missing: $token"
    }
}

if ($terminalText -notmatch 'distroStorageEvidence:\s*snapshot\.distroStorageEvidence' -or
    $terminalText -notmatch 'preferredSecurityDistro:\s*snapshot\.preferredSecurityDistro' -or
    $terminalText -notmatch 'planSession\(') {
    throw 'Terminal must consume typed WSL storage/security evidence through WslRuntimePolicy.'
}

if ($settingsText -notmatch 'distroStorageEvidence:\s*widget\.snapshot\.distroStorageEvidence' -or
    $settingsText -notmatch 'effectiveLaunchCandidateCount' -or
    $settingsText -notmatch 'boot não testado') {
    throw 'Settings must distinguish passive evidence from active Linux health.'
}

# Regression guard: legacy name-only evidence must never be promoted to WSL2.
if ($dartBridgeText -match 'CloudWslDistributionSnapshot\([\s\S]{0,200}version:\s*2[\s\S]{0,200}legacy') {
    throw 'Legacy WSL inventory must not synthesize WSL2 evidence.'
}

Write-Host '[PASS] CloudOS typed WSL runtime evidence bridge contract.'
