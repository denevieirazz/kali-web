# test-system-broker-v21-contract.ps1
# CloudOS V21 — System Broker Architectural & Contract Verification

$ErrorActionPreference = "Stop"
$root = (Get-Item "$PSScriptRoot\..\..").FullName

Write-Host "[Contract-V21] Checking V21 Architectural Constraints..."

$brokerSrc = Join-Path $root "desktop\CloudOS.SystemBroker\src"
$requiredHeaders = @(
    "protocol_v21.h",
    "security_v21.h",
    "event_bus_v21.h",
    "job_manager_v21.h",
    "app_service_v21.h",
    "system_service_v21.h",
    "wsl_service_v21.h",
    "diagnostics_v21.h",
    "broker_server_v21.h"
)
foreach ($h in $requiredHeaders) {
    $p = Join-Path $brokerSrc $h
    if (-not (Test-Path $p)) { throw "Missing required SystemBroker header: $h" }
}

$protoContent = Get-Content (Join-Path $brokerSrc "protocol_v21.h") -Raw
if ($protoContent -notmatch "kProtocolVersion\s*=\s*21") { throw "kProtocolVersion must be 21" }
if ($protoContent -notmatch "kMaxPayloadBytes\s*=\s*1048576") { throw "kMaxPayloadBytes must be 1048576 (1 MiB)" }

$forbiddenApis = @("executeCommand", "runShell", "runPowerShell", "runWslCommand", "cmdExec", "arbitraryCommand")
foreach ($api in $forbiddenApis) {
    if ($protoContent -match $api) { throw "FORBIDDEN API detected in protocol: $api" }
}

# SecurityV21 must build an explicit fail-closed DACL from the current SID,
# optionally using the SDDL protected-DACL flag (D:P...). It must not grant
# broad access to Everyone or Authenticated Users.
$secContent = Get-Content (Join-Path $brokerSrc "security_v21.cpp") -Raw
if ($secContent -notmatch 'D:P?\(A;;GA;;;') {
    throw "SecurityV21 must construct explicit per-user DACL"
}
if ($secContent -match '\(A;;GA;;;WD\)' -or $secContent -match '\(A;;GA;;;AU\)') {
    throw "SecurityV21 must not grant generic access to Everyone or Authenticated Users"
}
if ($secContent -notmatch 'sid\.empty\(\)') {
    throw "SecurityV21 must fail closed when the current user SID cannot be resolved"
}

# Event delivery must be isolated from EventBus publishers. A subscribed client
# that stops consuming its named pipe is disconnected after bounded per-client
# buffering instead of blocking Publish() inside WriteFile or growing memory
# without limit.
$serverContent = Get-Content (Join-Path $brokerSrc "broker_server_v21.cpp") -Raw
foreach ($required in @(
    'kMaxQueuedEventFrames',
    'kMaxQueuedEventBytes',
    'std::deque<std::string> event_queue',
    'std::condition_variable event_ready',
    'std::mutex write_mutex',
    'std::thread event_writer',
    'CancelIoEx(send_state->pipe, nullptr)'
)) {
    if (-not $serverContent.Contains($required)) {
        throw "SystemBroker event transport lost bounded backpressure contract: $required"
    }
}
if ($serverContent -match '(?s)RegisterClient\s*\([^;]+SendFrame\s*\(send_state->pipe') {
    throw "EventBus publisher callback must not write directly to the client pipe"
}

$docV21 = Join-Path $root "docs\native\SYSTEM_BROKER_V21.md"
$docSec = Join-Path $root "docs\native\SYSTEM_BROKER_SECURITY_V21.md"
if (-not (Test-Path $docV21)) { throw "Missing docs/native/SYSTEM_BROKER_V21.md" }
if (-not (Test-Path $docSec)) { throw "Missing docs/native/SYSTEM_BROKER_SECURITY_V21.md" }

Write-Host "[PASS] All V21 System Broker Contract Assertions Passed."
