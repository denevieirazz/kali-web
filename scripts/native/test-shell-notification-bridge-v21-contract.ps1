[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Read-RepoFile([string]$relativePath) {
    $path = Join-Path $root $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing notification bridge contract file: $relativePath"
    }
    return Get-Content -LiteralPath $path -Raw
}

$contract = Read-RepoFile 'desktop/CloudOS.NativeCommon/native_shell_activation_v21.h'
$client = Read-RepoFile 'desktop/CloudOS.NativeCommon/native_shell_activation_client_v21.h'
$server = Read-RepoFile 'desktop/CloudOS.NativeShell/src/native_shell_activation_server_v21.h'
$centerHeader = Read-RepoFile 'desktop/CloudOS.NativeShell/src/native_notification_center.h'
$centerSource = Read-RepoFile 'desktop/CloudOS.NativeShell/src/native_notification_center.cpp'
$bridge = Read-RepoFile 'desktop/CloudOS.FlutterShell/native_bridge/cloudos_flutter_bridge_v20.cpp'
$dartBridge = Read-RepoFile 'desktop/CloudOS.FlutterShell/lib/services/cloudos_bridge.dart'
$taskbar = Read-RepoFile 'desktop/CloudOS.FlutterShell/lib/features/taskbar/presentation/cloud_taskbar.dart'

foreach ($needle in @('NotificationAction', 'NotificationRequest', 'NotificationSnapshot', 'kNotificationCopyDataTag', 'kNotificationMaxItems')) {
    if (-not $contract.Contains($needle)) { throw "Notification V21 contract missing: $needle" }
}
if (-not $client.Contains('CreateFileMappingW') -or -not $client.Contains('QueryNotifications')) {
    throw 'Notification query must use ephemeral shared memory owned by the caller.'
}
if (-not $server.Contains('OpenFileMappingW') -or -not $server.Contains('HandleNotificationRequest')) {
    throw 'NativeShell activation server must fill the bounded notification snapshot.'
}
foreach ($needle in @('Snapshot(', 'Dismiss(', 'ClearAll(', 'MarkAllRead(')) {
    if (-not $centerHeader.Contains($needle)) { throw "Notification authority API missing: $needle" }
}
if (-not $centerSource.Contains('g_notifications')) {
    throw 'NativeShell notification center must remain the authoritative in-process store.'
}
foreach ($needle in @('getNotificationState', 'markNotificationsRead', 'dismissNotification', 'clearNotifications')) {
    if (-not $bridge.Contains($needle) -or -not $dartBridge.Contains($needle)) {
        throw "Flutter notification bridge method missing: $needle"
    }
}
if ($taskbar -match 'notificationCount\s*=\s*3') {
    throw 'Taskbar must not ship a fixed unread notification count.'
}
if ($contract -match '(?i)command.{0,30}notification|notification.{0,30}command') {
    throw 'Notification bridge must remain typed; generic command passthrough is forbidden.'
}

Write-Host 'PASS: NativeShell V21 notification authority is typed, bounded and wired to Flutter.'
