[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$headerPath = Join-Path $root 'desktop\CloudOS.SystemBroker\src\broker_server_v21.h'
$sourcePath = Join-Path $root 'desktop\CloudOS.SystemBroker\src\broker_server_v21.cpp'
$suitePath = Join-Path $root 'scripts\native\test-native-contract-suite.ps1'

foreach ($path in @($headerPath, $sourcePath, $suitePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Broker client-I/O hardening input missing: $path"
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
    'struct ClientThreadEntry final',
    'std::shared_ptr<std::atomic_bool> finished',
    'std::vector<HANDLE> client_pipes_'
)) {
    Assert-Contains $header $required "Broker client lifecycle contract missing from header: $required"
}

foreach ($required in @(
    'kMaxQueuedEventFrames = 128',
    'kMaxQueuedEventBytes = 2 * kMaxPayloadBytes',
    'std::shared_ptr<ClientSendState>',
    'std::deque<std::string> event_queue',
    'PeekNamedPipe(',
    'CancelIoEx(pipe, nullptr)',
    'CancelSynchronousIo(entry.thread.native_handle())',
    'DisconnectNamedPipe(pipe)',
    'TryPopQueuedEvent',
    'send_state->active = false',
    'while (header_written < sizeof(len))',
    'while (header_bytes < sizeof(len))',
    'SendFrame(pipe, SerializeResponse(res))',
    'std::isfinite(value)',
    'value < 0.0 || value > 1.0'
)) {
    Assert-Contains $source $required "Broker client-I/O hardening contract missing: $required"
}

Assert-NotContains $source 'std::mutex send_mutex' 'Event sender must not rely on a stack-owned send mutex.'
Assert-NotContains $source '&send_mutex' 'EventBus callbacks must not capture a stack send mutex by reference.'

if ($source.IndexOf('CancelSynchronousIo(entry.thread.native_handle())', [System.StringComparison]::Ordinal) -gt
    $source.IndexOf('if (entry.thread.joinable()) entry.thread.join()', [System.StringComparison]::Ordinal)) {
    throw 'Broker shutdown must cancel synchronous client I/O before joining client threads.'
}

Assert-Contains $suite "'test-system-broker-client-io-v22-contract.ps1'" 'Central native contract suite must execute the Broker client-I/O V22 contract.'

Write-Host 'System Broker bounded client I/O + shutdown V22 contract: PASS'
