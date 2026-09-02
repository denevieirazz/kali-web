# CloudOS V22.1 / V23 feature pass — typed text-file architecture contract
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$textService = Join-Path $repoRoot 'desktop\CloudOS.SystemBroker\src\text_file_service_v23.h'
$brokerServer = Join-Path $repoRoot 'desktop\CloudOS.SystemBroker\src\broker_server_v21.cpp'
$runnerBridge = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\windows\runner\cloudos_flutter_bridge_v20.cpp'
$legacyBridge = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_flutter_bridge_v20.cpp'
$dartClient = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\lib\services\broker_text_file_service.dart'
$notepad = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\lib\widgets\notepad_window.dart'

foreach ($required in @($textService, $brokerServer, $runnerBridge, $legacyBridge, $dartClient, $notepad)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing V23 text-file boundary file: $required" }
}

$service = Get-Content -LiteralPath $textService -Raw
foreach ($marker in @(
    'kMaxTextFileBytes',
    '16ll * 1024ll * 1024ll',
    'kMaxChunkBytes',
    '64ll * 1024ll',
    'files.text.readChunk',
    'files.text.writeChunk',
    'files.text.abortWrite',
    'IsValidUtf8',
    'IsValidTransactionId',
    'FlushFileBuffers',
    'MoveFileExW',
    'MOVEFILE_WRITE_THROUGH',
    'MOVEFILE_REPLACE_EXISTING',
    'EventBusV21::Instance().Publish',
    'unsupported_encoding'
)) {
    if (-not $service.Contains($marker)) { throw "TextFileServiceV23 missing hardening marker: $marker" }
}
foreach ($forbidden in @('system(', 'cmd.exe', 'powershell.exe', 'ShellExecute', 'CreateProcess', 'WinExec')) {
    if ($service.Contains($forbidden)) { throw "TextFileServiceV23 contains forbidden execution surface: $forbidden" }
}

$broker = Get-Content -LiteralPath $brokerServer -Raw
if (-not $broker.Contains('#include "text_file_service_v23.h"') -or -not $broker.Contains('TextFileServiceV23::TryHandle')) {
    throw 'SystemBroker does not dispatch the typed text-file service.'
}

foreach ($bridgePath in @($runnerBridge, $legacyBridge)) {
    $bridge = Get-Content -LiteralPath $bridgePath -Raw
    foreach ($method in @('files.text.readChunk', 'files.text.writeChunk', 'files.text.abortWrite')) {
        if (-not $bridge.Contains('"' + $method + '"')) { throw "Bridge allowlist missing $method in $bridgePath" }
    }
    foreach ($forbiddenRpc in @('"files.execute"', '"files.command"', '"shell.execute"')) {
        if ($bridge.Contains($forbiddenRpc)) { throw "Bridge exposes forbidden general execution RPC $forbiddenRpc in $bridgePath" }
    }
}

$dart = Get-Content -LiteralPath $dartClient -Raw
foreach ($marker in @('maxFileBytes = 16 * 1024 * 1024', 'rpcChunkBytes = 64 * 1024', 'writeChunkBytes = 48 * 1024', 'files.text.readChunk', 'files.text.writeChunk', 'files.text.abortWrite', 'utf8.encode', 'utf8.decode')) {
    if (-not $dart.Contains($marker)) { throw "BrokerTextFileService missing bounded client marker: $marker" }
}
foreach ($forbidden in @("import 'dart:io'", 'Process.start', 'Process.run', 'Directory(', 'File(')) {
    if ($dart.Contains($forbidden)) { throw "BrokerTextFileService bypasses Broker boundary: $forbidden" }
}

$notepadContent = Get-Content -LiteralPath $notepad -Raw
if (-not $notepadContent.Contains('BrokerTextFileService')) {
    throw 'Notepad is not wired to BrokerTextFileService.'
}
foreach ($forbidden in @("import 'dart:io'", 'Platform.environment', 'Directory(', 'File(', 'Process.start', 'Process.run')) {
    if ($notepadContent.Contains($forbidden)) { throw "Notepad bypasses typed Broker filesystem boundary: $forbidden" }
}

Write-Host '[PASS] Typed text-file V23 architecture contract passed.' -ForegroundColor Green
exit 0
