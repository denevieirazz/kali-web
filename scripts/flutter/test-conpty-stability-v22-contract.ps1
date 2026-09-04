[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$headerPath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_conpty_manager.h'
$sourcePath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_conpty_manager.cpp'
$suitePath = Join-Path $root 'scripts\native\test-native-contract-suite.ps1'

foreach ($path in @($headerPath, $sourcePath, $suitePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "ConPTY stability V22 contract input missing: $path"
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

foreach ($required in @(
    'kMaxSessions = 32',
    'kMaxPendingEventFrames = 256',
    'kMaxPendingEventBytes = 2 * 1024 * 1024',
    'kMaxWriteBytes = 1024 * 1024',
    'kMaxDistroNameBytes = 256',
    'kProcessExitWaitMs = 1000',
    'pending_event_bytes_{0}',
    'bool QueuePlatformEvent(PlatformEvent event)'
)) {
    Assert-Contains $header $required "ConPTY stability header invariant missing: $required"
}

foreach ($required in @(
    'sessions_.size() >= kMaxSessions',
    'distro.size() > kMaxDistroNameBytes',
    'input_data.size() > kMaxWriteBytes',
    'pending_events_.size() >= kMaxPendingEventFrames',
    'pending_event_bytes_ > kMaxPendingEventBytes - event_bytes',
    'if (!PostMessageW(window, kDispatchMessage, 0, 0))',
    'pending_event_bytes_ = 0',
    'while (total_written < input_data.size())',
    'bytes_written == 0',
    'WaitForSingleObject(process, kProcessExitWaitMs)',
    'TerminateProcess(process, ERROR_NOT_ENOUGH_MEMORY)',
    'SetPlatformWindow(nullptr)',
    'SetMethodChannel(nullptr)'
)) {
    Assert-Contains $source $required "ConPTY stability implementation invariant missing: $required"
}

if ($source.Contains('WaitForSingleObject(process, INFINITE)', [System.StringComparison]::Ordinal)) {
    throw 'ConPTY reader/cleanup must not use an unbounded process wait.'
}

Assert-Contains $suite "'..\flutter\test-conpty-stability-v22-contract.ps1'" 'Central native suite must execute the ConPTY stability V22 contract.'

Write-Host 'ConPTY bounded sessions/events/IO/shutdown V22 contract: PASS'
