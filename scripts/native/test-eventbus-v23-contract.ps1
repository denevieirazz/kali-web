# CloudOS V23 — dedicated Flutter EventBus transport architecture contract
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runner = Join-Path $root 'desktop\CloudOS.FlutterShell\windows\runner'
$lib = Join-Path $root 'desktop\CloudOS.FlutterShell\lib'
$tests = Join-Path $root 'desktop\CloudOS.FlutterShell\test'
$broker = Join-Path $root 'desktop\CloudOS.SystemBroker\src'

function Read-Source([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Required source missing: $Path" }
    return [IO.File]::ReadAllText($Path)
}

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
    if (-not $Text.Contains($Needle, [StringComparison]::Ordinal)) { throw $Message }
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Message) {
    if ($Text.Contains($Needle, [StringComparison]::Ordinal)) { throw $Message }
}

function Assert-Before(
    [string]$Text,
    [string]$First,
    [string]$Second,
    [string]$Message
) {
    $firstIndex = $Text.IndexOf($First, [StringComparison]::Ordinal)
    $secondIndex = $Text.IndexOf($Second, [StringComparison]::Ordinal)
    if ($firstIndex -lt 0 -or $secondIndex -lt 0 -or $firstIndex -ge $secondIndex) {
        throw $Message
    }
}

$eventHeader = Read-Source (Join-Path $runner 'cloudos_broker_event_client_v23.h')
$eventCpp = Read-Source (Join-Path $runner 'cloudos_broker_event_client_v23.cpp')
$flutterWindow = Read-Source (Join-Path $runner 'flutter_window.cpp')
$cmake = Read-Source (Join-Path $runner 'CMakeLists.txt')
$rpcBridge = Read-Source (Join-Path $runner 'cloudos_flutter_bridge_v20.cpp')
$dartBridge = Read-Source (Join-Path $lib 'services\broker_event_bridge_v23.dart')
$runtime = Read-Source (Join-Path $lib 'services\runtime_event_service.dart')
$runtimeTest = Read-Source (Join-Path $tests 'runtime_event_service_test.dart')
$taskbar = Read-Source (Join-Path $lib 'widgets\cloud_taskbar.dart')
$server = Read-Source (Join-Path $broker 'broker_server_v21.cpp')

Assert-Contains $eventHeader 'kMaxPendingUiEvents = 256' 'Native EventBus UI queue must remain bounded to 256 frames.'
Assert-Contains $eventHeader 'kMaxPendingUiBytes = 4 * 1024 * 1024' 'Native EventBus UI queue must remain bounded by bytes.'
Assert-Contains $eventCpp 'cloudos/native/events/v23' 'Dedicated event MethodChannel name is missing.'
Assert-Contains $eventCpp 'events.subscribe' 'Native event client no longer subscribes through the typed EventBus method.'
Assert-Contains $eventCpp '"{\"pattern\":\"*\"}"' 'Native event client must subscribe to the explicit wildcard pattern.'
Assert-Contains $eventCpp 'WaitNamedPipeW' 'Event transport lost bounded pipe wait/reconnect behavior.'
Assert-Contains $eventCpp 'kInitialReconnectDelayMs = 250' 'Event reconnect initial delay changed without contract update.'
Assert-Contains $eventCpp 'kMaxReconnectDelayMs = 5000' 'Event reconnect ceiling changed without contract update.'
Assert-Contains $eventCpp 'PostMessageW' 'Event worker must marshal delivery onto the Flutter UI thread.'
Assert-Contains $eventCpp 'broker.onEvent' 'Native event delivery method is missing.'
Assert-Contains $eventCpp 'broker.onConnectionState' 'Native connection-state delivery method is missing.'
Assert-Contains $eventCpp 'call.method_name() == "start"' 'Event transport must expose explicit start lifecycle semantics.'
Assert-Contains $eventCpp 'call.method_name() == "stop"' 'Event transport must expose deterministic stop semantics.'
Assert-Contains $eventCpp 'call.method_name() == "status"' 'Event transport must expose read-only status diagnostics.'
Assert-NotContains $eventCpp 'shell.execute' 'Arbitrary shell execution is forbidden on the event transport.'
Assert-NotContains $eventCpp 'files.execute' 'Generic file execution is forbidden on the event transport.'

Assert-Contains $cmake 'cloudos_broker_event_client_v23.cpp' 'Windows Release target does not compile the V23 EventBus client.'
Assert-Contains $flutterWindow 'CloudOSBrokerEventClientV23::Instance().Initialize(' 'Flutter window must initialize the event channel with the engine messenger.'
Assert-Contains $flutterWindow 'CloudOSBrokerEventClientV23::Instance().Shutdown()' 'Flutter window teardown must stop the event transport before engine teardown.'
Assert-Contains $flutterWindow 'CloudOSBrokerEventClientV23::kDispatchMessage' 'Flutter window must drain native events on its platform message loop.'

Assert-Contains $dartBridge "cloudos/native/events/v23" 'Dart bridge is not bound to the dedicated event channel.'
Assert-Contains $dartBridge "invokeMethod<bool>('start')" 'Dart must explicitly start native EventBus transport.'
Assert-Before $dartBridge '_channel.setMethodCallHandler(_handleNativeCall);' '_startFuture = _invokeStart();' 'Dart must install its native-call handler before starting EventBus transport.'
Assert-NotContains $dartBridge 'invokeBrokerRpc' 'Dedicated event bridge must not expose synchronous broker business RPC.'
Assert-NotContains $dartBridge 'shell.execute' 'Dart event bridge exposes an arbitrary command surface.'

Assert-Contains $runtime 'maxJournalEntries = 256' 'Runtime journal must remain bounded.'
Assert-Contains $runtime 'maxNotifications = 100' 'Runtime notification retention must remain bounded.'
Assert-Contains $runtime 'nativeDroppedEventCount' 'Runtime service lost native drop telemetry.'
Assert-Contains $runtimeTest "test('job.progress never creates notification spam'" 'Runtime tests must prove job.progress does not fabricate notification spam.'
Assert-Contains $runtimeTest 'expect(service.notifications, isEmpty);' 'Runtime tests must assert progress events create no notifications.'
Assert-Contains $taskbar '_runtimeEvents.unreadCount' 'Taskbar no longer uses real unread notification state.'
Assert-NotContains $taskbar 'notificationCount = 3' 'Fabricated taskbar notification count returned.'

# The generic synchronous RPC pipe remains response-only from Flutter's point
# of view. Event subscription is available only on the dedicated connection.
Assert-NotContains $rpcBridge '"events.subscribe",' 'Generic Flutter RPC allowlist must not expose events.subscribe.'
Assert-NotContains $rpcBridge '"events.unsubscribe",' 'Generic Flutter RPC allowlist must not expose events.unsubscribe.'

# Broker-side publication must enqueue and return; it must never write from the
# EventBus publisher callback itself or flush synchronously during teardown.
Assert-Contains $server 'kMaxQueuedEventFrames = 128' 'Broker per-client event queue frame bound is missing.'
Assert-Contains $server 'kMaxQueuedEventBytes = 2 * kMaxPayloadBytes' 'Broker per-client event queue byte bound is missing.'
Assert-Contains $server 'event_queue.push_back' 'Broker EventBus callback is no longer queue-backed.'
Assert-Contains $server 'event_writer' 'Broker lost the dedicated per-client event writer.'
Assert-NotContains $server 'FlushFileBuffers(pipe)' 'Blocking teardown FlushFileBuffers returned to Broker client teardown.'

Write-Host '[PASS] Dedicated Flutter EventBus V23 architecture contract passed.' -ForegroundColor Green
exit 0
