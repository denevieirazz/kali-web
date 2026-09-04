[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$headerPath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_broker_client_v21.h'
$sourcePath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_broker_client_v21.cpp'
$suitePath = Join-Path $root 'scripts\native\test-native-contract-suite.ps1'

foreach ($path in @($headerPath, $sourcePath, $suitePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Flutter Broker client hardening input missing: $path"
    }
}

$header = Get-Content -LiteralPath $headerPath -Raw
$source = Get-Content -LiteralPath $sourcePath -Raw
$suite = Get-Content -LiteralPath $suitePath -Raw

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
    if (-not $Text.Contains($Needle, [System.StringComparison]::Ordinal)) {
        throw $Message
    }
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Message) {
    if ($Text.Contains($Needle, [System.StringComparison]::Ordinal)) {
        throw $Message
    }
}

foreach ($required in @(
    'uint32_t session_id{0}',
    'std::atomic_uint64_t last_spawn_attempt_ms_{0}'
)) {
    Assert-Contains $header $required "Flutter Broker client header hardening missing: $required"
}

foreach ($required in @(
    'IsValidSid(token_user->User.Sid)',
    'TryGetCurrentSessionId',
    'if (sid.empty() || !TryGetCurrentSessionId(session_id)) return {}',
    'if (GetCommandPipeName().empty())',
    'if (pipe_name.empty()) return false',
    'now - previous < 5000',
    'while (header_written < sizeof(len))',
    'while (header_bytes < sizeof(len))',
    'client_id_.empty() || server_instance_id_.empty()',
    'std::isfinite(value)',
    'value < 0.0 || value > 1.0',
    'session_id < 0 || session_id > UINT32_MAX'
)) {
    Assert-Contains $source $required "Flutter Broker client hardening missing: $required"
}

foreach ($forbidden in @(
    'return L"CURRENT_USER"',
    'return 1;',
    'C:\\CloudOS\\desktop\\CloudOS.NativeShell\\bin\\Release\\CloudOS.SystemBroker.exe'
)) {
    Assert-NotContains $source $forbidden "Flutter Broker client fail-open/unsafe fallback returned: $forbidden"
}

Assert-Contains $suite "'test-flutter-broker-client-hardening-v22-contract.ps1'" 'Central native suite must execute the Flutter Broker client hardening contract.'

Write-Host 'Flutter Broker client identity/framing V22 hardening contract: PASS'
