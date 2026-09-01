# test-unified-files-v22-contract.ps1
# CloudOS V22 — Unified Files & Open With Architectural Contract Verification

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "`n[Contract-V22] Checking V22 Unified Files Architectural Constraints..." -ForegroundColor Cyan

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$fileServiceH = Join-Path $repoRoot 'desktop\CloudOS.SystemBroker\src\file_service_v22.h'
$fileServiceCpp = Join-Path $repoRoot 'desktop\CloudOS.SystemBroker\src\file_service_v22.cpp'
if (-not (Test-Path $fileServiceH) -or -not (Test-Path $fileServiceCpp)) {
    throw 'Missing file_service_v22.h or file_service_v22.cpp in SystemBroker source'
}

$fileServiceContent = Get-Content -Path $fileServiceCpp -Raw
if ($fileServiceContent -match 'system\(' -or $fileServiceContent -match 'cmd\.exe /c' -or $fileServiceContent -match 'powershell\.exe -Command') {
    throw 'Security violation: Arbitrary shell command execution detected in file_service_v22.cpp'
}
if ($fileServiceContent -notmatch 'IFileOperation' -and $fileServiceContent -notmatch 'SHFileOperationW' -and $fileServiceContent -notmatch 'FOF_ALLOWUNDO') {
    throw 'Missing safe Recycle Bin / IFileOperation implementation in file_service_v22.cpp'
}
if ($fileServiceContent -notmatch 'wsl\.localhost' -or $fileServiceContent -notmatch 'TryMapWindowsPathToLinux') {
    throw 'Missing WSL Linux path mapping and translation in file_service_v22.cpp'
}
if ($fileServiceContent -notmatch 'GetOpenWithList' -or $fileServiceContent -notmatch 'LaunchOpenWith') {
    throw 'Missing Open With association logic in file_service_v22.cpp'
}
if ($fileServiceContent -match 'JsonObject\s+gimp' -or $fileServiceContent -match 'Editor de Texto Linux') {
    throw 'Open With must not advertise guessed Linux applications.'
}
foreach ($requiredHardening in @(
    'IsWslCommandAvailable',
    'CopyPathRecursive',
    'CopyFileExW',
    'source_equals_destination',
    'destination_inside_source',
    'if (!ok && permanent)'
)) {
    if ($fileServiceContent.IndexOf($requiredHardening, [StringComparison]::Ordinal) -lt 0) {
        throw "Missing V22.1 file-operation hardening: $requiredHardening"
    }
}

$fileModelsDart = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\lib\models\file_models.dart'
$filesControllerDart = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\lib\services\files_controller.dart'
$filesWindowDart = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\lib\widgets\files_window.dart'
$bridgeDart = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\lib\services\cloudos_bridge.dart'
$nativeBridge = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_flutter_bridge_v20.cpp'
$nativeClient = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_broker_client_v21.cpp'
foreach ($requiredFile in @($fileModelsDart, $filesControllerDart, $filesWindowDart, $bridgeDart, $nativeBridge, $nativeClient)) {
    if (-not (Test-Path $requiredFile)) { throw "Missing V22 Flutter boundary file: $requiredFile" }
}

$filesWindowContent = Get-Content -Path $filesWindowDart -Raw
if ($filesWindowContent -notmatch 'FilesController' -or $filesWindowContent -notmatch 'Nova Aba') {
    throw 'FilesWindow is not connected to FilesController or lacks multi-tab support'
}

$controllerContent = Get-Content -Path $filesControllerDart -Raw
foreach ($requiredControllerHardening in @('_disposed', 'loadGeneration', "overwritePolicy: 'ask'", 'cancelActiveJob')) {
    if (-not $controllerContent.Contains($requiredControllerHardening)) {
        throw "Missing V22.1 Flutter FilesController hardening: $requiredControllerHardening"
    }
}
if ($controllerContent.Contains("overwritePolicy: 'replace'")) {
    throw 'FilesController must not silently replace destination data during paste.'
}

$bridgeContent = Get-Content -Path $bridgeDart -Raw
foreach ($forbiddenFallback in @('return previewFiles', 'return previewOpenWith', 'return previewKnownFolders', 'return previewDrives')) {
    if ($bridgeContent.Contains($forbiddenFallback)) {
        throw "Flutter runtime must not fabricate broker data: $forbiddenFallback"
    }
}

$nativeBridgeContent = Get-Content -Path $nativeBridge -Raw
foreach ($requiredBoundaryMarker in @('IsAllowedFlutterRpcMethod', 'generic_broker_rpc_restricted', 'event_subscription_exposed', 'event_demux_supported')) {
    if (-not $nativeBridgeContent.Contains($requiredBoundaryMarker)) {
        throw "Missing Flutter native bridge hardening marker: $requiredBoundaryMarker"
    }
}
# Even after V23 adds a typed event stream, the generic Dart RPC allowlist must
# never gain direct event subscription authority.
$allowlistMatch = [regex]::Match($nativeBridgeContent, 'static const std::unordered_set<std::string> allowed = \{(?<body>[\s\S]*?)\};')
if (-not $allowlistMatch.Success) { throw 'Could not locate Flutter generic RPC allowlist.' }
$allowlistBody = $allowlistMatch.Groups['body'].Value
if ($allowlistBody.Contains('events.subscribe') -or $allowlistBody.Contains('events.unsubscribe')) {
    throw 'Generic Flutter RPC must not expose Broker event subscription methods.'
}

$nativeClientContent = Get-Content -Path $nativeClient -Raw
foreach ($requiredClientHardening in @('AppendJsonString', 'IsSafeRpcMethod', 'LooksLikeJsonObjectPayload', 'GetCommandPipeName().empty()', 'ResponseReportsOk')) {
    if (-not $nativeClientContent.Contains($requiredClientHardening)) {
        throw "Missing Flutter broker client hardening: $requiredClientHardening"
    }
}
if ($nativeClientContent.Contains('L"CURRENT_USER"')) {
    throw 'Flutter broker client must fail closed instead of inventing a CURRENT_USER SID fallback.'
}
foreach ($forbiddenClientCapability in @('"jobs.submit"', '"system.brightness.write"')) {
    if ($nativeClientContent.Contains($forbiddenClientCapability)) {
        throw "Flutter broker client advertises unsupported/unsafe capability: $forbiddenClientCapability"
    }
}
if (($nativeClientContent.Contains('"events.subscribe"') -or $nativeClientContent.Contains('"events.unsubscribe"')) -and
    -not $nativeClientContent.Contains('broker.event_demux.v23')) {
    throw 'Event subscription capability may exist only with the V23 demultiplexed client transport.'
}

$jobsContent = Get-Content -Path (Join-Path $repoRoot 'desktop\CloudOS.SystemBroker\src\job_manager_v21.h') -Raw
if (-not $jobsContent.Contains('info_mutex') -or -not $jobsContent.Contains('kMaxRetainedJobs') -or -not $jobsContent.Contains('kMaxQueuedJobs')) {
    throw 'JobManager must synchronize job state and bound retained/queued job history.'
}

$probeMain = Join-Path $repoRoot 'desktop\CloudOS.BrokerProbe\main.cpp'
$probeContent = Get-Content -Path $probeMain -Raw
if ($probeContent -notmatch 'cmd == "list"' -or $probeContent -notmatch 'cmd == "open-with"') {
    throw 'CloudOS.BrokerProbe missing V22 file inspection commands'
}

Write-Host '[PASS] All V22 Unified Files & Open With Contract Assertions Passed.' -ForegroundColor Green
exit 0
