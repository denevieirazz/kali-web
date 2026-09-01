# test-reactive-broker-v23-contract.ps1
# CloudOS V23 — Reactive Broker / Event Stream structural contract

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Write-Host "`n[Contract-V23] Checking reactive Broker/Event Stream constraints..." -ForegroundColor Cyan

$clientH = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_broker_client_v21.h'
$clientCpp = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_broker_client_v21.cpp'
$bridgeH = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_flutter_bridge_v20.h'
$bridgeCpp = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_flutter_bridge_v20.cpp'
$eventsDart = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\lib\services\broker_events.dart'
$filesController = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\lib\services\files_controller.dart'
$shellDart = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\lib\shell\cloudos_shell.dart'
$quickDart = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\lib\widgets\quick_settings_panel.dart'
$probeMain = Join-Path $repoRoot 'desktop\CloudOS.BrokerProbe\main.cpp'
$probeProject = Join-Path $repoRoot 'desktop\CloudOS.BrokerProbe\CloudOS.BrokerProbe.vcxproj'

foreach ($path in @($clientH,$clientCpp,$bridgeH,$bridgeCpp,$eventsDart,$filesController,$shellDart,$quickDart,$probeMain,$probeProject)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing V23 contract file: $path" }
}

$clientHeader = Get-Content -LiteralPath $clientH -Raw
$client = Get-Content -LiteralPath $clientCpp -Raw
foreach ($marker in @(
    'PendingResponse',
    'std::condition_variable cv',
    'pending_responses_',
    'reader_thread_',
    'write_mutex_',
    'ConfigureEventSubscriptions',
    'kMaxPendingResponses',
    'kRpcTimeoutMs'
)) {
    if (-not $clientHeader.Contains($marker)) { throw "V23 client header missing: $marker" }
}
foreach ($marker in @(
    'StartReaderLocked',
    'ReaderLoop',
    'HandleIncomingFrame',
    'ExtractTopLevelStringField',
    'type == "response"',
    'type == "event"',
    'pending->cv.wait_for',
    'pending_responses_.erase',
    'FailAllPending',
    'ReconcileEventSubscriptions',
    'broker.event_demux.v23',
    'events.subscribe',
    'events.unsubscribe'
)) {
    if (-not $client.Contains($marker)) { throw "V23 client implementation missing: $marker" }
}
if ($client.Contains('response.find("\\"ok\\":true")')) {
    throw 'V23 must not classify broker envelopes using a raw ok:true substring search.'
}
if ($client.Contains('L"CURRENT_USER"')) {
    throw 'V23 client regressed to an invented user SID fallback.'
}

$bridgeHeader = Get-Content -LiteralPath $bridgeH -Raw
$bridge = Get-Content -LiteralPath $bridgeCpp -Raw
foreach ($marker in @('broker_event_queue_', 'kMaxQueuedBrokerEvents', 'channel_', 'event_drain_scheduled_')) {
    if (-not $bridgeHeader.Contains($marker)) { throw "V23 Flutter bridge header missing: $marker" }
}
foreach ($marker in @(
    'StartBrokerEventStream',
    'QueueBrokerEvent',
    'DrainBrokerEventsOnPlatformThread',
    'SetTimer',
    'EventDrainTimerProc',
    'InvokeMethod(',
    '"brokerEvent"',
    '"startBrokerEvents"',
    'event_demux_supported',
    'event_stream_active'
)) {
    if (-not $bridge.Contains($marker)) { throw "V23 Flutter bridge implementation missing: $marker" }
}
$allowlistMatch = [regex]::Match($bridge, 'static const std::unordered_set<std::string> allowed = \{(?<body>[\s\S]*?)\};')
if (-not $allowlistMatch.Success) { throw 'Could not locate V23 generic Flutter RPC allowlist.' }
$allowlistBody = $allowlistMatch.Groups['body'].Value
if ($allowlistBody.Contains('events.subscribe') -or $allowlistBody.Contains('events.unsubscribe')) {
    throw 'V23 typed event stream must not expose subscription methods through generic Dart RPC.'
}
foreach ($approvedPattern in @('"system.*"','"files.*"','"job.*"')) {
    if (-not $bridge.Contains($approvedPattern)) { throw "V23 bridge missing approved native event family: $approvedPattern" }
}

$events = Get-Content -LiteralPath $eventsDart -Raw
foreach ($marker in @(
    'class CloudOSBrokerEvent',
    'StreamController<CloudOSBrokerEvent>.broadcast',
    "invokeMethod<bool>('startBrokerEvents')",
    "call.method != 'brokerEvent'",
    "decoded['type'] != 'event'"
)) {
    if (-not $events.Contains($marker)) { throw "V23 Dart event stream missing: $marker" }
}

$files = Get-Content -LiteralPath $filesController -Raw
foreach ($marker in @(
    'CloudOSBrokerEvents.instance.stream.listen',
    "event.name == 'files.changed'",
    "event.name == 'job.progress'",
    "'job.completed'",
    "'job.failed'",
    "'job.cancelled'",
    '_waitForJobReactive',
    'completer.future.timeout',
    '_waitForJobPollingFallback'
)) {
    if (-not $files.Contains($marker)) { throw "V23 Files reactive integration missing: $marker" }
}
$reactiveMethod = [regex]::Match($files, 'Future<void> _waitForJobReactive[\s\S]*?Future<void> _waitForJobPollingFallback')
if (-not $reactiveMethod.Success) { throw 'Unable to isolate V23 reactive job wait implementation.' }
if ($reactiveMethod.Value.Contains('Future<void>.delayed')) {
    throw 'V23 production reactive job wait contains a polling delay loop.'
}

$shell = Get-Content -LiteralPath $shellDart -Raw
foreach ($marker in @('CloudOSBrokerEvents.instance.stream.listen', "event.name == 'system.volumeChanged'", '_refreshSystemSnapshotFromEvent')) {
    if (-not $shell.Contains($marker)) { throw "V23 shell reactive integration missing: $marker" }
}
$quick = Get-Content -LiteralPath $quickDart -Raw
if (-not $quick.Contains('didUpdateWidget') -or -not $quick.Contains('widget.snapshot.volume')) {
    throw 'Quick Settings does not reconcile external reactive system snapshots.'
}

$probe = Get-Content -LiteralPath $probeMain -Raw
foreach ($marker in @('reactive-self-test', 'event-before-response-one', 'kConcurrentRequests = 8', 'reconnect_subscription_restore')) {
    if (-not $probe.Contains($marker)) { throw "V23 runtime probe missing: $marker" }
}
$project = Get-Content -LiteralPath $probeProject -Raw
if (-not $project.Contains('cloudos_broker_client_v21.cpp')) {
    throw 'BrokerProbe does not compile the actual V23 Flutter broker client.'
}
if (-not $project.Contains('TreatWarningAsError>true')) {
    throw 'BrokerProbe V23 harness must compile with warnings as errors.'
}

foreach ($content in @($client,$bridge,$events,$files,$shell)) {
    if ($content -match 'Winlogon' -and $content -match 'RegSetValue') {
        throw 'V23 reactive path must not mutate Winlogon.'
    }
    if ($content -match 'UserChoice' -and $content -match 'RegSetValue') {
        throw 'V23 reactive path must not mutate protected UserChoice associations.'
    }
}

Write-Host '[PASS] V23 Reactive Broker / Event Stream contract passed.' -ForegroundColor Green
exit 0
