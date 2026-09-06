[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Assert-FileContains {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string[]]$Needles,
        [string]$Description = ''
    )

    $fullPath = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "File missing for contract ($Description): $RelativePath"
    }

    $content = Get-Content -LiteralPath $fullPath -Raw
    foreach ($needle in $Needles) {
        if (-not $content.Contains($needle)) {
            throw "Contract check failed in $RelativePath ($Description). Expected to contain: '$needle'"
        }
    }
}

# 1. Native Window Registry Protocol V23 Header
Assert-FileContains -RelativePath 'desktop\CloudOS.NativeCommon\native_window_registry_v23.h' -Needles @(
    'kSchema = 23',
    'kWindowCommandCopyDataTag',
    'kWindowSnapshotCopyDataTag',
    'kWindowServerClass',
    'CloudWindowRecordV23',
    'CloudMonitorRecordV23',
    'CloudWindowEventV23',
    'CloudWindowSnapshotV23',
    'WindowCommandPayload',
    'ToJson() const'
) -Description 'Native Window Registry V23 Protocol Header'

# 2. NativeShell Window Manager Authority
Assert-FileContains -RelativePath 'desktop\CloudOS.NativeShell\src\native_window_manager.h' -Needles @(
    'GetRegistrySnapshot',
    'GetRegistrySnapshotJson',
    'WriteRegistrySnapshotToMapping',
    'ExecuteWindowCommand',
    'SnapWindow',
    'MinimizeWindow',
    'MaximizeWindow',
    'RestoreWindow',
    'CloseWindow',
    'SetWindowBounds',
    'SetWindowFullscreen'
) -Description 'NativeShell Window Manager Declarations'

Assert-FileContains -RelativePath 'desktop\CloudOS.NativeShell\src\native_window_manager.cpp' -Needles @(
    'GetRegistrySnapshot',
    'GetRegistrySnapshotJson',
    'WriteRegistrySnapshotToMapping',
    'OpenFileMappingW',
    'MapViewOfFile',
    'CloudOS::WindowRegistryV23::CloudWindowSnapshotV23',
    'CloudOS::NativeMonitorManager::Enumerate()',
    'ShowWindow(window, SW_MINIMIZE)',
    'SW_MAXIMIZE',
    'SW_RESTORE'
) -Description 'NativeShell Window Manager Implementation'

# 3. NativeShell Activation Server
Assert-FileContains -RelativePath 'desktop\CloudOS.NativeShell\src\native_shell_activation_server_v21.h' -Needles @(
    'kWindowCommandCopyDataTag',
    'kWindowSnapshotCopyDataTag'
) -Description 'NativeShell Activation Server Window Tags'

# 4. SystemBroker Window Service V23
Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\window_service_v23.h' -Needles @(
    'WindowServiceV23',
    'GetSnapshot',
    'ExecuteCommand',
    'FocusWindow',
    'MinimizeWindow',
    'MaximizeWindow',
    'RestoreWindow',
    'CloseWindow',
    'SetBounds',
    'SnapWindow',
    'MoveToWorkspace',
    'SetFullscreen'
) -Description 'SystemBroker Window Service V23 Header'

Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\window_service_v23.cpp' -Needles @(
    'CloudOS.WindowSnapshot.v23.',
    'kWindowSnapshotCopyDataTag',
    'kWindowCommandCopyDataTag',
    'window.snapshotChanged'
) -Description 'SystemBroker Window Service V23 Implementation'

# 5. SystemBroker RPC Dispatch
Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\broker_server_v21.cpp' -Needles @(
    'window.snapshot',
    'window.focus',
    'window.minimize',
    'window.maximize',
    'window.restore',
    'window.close',
    'window.setBounds',
    'window.snap',
    'window.moveToWorkspace',
    'window.setFullscreen',
    'monitor.list'
) -Description 'SystemBroker RPC Dispatch for Windows'

# 6. Flutter Native Bridge & Runner
Assert-FileContains -RelativePath 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_flutter_bridge_v20.cpp' -Needles @(
    'window.getSnapshot',
    'window.focus',
    'window.minimize',
    'window.maximize',
    'window.restore',
    'window.close',
    'window.setBounds',
    'window.snap',
    'window.moveToWorkspace',
    'window.setFullscreen',
    'monitor.list'
) -Description 'Flutter Native Bridge Method Handlers'

$runnerBridge = Join-Path $root 'desktop\CloudOS.FlutterShell\windows\runner\cloudos_flutter_bridge_v20.cpp'
if (Test-Path -LiteralPath $runnerBridge) {
    Assert-FileContains -RelativePath 'desktop\CloudOS.FlutterShell\windows\runner\cloudos_flutter_bridge_v20.cpp' -Needles @(
        'window.getSnapshot',
        'window.focus',
        'window.minimize',
        'window.maximize',
        'window.restore',
        'window.close',
        'window.setBounds',
        'window.snap',
        'window.moveToWorkspace',
        'window.setFullscreen',
        'monitor.list'
    ) -Description 'Flutter Runner Method Handlers'
}

# 7. Flutter Dart Bridge & Models
Assert-FileContains -RelativePath 'desktop\CloudOS.FlutterShell\lib\services\cloudos_bridge.dart' -Needles @(
    'tryLoadWindowSnapshot',
    'focusWindow',
    'minimizeWindow',
    'maximizeWindow',
    'restoreWindow',
    'closeWindow',
    'setWindowBounds',
    'snapWindow',
    'moveWindowToWorkspace',
    'setWindowFullscreen',
    'listMonitors'
) -Description 'Flutter CloudOSBridge Window Methods'

Assert-FileContains -RelativePath 'desktop\CloudOS.FlutterShell\lib\shell\window_manager\cloud_window.dart' -Needles @(
    'CloudWindowSnapshot',
    'CloudMonitorRecord',
    'platform',
    'hwnd',
    'pid',
    'appId',
    'capabilities',
    'fromJsonString',
    'toJson'
) -Description 'Flutter CloudWindow and CloudWindowSnapshot Models'

Assert-FileContains -RelativePath 'desktop\CloudOS.FlutterShell\lib\shell\cloudos_shell.dart' -Needles @(
    '_getUnifiedWindows()',
    'windowSnapshot',
    '_refreshWindowSnapshot'
) -Description 'Flutter CloudOSShell Window Management Integration'

Write-Host '[PASS] Window Registry V23 Contract: All native, broker, bridge, and Flutter window manager contracts verified.'
