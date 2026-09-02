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

# Event delivery V23 backpressure contract carried by the V21 Broker:
# - EventBus publisher callback only serializes/enqueues bounded data.
# - A ClientSendState owns queue lifecycle and byte accounting per client.
# - The ClientSessionLoop is the sole I/O owner for its named-pipe handle and
#   sends both queued events and RPC responses, eliminating concurrent writers.
# - PeekNamedPipe + a short condition-variable wait prevents a blocking ReadFile
#   from starving unsolicited events while an idle client is connected.
# - Overflow cancels the stalled client instead of blocking Publish() or growing
#   memory without limit.
$serverContent = Get-Content (Join-Path $brokerSrc "broker_server_v21.cpp") -Raw
foreach ($required in @(
    'constexpr size_t kMaxQueuedEventFrames',
    'constexpr size_t kMaxQueuedEventBytes',
    'struct ClientSendState final',
    'std::mutex mutex',
    'std::condition_variable event_ready',
    'std::deque<std::string> event_queue',
    'size_t queued_event_bytes',
    'bool active',
    'TryPopQueuedEvent',
    'PeekNamedPipe(',
    'send_state->event_queue.size() >= kMaxQueuedEventFrames',
    'send_state->queued_event_bytes += serialized.size()',
    'send_state->event_queue.push_back(std::move(serialized))',
    'CancelIoEx(send_state->pipe, nullptr)',
    'SendFrame(pipe, outbound_event)',
    'SendFrame(pipe, SerializeResponse(res))'
)) {
    if (-not $serverContent.Contains($required)) {
        throw "SystemBroker event transport lost bounded single-writer contract: $required"
    }
}

$registerStart = $serverContent.IndexOf('EventBusV21::Instance().RegisterClient(')
if ($registerStart -lt 0) {
    throw "SystemBroker event transport must register EventBus clients"
}
$registerEnd = $serverContent.IndexOf('        });', $registerStart)
if ($registerEnd -lt 0) {
    throw "SystemBroker EventBus registration callback could not be bounded for contract inspection"
}
$registerBody = $serverContent.Substring($registerStart, $registerEnd - $registerStart)
if ($registerBody.Contains('SendFrame(') -or $registerBody.Contains('WriteFile(')) {
    throw "EventBus publisher callback must enqueue only and must not write directly to the client pipe"
}
if (-not $registerBody.Contains('event_queue.push_back')) {
    throw "EventBus publisher callback must enqueue events into the bounded per-client queue"
}

# A second writer thread/mutex would reintroduce ordering races between events
# and RPC responses on one duplex pipe. All writes stay in ClientSessionLoop.
foreach ($forbidden in @(
    'std::mutex write_mutex',
    'std::thread event_writer'
)) {
    if ($serverContent.Contains($forbidden)) {
        throw "SystemBroker event transport regressed to stale multi-writer model: $forbidden"
    }
}

$docV21 = Join-Path $root "docs\native\SYSTEM_BROKER_V21.md"
$docSec = Join-Path $root "docs\native\SYSTEM_BROKER_SECURITY_V21.md"
if (-not (Test-Path $docV21)) { throw "Missing docs/native/SYSTEM_BROKER_V21.md" }
if (-not (Test-Path $docSec)) { throw "Missing docs/native/SYSTEM_BROKER_SECURITY_V21.md" }

Write-Host "[PASS] All V21 System Broker Contract Assertions Passed."
