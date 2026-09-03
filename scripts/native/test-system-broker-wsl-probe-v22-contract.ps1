# test-system-broker-wsl-probe-v22-contract.ps1
# Structural contract for the bounded active WSL health probe.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Get-Item "$PSScriptRoot\..\..").FullName
$brokerRoot = Join-Path $root 'desktop\CloudOS.SystemBroker'
$src = Join-Path $brokerRoot 'src'

$probeHeaderPath = Join-Path $src 'wsl_probe_service_v22.h'
$probeSourcePath = Join-Path $src 'wsl_probe_service_v22.cpp'
$wslHeaderPath = Join-Path $src 'wsl_service_v21.h'
$brokerSourcePath = Join-Path $src 'broker_server_v21.cpp'
$systemSourcePath = Join-Path $src 'system_service_v21.cpp'
$projectPath = Join-Path $brokerRoot 'CloudOS.SystemBroker.vcxproj'

foreach ($path in @(
    $probeHeaderPath,
    $probeSourcePath,
    $wslHeaderPath,
    $brokerSourcePath,
    $systemSourcePath,
    $projectPath
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
if ($brokerSource -notmatch 'wsl\.healthProbed') {
    throw 'Active WSL health results must be observable on the Broker event bus.'
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

Write-Host '[PASS] CloudOS bounded active WSL health probe contract.'
