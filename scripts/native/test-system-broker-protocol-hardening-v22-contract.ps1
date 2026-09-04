[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$protocolPath = Join-Path $root 'desktop\CloudOS.SystemBroker\src\protocol_v21.cpp'
$brokerMainPath = Join-Path $root 'desktop\CloudOS.SystemBroker\src\broker_main.cpp'
$suitePath = Join-Path $root 'scripts\native\test-native-contract-suite.ps1'
foreach ($path in @($protocolPath, $brokerMainPath, $suitePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Protocol hardening V22 contract input missing: $path"
    }
}

$protocol = Get-Content -LiteralPath $protocolPath -Raw
$brokerMain = Get-Content -LiteralPath $brokerMainPath -Raw
$suite = Get-Content -LiteralPath $suitePath -Raw

foreach ($required in @(
    'kMaxJsonDepth = 64',
    'kMaxJsonContainerItems = 65536',
    'std::from_chars',
    'std::strtod',
    'errno == ERANGE',
    'std::isfinite(parsed)',
    'AppendUtf8CodePoint',
    'ParseHexUnit',
    'if (static_cast<unsigned char>(c) < 0x20) return false',
    'if (obj.find(key) != obj.end()) return false',
    'if (depth > kMaxJsonDepth) return false',
    'catch (...)',
    'it_id->second.AsString().size() > kMaxRequestIdLength',
    'it_method->second.AsString().size() > kMaxMethodLength',
    'Invalid request ''payload''; expected an object',
    'Invalid response payload',
    'Missing response error object',
    'Invalid event payload',
    'Invalid event timestamp'
)) {
    if (-not $protocol.Contains($required, [StringComparison]::Ordinal)) {
        throw "System Broker protocol hardening contract missing: $required"
    }
}

foreach ($forbidden in @(
    'std::stod(num_str)',
    'std::stoll(num_str)',
    "out.push_back('?')"
)) {
    if ($protocol.Contains($forbidden, [StringComparison]::Ordinal)) {
        throw "System Broker protocol parser regressed to unsafe behavior: $forbidden"
    }
}

foreach ($runtimeAssertion in @(
    'Reject invalid JSON escape',
    'Reject invalid Unicode hex escape',
    'Reject lone high surrogate',
    'Reject lone low surrogate',
    'Reject leading-zero number',
    'Reject fraction without digits',
    'Reject exponent without digits',
    'Reject int64 overflow',
    'Reject non-finite float overflow',
    'Reject duplicate object keys',
    'Reject excessive JSON nesting',
    'Reject non-object request payload',
    'Reject failed response without typed error object',
    'Reject negative event timestamp'
)) {
    if (-not $brokerMain.Contains($runtimeAssertion, [StringComparison]::Ordinal)) {
        throw "System Broker runtime self-test does not exercise protocol hardening: $runtimeAssertion"
    }
}

if (-not $suite.Contains('test-system-broker-protocol-hardening-v22-contract.ps1', [StringComparison]::Ordinal)) {
    throw 'Central native suite must protect System Broker protocol hardening V22.'
}

Write-Host '[PASS] System Broker protocol hardening V22: bounded nesting/containers, strict JSON escapes/Unicode, non-throwing finite numbers, typed envelopes and executable self-test coverage.'
