[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$paths = [ordered]@{
    ServerHeader = Join-Path $root 'desktop\CloudOS.SystemBroker\src\event_transport_v23.h'
    ServerSource = Join-Path $root 'desktop\CloudOS.SystemBroker\src\event_transport_v23.cpp'
    BusHeader = Join-Path $root 'desktop\CloudOS.SystemBroker\src\event_bus_v21.h'
    BusSource = Join-Path $root 'desktop\CloudOS.SystemBroker\src\event_bus_v21.cpp'
    Security = Join-Path $root 'desktop\CloudOS.SystemBroker\src\security_v21.cpp'
    BrokerMain = Join-Path $root 'desktop\CloudOS.SystemBroker\src\broker_main.cpp'
    BrokerProject = Join-Path $root 'desktop\CloudOS.SystemBroker\CloudOS.SystemBroker.vcxproj'
    FlutterEvents = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_event_client_v23.h'
    FlutterRpc = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_broker_client_v21.cpp'
}
foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Event Transport V23 contract input missing: $($entry.Value)"
    }
}

$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $text[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

foreach ($required in @(
    'GetEventsPipeName',
    'CreatePerUserSecurityAttributes',
    'PIPE_REJECT_REMOTE_CLIENTS',
    'ValidateNamedPipeClient',
    'ClientIdMatchesProcess',
    'CloudOS.EventTransport.V23',
    'kMaxQueuedEvents = 256',
    '4u * 1024u * 1024u',
    'RegisterDedicatedClientV23',
    'UnregisterDedicatedClientV23'
)) {
    if (-not $text.ServerSource.Contains($required)) {
        throw "Event Transport V23 server missing required isolation/bounding behavior: $required"
    }
}

if ($text.ServerSource -notmatch 'schema_it->second\.AsInt\(\)\s*!=\s*23' -or
    $text.ServerSource -notmatch 'parsed\s*==\s*static_cast<uint64_t>\(process_id\)') {
    throw 'Event Transport V23 handshake must enforce schema 23 and bind the RPC client id to the validated named-pipe PID.'
}

foreach ($required in @(
    'legacy_rpc_sender',
    'dedicated_v23_sender',
    'SetDedicatedTransportRequired',
    'RegisterDedicatedClientV23',
    'UnregisterDedicatedClientV23',
    'client_senders_.find(client_id)'
)) {
    if (-not ($text.BusHeader.Contains($required) -or $text.BusSource.Contains($required))) {
        throw "EventBus V21/V23 separation missing: $required"
    }
}
if ($text.BusSource -notmatch 'if \(it == client_senders_\.end\(\) \|\| !it->second\.legacy_rpc_sender\)') {
    throw 'Dedicated event clients must be rejected unless the exact RPC client id is still live.'
}
if ($text.BusSource -notmatch 'UnregisterDedicatedClientV23[\s\S]*dedicated_v23_sender\s*=\s*\{\}') {
    throw 'Event-pipe detach must clear only the dedicated sender instead of deleting the RPC subscription.'
}

foreach ($required in @(
    'event_transport_v23.h',
    'event_transport_v23.cpp'
)) {
    if (-not $text.BrokerProject.Contains($required)) {
        throw "SystemBroker build graph does not compile Event Transport V23: $required"
    }
}
if ($text.BrokerMain -notmatch 'EventTransportV23::Instance\(\)\.Start\(\)' -or
    $text.BrokerMain -notmatch 'SetDedicatedTransportRequired\(true\)') {
    throw 'SystemBroker runtime must start V23 and require the dedicated event channel before normal RPC operation.'
}

foreach ($required in @(
    'CloudOS.SystemBroker.Events.v21.',
    'CloudOS.EventTransport.V23',
    'kMaxQueuedEvents = 256',
    '4u * 1024u * 1024u',
    'kInitialReconnectMs = 250',
    'kMaxReconnectMs = 5000',
    'CreateEventW',
    'WaitForSingleObject',
    'CancelIoEx',
    'CancelSynchronousIo',
    'ParseEvent'
)) {
    if (-not $text.FlutterEvents.Contains($required)) {
        throw "Flutter Event Client V23 missing reconnect/bounding/shutdown behavior: $required"
    }
}
if ($text.FlutterEvents.Contains('CURRENT_USER') -or
    $text.FlutterRpc.Contains('CURRENT_USER')) {
    throw 'Flutter RPC/event pipe identity must fail closed; CURRENT_USER string fallbacks are forbidden.'
}
if ($text.FlutterRpc -match 'return\s+1\s*;[\r\n]+\s*\}[\r\n]+\s*return\s+session_id') {
    throw 'Flutter RPC pipe session identity must not silently fall back to session 1.'
}

foreach ($required in @(
    '#include "cloudos_event_client_v23.h"',
    'CloudOSEventClientV23::Instance().Start(client_id_)',
    'events.subscribe',
    'JsonValue("*")',
    'CloudOSEventClientV23::Instance().Stop()'
)) {
    if (-not $text.FlutterRpc.Contains($required)) {
        throw "Flutter RPC hello is not fully bound to Event Transport V23: $required"
    }
}

Write-Host '[PASS] Event Transport V23: RPC responses and events are separated, named pipes are user/session/PID bound, stale client ids are rejected, reconnect preserves RPC subscriptions, queues are bounded and Flutter shutdown/reconnect is deterministic.'
