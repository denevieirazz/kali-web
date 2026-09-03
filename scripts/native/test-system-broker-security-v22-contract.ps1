[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$headerPath = Join-Path $root 'desktop\CloudOS.SystemBroker\src\security_v21.h'
$securityPath = Join-Path $root 'desktop\CloudOS.SystemBroker\src\security_v21.cpp'
$brokerPath = Join-Path $root 'desktop\CloudOS.SystemBroker\src\broker_server_v21.cpp'
$suitePath = Join-Path $root 'scripts\native\test-native-contract-suite.ps1'

foreach ($path in @($headerPath, $securityPath, $brokerPath, $suitePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "System Broker Security V22 contract input missing: $path"
    }
}

$header = Get-Content -LiteralPath $headerPath -Raw
$security = Get-Content -LiteralPath $securityPath -Raw
$broker = Get-Content -LiteralPath $brokerPath -Raw
$suite = Get-Content -LiteralPath $suitePath -Raw

foreach ($required in @(
    'ValidateNamedPipeClient(HANDLE pipe',
    'out_process_id'
)) {
    if (-not $header.Contains($required)) {
        throw "System Broker Security V22 header missing: $required"
    }
}

foreach ($required in @(
    'D:P(A;;GA;;;',
    'BuildDenyAllSecurityAttributes',
    'InitializeSecurityDescriptor',
    'InitializeAcl',
    'SetSecurityDescriptorDacl',
    'GetNamedPipeClientProcessId',
    'PROCESS_QUERY_LIMITED_INFORMATION',
    'OpenProcessToken',
    'ProcessIdToSessionId',
    'client_session != broker_session',
    '_wcsicmp(broker_sid.c_str(), client_sid.c_str())',
    'ERROR_ACCESS_DENIED',
    'UNRESOLVED-'
)) {
    if (-not $security.Contains($required)) {
        throw "System Broker Security V22 implementation missing: $required"
    }
}

foreach ($required in @(
    'PIPE_REJECT_REMOTE_CLIENTS',
    'ValidateNamedPipeClient(pipe, &client_process_id)',
    'Rejected unvalidated named-pipe client',
    'DisconnectNamedPipe(pipe)',
    'Failed to construct fail-closed pipe security',
    'CreateNamedPipeW('
)) {
    if (-not $broker.Contains($required)) {
        throw "System Broker Security V22 server guard missing: $required"
    }
}

foreach ($forbidden in @(
    'CURRENT_USER',
    'sa_ok ? &sa : nullptr',
    'sa_ok ? &sa : NULL'
)) {
    if ($security.Contains($forbidden) -or $broker.Contains($forbidden)) {
        throw "System Broker Security V22 fail-open regression found: $forbidden"
    }
}

# Listener creation must always pass the explicit SECURITY_ATTRIBUTES object.
if (-not $broker.Contains("            &sa);")) {
    throw 'System Broker named pipe must use the explicit fail-closed SECURITY_ATTRIBUTES object.'
}

if (-not $suite.Contains('test-system-broker-security-v22-contract.ps1')) {
    throw 'Central native suite must protect System Broker Security V22.'
}

Write-Host '[PASS] System Broker Security V22: protected current-user/SYSTEM DACL, deny-all fallback, remote-client rejection and PID/session/SID validation are fail-closed.'
