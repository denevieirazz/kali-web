# test-system-broker-wsl-inventory-v22-contract.ps1
# CloudOS V22-facing WSL inventory contract over the compatible V21 broker.

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

# The legacy V21 fields must remain available while the richer inventory is
# additive. This prevents older Flutter/native clients from breaking.
if ($wslHeader -notmatch 'struct\s+WslDistributionInfoV21' -or
    $wslHeader -notmatch 'int\s+version\s*\{\s*0\s*\}' -or
    $wslHeader -notmatch 'bool\s+is_default') {
    throw 'WslDistributionInfoV21 must carry name/version/default evidence.'
}
if ($wslHeader -notmatch 'struct\s+WslRuntimeSnapshotV21' -or
    $wslHeader -notmatch 'engine_available' -or
    $wslHeader -notmatch 'usable' -or
    $wslHeader -notmatch 'GetRuntimeSnapshot') {
    throw 'WslServiceV21 must expose separate engine/usable runtime evidence.'
}
if ($wslHeader -notmatch 'IsWslAvailable' -or
    $wslHeader -notmatch 'GetDistributions' -or
    $wslHeader -notmatch 'GetDefaultDistribution') {
    throw 'Legacy V21 WSL methods must remain present.'
}

# Passive system snapshots must not wake Linux. Inventory comes from the WSL
# registration metadata plus presence of wsl.exe.
if ($wslSource -notmatch 'SOFTWARE\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Lxss') {
    throw 'WslServiceV21 must read the per-user Lxss registration metadata.'
}
if ($wslSource -notmatch 'DistributionName' -or
    $wslSource -notmatch 'DefaultDistribution' -or
    $wslSource -notmatch 'ReadDwordValue' -or
    $wslSource -notmatch 'L"Version"') {
    throw 'Passive inventory must read distro name, default registration and registered WSL version.'
}
if ($wslSource -match 'CreateProcessW' -or
    $wslSource -match 'ShellExecuteW' -or
    $wslSource -match 'wsl\.exe\s+--list' -or
    $wslSource -match 'wsl\.exe\s+-d') {
    throw 'Passive WSL inventory must not start or query a distro process.'
}
if ($wslSource -notmatch 'registered_version\s*==\s*1' -or
    $wslSource -notmatch 'registered_version\s*==\s*2' -or
    $wslSource -notmatch 'version\s*=.*0') {
    throw 'Unknown WSL versions must remain unknown instead of being guessed as WSL2.'
}

if ($systemHeader -notmatch 'wsl_engine_available' -or
    $systemHeader -notmatch 'wsl_distros' -or
    $systemHeader -notmatch 'SystemWslDistributionSnapshot') {
    throw 'SystemSnapshot must expose additive typed WSL inventory evidence.'
}
if ($systemSource -notmatch '"wslEngineAvailable"' -or
    $systemSource -notmatch '"wslDistros"' -or
    $systemSource -notmatch '"versionKnown"') {
    throw 'System snapshot JSON must serialize typed WSL evidence.'
}
if ($systemSource -notmatch '"wslAvailable"' -or
    $systemSource -notmatch '"defaultDistro"' -or
    $systemSource -notmatch '"distros"') {
    throw 'System snapshot must preserve legacy V21 WSL JSON fields.'
}
if ($systemSource -notmatch 'wsl\.inventory\.typed') {
    throw 'Broker capabilities must advertise wsl.inventory.typed.'
}

if ($project -notmatch 'src\\wsl_service_v21\.cpp' -or
    $project -notmatch 'src\\system_service_v21\.cpp') {
    throw 'Typed WSL inventory sources must be compiled into CloudOS.SystemBroker.'
}

Write-Host '[PASS] CloudOS typed passive WSL inventory contract.'
