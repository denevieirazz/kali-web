# test-system-broker-wsl-inventory-v22-contract.ps1
# CloudOS V22-facing WSL inventory/health contract over the compatible V21 broker.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Get-Item "$PSScriptRoot\..\..").FullName
$brokerRoot = Join-Path $root 'desktop\CloudOS.SystemBroker'
$src = Join-Path $brokerRoot 'src'

$wslHeaderPath = Join-Path $src 'wsl_service_v21.h'
$wslSourcePath = Join-Path $src 'wsl_service_v21.cpp'
$systemHeaderPath = Join-Path $src 'system_service_v21.h'
$systemSourcePath = Join-Path $src 'system_service_v21.cpp'
$projectPath = Join-Path $brokerRoot 'CloudOS.SystemBroker.vcxproj'

foreach ($path in @($wslHeaderPath, $wslSourcePath, $systemHeaderPath, $systemSourcePath, $projectPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required WSL inventory contract source is missing: $path"
    }
}

$wslHeader = Get-Content -LiteralPath $wslHeaderPath -Raw
$wslSource = Get-Content -LiteralPath $wslSourcePath -Raw
$systemHeader = Get-Content -LiteralPath $systemHeaderPath -Raw
$systemSource = Get-Content -LiteralPath $systemSourcePath -Raw
$project = Get-Content -LiteralPath $projectPath -Raw

# The legacy V21 fields must remain available while richer evidence is additive.
if ($wslHeader -notmatch 'struct\s+WslDistributionInfoV21' -or
    $wslHeader -notmatch 'int\s+version\s*\{\s*0\s*\}' -or
    $wslHeader -notmatch 'bool\s+is_default') {
    throw 'WslDistributionInfoV21 must carry name/version/default evidence.'
}
if ($wslHeader -notmatch 'base_path_present' -or
    $wslHeader -notmatch 'is_security_candidate') {
    throw 'WslDistributionInfoV21 must carry passive storage/security evidence.'
}
if ($wslHeader -notmatch 'struct\s+WslRuntimeSnapshotV21' -or
    $wslHeader -notmatch 'engine_available' -or
    $wslHeader -notmatch 'usable' -or
    $wslHeader -notmatch 'passive_ready' -or
    $wslHeader -notmatch 'preferred_security_distribution' -or
    $wslHeader -notmatch 'registered_count' -or
    $wslHeader -notmatch 'launch_candidate_count' -or
    $wslHeader -notmatch 'wsl1_count' -or
    $wslHeader -notmatch 'wsl2_count' -or
    $wslHeader -notmatch 'GetRuntimeSnapshot') {
    throw 'WslServiceV21 must expose separate engine/legacy/passive runtime evidence.'
}
if ($wslHeader -notmatch 'IsWslAvailable' -or
    $wslHeader -notmatch 'GetDistributions' -or
    $wslHeader -notmatch 'GetDefaultDistribution') {
    throw 'Legacy V21 WSL methods must remain present.'
}

# Passive system snapshots must not wake Linux. Inventory comes from the WSL
# registration metadata plus presence of wsl.exe and registered storage.
if ($wslSource -notmatch 'SOFTWARE\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Lxss') {
    throw 'WslServiceV21 must read the per-user Lxss registration metadata.'
}
if ($wslSource -notmatch 'DistributionName' -or
    $wslSource -notmatch 'DefaultDistribution' -or
    $wslSource -notmatch 'ReadDwordValue' -or
    $wslSource -notmatch 'L"Version"' -or
    $wslSource -notmatch 'L"BasePath"' -or
    $wslSource -notmatch 'GetFileAttributesW') {
    throw 'Passive inventory must read distro name/default/version/BasePath and validate storage.'
}
if ($wslSource -match 'CreateProcessW' -or
    $wslSource -match 'ShellExecuteW' -or
    $wslSource -match 'wsl\.exe\s+--list' -or
    $wslSource -match 'wsl\.exe\s+-d') {
    throw 'Passive WSL inventory must not start or query a distro process.'
}
if ($wslSource -notmatch 'registered_version\s*==\s*1' -or
    $wslSource -notmatch 'registered_version\s*==\s*2' -or
    $wslSource -notmatch 'out\.version\s*=[\s\S]{0,300}\?\s*static_cast<int>\(registered_version\)[\s\S]{0,100}:\s*0\s*;') {
    throw 'Unknown WSL versions must remain unknown instead of being guessed as WSL2.'
}
if ($wslSource -notmatch 'IsKaliName\(out\.name\)' -or
    $wslSource -notmatch 'out\.version\s*==\s*2' -or
    $wslSource -notmatch 'out\.base_path_present') {
    throw 'Security-candidate classification must require Kali identity, WSL2 and present storage.'
}
if ($wslSource -notmatch 'passive_ready_\s*=\s*wsl_engine_available_\s*&&\s*launch_candidate_count_\s*>\s*0') {
    throw 'Passive readiness must require the engine and at least one storage-backed registration.'
}

if ($systemHeader -notmatch 'wsl_engine_available' -or
    $systemHeader -notmatch 'wsl_passive_ready' -or
    $systemHeader -notmatch 'wsl_distros' -or
    $systemHeader -notmatch 'SystemWslDistributionSnapshot' -or
    $systemHeader -notmatch 'preferred_security_distro' -or
    $systemHeader -notmatch 'wsl_launch_candidate_count') {
    throw 'SystemSnapshot must expose additive typed WSL inventory/health evidence.'
}
if ($systemSource -notmatch '"wslEngineAvailable"' -or
    $systemSource -notmatch '"wslPassiveReady"' -or
    $systemSource -notmatch '"wslDistros"' -or
    $systemSource -notmatch '"versionKnown"' -or
    $systemSource -notmatch '"basePathPresent"' -or
    $systemSource -notmatch '"securityCandidate"' -or
    $systemSource -notmatch '"wslRegisteredCount"' -or
    $systemSource -notmatch '"wslLaunchCandidateCount"' -or
    $systemSource -notmatch '"wsl1Count"' -or
    $systemSource -notmatch '"wsl2Count"' -or
    $systemSource -notmatch '"preferredSecurityDistro"') {
    throw 'System snapshot JSON must serialize typed WSL inventory and passive health evidence.'
}
if ($systemSource -notmatch '"wslAvailable"' -or
    $systemSource -notmatch '"defaultDistro"' -or
    $systemSource -notmatch '"distros"') {
    throw 'System snapshot must preserve legacy V21 WSL JSON fields.'
}
if ($systemSource -notmatch 'wsl\.inventory\.typed' -or
    $systemSource -notmatch 'wsl\.inventory\.health') {
    throw 'Broker capabilities must advertise typed WSL inventory and health evidence.'
}
if ($systemSource -match 'wsl\.health\.probe') {
    throw 'Passive inventory slice must not advertise the active WSL health probe before its implementation is ported.'
}

if ($project -notmatch 'src\\wsl_service_v21\.cpp' -or
    $project -notmatch 'src\\system_service_v21\.cpp') {
    throw 'Typed WSL inventory sources must be compiled into CloudOS.SystemBroker.'
}

Write-Host '[PASS] CloudOS typed passive WSL inventory/health contract.'
