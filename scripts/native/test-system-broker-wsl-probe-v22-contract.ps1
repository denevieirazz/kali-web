# test-system-broker-wsl-probe-v22-contract.ps1
# Structural contract for the bounded active WSL health probe.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Get-Item "$PSScriptRoot\..\..").FullName
$brokerRoot = Join-Path $root 'desktop\CloudOS.SystemBroker'
$src = Join-Path $brokerRoot 'src'
$flutterBridgeRoot = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge'

$probeHeaderPath = Join-Path $src 'wsl_probe_service_v22.h'
$probeSourcePath = Join-Path $src 'wsl_probe_service_v22.cpp'
$wslHeaderPath = Join-Path $src 'wsl_service_v21.h'
$brokerSourcePath = Join-Path $src 'broker_server_v21.cpp'
$systemSourcePath = Join-Path $src 'system_service_v21.cpp'
$projectPath = Join-Path $brokerRoot 'CloudOS.SystemBroker.vcxproj'
$brokerClientHeaderPath = Join-Path $flutterBridgeRoot 'cloudos_broker_client_v21.h'
$brokerClientSourcePath = Join-Path $flutterBridgeRoot 'cloudos_broker_client_v21.cpp'
$flutterBridgeSourcePath = Join-Path $flutterBridgeRoot 'cloudos_flutter_bridge_v20.cpp'

foreach ($path in @(
    $probeHeaderPath,
    $probeSourcePath,
    $wslHeaderPath,
    $brokerSourcePath,
    $systemSourcePath,
    $projectPath,
    $brokerClientHeaderPath,
    $brokerClientSourcePath,
    $flutterBridgeSourcePath
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required WSL probe contract source is missing: $path"
    }
}

$probeHeader = Get-Content -LiteralPath $probeHeaderPath -Raw
$probeSource = Get-Content -LiteralPath $probeSourcePath -Raw
$wslHeader = Get-Content -LiteralPath $wslHeaderPath -Raw
$brokerSource = Get-Content -LiteralPath $brokerSourcePath -Raw
$systemSource = Get-Content -LiteralPath $systemSourcePath -Raw
$project = Get-Content -LiteralPath $projectPath -Raw
$brokerClientHeader = Get-Content -LiteralPath $brokerClientHeaderPath -Raw
$brokerClientSource = Get-Content -LiteralPath $brokerClientSourcePath -Raw
$flutterBridgeSource = Get-Content -LiteralPath $flutterBridgeSourcePath -Raw

if ($probeHeader -notmatch 'struct\s+WslProbeResultV22' -or
    $probeHeader -notmatch 'bool\s+attempted' -or
    $probeHeader -notmatch 'bool\s+success' -or
    $probeHeader -notmatch 'bool\s+timed_out' -or
    $probeHeader -notmatch 'int\s+exit_code' -or
    $probeHeader -notmatch 'duration_ms' -or
    $probeHeader -notmatch 'error_code' -or
    $probeHeader -notmatch 'error_message') {
    throw 'WslProbeResultV22 must preserve typed health/lifecycle evidence.'
}

if ($probeHeader -notmatch 'Probe\s*\(\s*const\s+std::string&\s+requested_distro\s*,\s*uint32_t\s+timeout_ms') {
    throw 'The active probe API must accept only distro identity plus a bounded timeout.'
}
if ($probeHeader -match '\bcommand\b\s*[,;)]' -or
    $probeHeader -match '\bargv\b\s*[,;)]' -or
    $probeHeader -match '\bshell_command\b') {
    throw 'The WSL health probe API must not expose arbitrary command execution.'
}

# The active probe is intentionally different from passive inventory: it may
# start wsl.exe, but the Linux body is fixed in source and cannot come from RPC.
if ($probeSource -notmatch 'CLOUDOS_WSL_HEALTH_V22' -or
    $probeSource -notmatch "id -u" -or
    $probeSource -notmatch 'uname -s' -or
    $probeSource -notmatch 'pwd') {
    throw 'The active probe must carry the fixed CloudOS marker/identity/kernel/cwd script.'
}
if ($probeSource -notmatch 'CreateProcessW' -or
    $probeSource -notmatch 'WaitForSingleObject' -or
    $probeSource -notmatch 'TerminateProcess') {
    throw 'The active probe must own a bounded Windows process lifecycle.'
}
if ($probeSource -notmatch 'kMinTimeoutMs\s*=\s*1000' -or
    $probeSource -notmatch 'kMaxTimeoutMs\s*=\s*15000' -or
    $probeSource -notmatch 'std::clamp\(timeout_ms') {
    throw 'Probe deadlines must be bounded between the contract limits.'
}
if ($probeSource -notmatch 'kMaxCapturedBytes\s*=\s*64\s*\*\s*1024' -or
    $probeSource -notmatch 'kMaxReturnedBytes\s*=\s*8\s*\*\s*1024') {
    throw 'Probe output must remain bounded in memory and on the wire.'
}
if ($probeSource -notmatch 'FindDistribution\(snapshot' -or
    $probeSource -notmatch 'base_path_present') {
    throw 'The probe must validate the requested distro against passive registration/storage evidence.'
}
if ($probeSource -notmatch 'SetHandleInformation\(read_pipe,\s*HANDLE_FLAG_INHERIT,\s*0\)' -or
    $probeSource -notmatch 'probe_pipe_security_failed') {
    throw 'The child must not inherit the Broker-side read end of the probe pipe.'
}
if ($probeSource -notmatch 'const\s+DWORD\s+create_error\s*=\s*created\s*\?\s*ERROR_SUCCESS\s*:\s*GetLastError\(\)') {
    throw 'CreateProcess failure evidence must be captured before cleanup can overwrite GetLastError.'
}
if ($probeSource -match '--terminate' -or $probeSource -match '--unregister') {
    throw 'A health probe must never terminate or unregister an entire WSL distribution.'
}

if ($brokerSource -notmatch 'wsl_probe_service_v22\.h' -or
    $brokerSource -notmatch 'method\s*==\s*"wsl\.health\.probe"') {
    throw 'System Broker must expose the typed wsl.health.probe RPC.'
}
if ($brokerSource -notmatch 'field\.first\s*!=\s*"distro"[\s\S]{0,100}field\.first\s*!=\s*"timeoutMs"') {
    throw 'The WSL health RPC must use a strict payload allowlist.'
}
if ($brokerSource -notmatch "accepts only 'distro' and 'timeoutMs'") {
    throw 'The strict WSL probe payload contract must remain explicit.'
}
if ($brokerSource -notmatch 'requested_timeout\s*<\s*1000' -or
    $brokerSource -notmatch 'requested_timeout\s*>\s*15000') {
    throw 'The Broker must reject out-of-contract probe deadlines.'
}
if ($brokerSource -notmatch 'WriteWslProbePayload' -or
    $brokerSource -notmatch '"healthy"' -or
    $brokerSource -notmatch '"timedOut"' -or
    $brokerSource -notmatch '"markerSeen"' -or
    $brokerSource -notmatch '"exitCode"' -or
    $brokerSource -notmatch '"durationMs"') {
    throw 'The Broker must return structured active health evidence.'
}
if ($brokerSource -notmatch 'event interleaving here could make it consume an event as the reply') {
    throw 'The synchronous V21 probe RPC must document why it does not publish before its response frame.'
}

if ($systemSource -notmatch '"wsl\.health\.probe"') {
    throw 'System Broker capabilities must advertise wsl.health.probe.'
}
if ($wslHeader -notmatch 'base_path_present') {
    throw 'Active probe preflight depends on passive distro storage evidence.'
}

if ($project -notmatch 'src\\wsl_probe_service_v22\.h' -or
    $project -notmatch 'src\\wsl_probe_service_v22\.cpp') {
    throw 'WslProbeServiceV22 must be compiled into CloudOS.SystemBroker.'
}

# The declaration lives in the native client header, while request framing and
# response validation intentionally live in the .cpp implementation.
if ($brokerClientHeader -notmatch 'struct\s+BrokerClientWslProbeResult' -or
    $brokerClientHeader -notmatch 'ProbeWslHealth\s*\(') {
    throw 'The native Flutter-side Broker client must declare the typed health probe.'
}
if ($brokerClientSource -notmatch 'CloudOSBrokerClientV21::ProbeWslHealth\s*\(' -or
    $brokerClientSource -notmatch '"wsl\.health\.probe"' -or
    $brokerClientSource -notmatch 'ProbePayloadLooksConsistent\(probe\)') {
    throw 'The native Broker client must implement and validate the active WSL probe RPC.'
}
if ($brokerClientSource -notmatch 'probe\.healthy[\s\S]{0,300}probe\.attempted' -or
    $brokerClientSource -notmatch 'probe\.marker_seen' -or
    $brokerClientSource -notmatch 'probe\.exit_code\s*==\s*0') {
    throw 'The native Broker client must reject internally inconsistent healthy probe responses.'
}
if ($brokerClientSource -notmatch 'probe\.output\.size\(\)\s*>\s*16\s*\*\s*1024') {
    throw 'The native client must keep probe response text bounded even if the Broker regresses.'
}

if ($flutterBridgeSource -notmatch 'method\s*==\s*"probeWslHealth"' -or
    $flutterBridgeSource -notmatch 'ProbeWslHealth\(' -or
    $flutterBridgeSource -notmatch '"healthy"' -or
    $flutterBridgeSource -notmatch '"errorCode"') {
    throw 'The Flutter MethodChannel bridge must expose the typed active WSL probe result.'
}
if ($flutterBridgeSource -match 'commandLine' -or
    $flutterBridgeSource -match 'shellCommand') {
    throw 'The Flutter active health bridge must not expose arbitrary Linux command fields.'
}

Write-Host '[PASS] CloudOS bounded active WSL health probe contract.'
