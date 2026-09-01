# test-system-broker-v21-contract.ps1
# CloudOS V21 — System Broker Architectural & Contract Verification

$ErrorActionPreference = "Stop"
$root = (Get-Item "$PSScriptRoot\..\..").FullName

Write-Host "[Contract-V21] Checking V21 Architectural Constraints..."

# 1. Verify C++ SystemBroker project files exist
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
    if (-not (Test-Path $p)) {
        throw "Missing required SystemBroker header: $h"
    }
}

# 2. Verify Protocol Constants
$protoContent = Get-Content (Join-Path $brokerSrc "protocol_v21.h") -Raw
if ($protoContent -notmatch "kProtocolVersion\s*=\s*21") {
    throw "kProtocolVersion must be 21"
}
if ($protoContent -notmatch "kMaxPayloadBytes\s*=\s*1048576") {
    throw "kMaxPayloadBytes must be 1048576 (1 MiB)"
}

# 3. Verify No Arbitrary Command APIs in Protocol
$forbiddenApis = @("executeCommand", "runShell", "runPowerShell", "runWslCommand", "cmdExec", "arbitraryCommand")
foreach ($api in $forbiddenApis) {
    if ($protoContent -match $api) {
        throw "FORBIDDEN API detected in protocol: $api"
    }
}

# 4. Verify Per-User Security ACL in SecurityV21
$secContent = Get-Content (Join-Path $brokerSrc "security_v21.cpp") -Raw
if ($secContent -notmatch "D:\(A;;GA;;;") {
    throw "SecurityV21 must construct explicit per-user DACL"
}

# 5. Verify Documentation Exists
$docV21 = Join-Path $root "docs\native\SYSTEM_BROKER_V21.md"
$docSec = Join-Path $root "docs\native\SYSTEM_BROKER_SECURITY_V21.md"
if (-not (Test-Path $docV21)) {
    throw "Missing docs/native/SYSTEM_BROKER_V21.md"
}
if (-not (Test-Path $docSec)) {
    throw "Missing docs/native/SYSTEM_BROKER_SECURITY_V21.md"
}

Write-Host "[PASS] All V21 System Broker Contract Assertions Passed."
