$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'
$project = Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj') -Raw

$paths = @{
    Quick = Join-Path $src 'native_quick_settings_window_v4.cpp'
    Backend = Join-Path $src 'native_system_control_backend.cpp'
    BackendHeader = Join-Path $src 'native_system_control_backend.h'
    SystemCenter = Join-Path $src 'native_system_control_window.cpp'
    Tray = Join-Path $src 'native_cloudos_tray.cpp'
    Toast = Join-Path $src 'native_toast_overlay.cpp'
    Service = Join-Path $src 'native_control_plane_service.cpp'
    Appearance = Join-Path $src 'native_appearance_manager.cpp'
    Studio = Join-Path $src 'native_workspace_studio_service.cpp'
    Continuity = Join-Path $src 'native_session_continuity_service.cpp'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Shell Control Plane file missing [$($entry.Key)]: $($entry.Value)"
    }
}

$content = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}
$content.Quick += Get-Content -LiteralPath (Join-Path $src 'native_quick_model_v12.h') -Raw
$content.Backend = (Get-Content -LiteralPath $paths.BackendHeader -Raw) + "`n" + $content.Backend

function Require([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) {
            throw "$Name contract missing: $token"
        }
    }
}

function Forbid([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if ($Text.Contains($token)) {
            throw "$Name forbidden regression found: $token"
        }
    }
}

Require 'Unified build graph' $project @(
    'src\native_system_control_backend.cpp',
    'src\native_system_control_window.cpp',
    'src\native_workspace_studio_service.cpp',
    'src\native_session_continuity_service.cpp',
    'src\native_control_plane_service.cpp',
    'src\native_cloudos_tray.cpp',
    'src\native_toast_overlay.cpp',
    'src\native_appearance_manager.cpp',
    'src\native_quick_settings_window_v4.cpp',
    'wlanapi.lib',
    'dxva2.lib',
    'iphlpapi.lib',
    'powrprof.lib',
    'wbemuuid.lib'
)
Forbid 'Unified build graph' $project @(
    '<ClCompile Include="src\native_quick_settings_window.cpp"',
    '<ClCompile Include="src\native_app_launcher.cpp"',
    '<ClCompile Include="src\native_app_launcher_v2.cpp"'
)

Require 'System backend' $content.Backend @(
    'NativeSystemControlBackend',
    'ScanWifi',
    'WlanOpenHandle',
    'WlanGetAvailableNetworkList',
    'ConnectKnownWifi',
    'WlanConnect',
    'DisconnectWifi',
    'IAudioEndpointVolume',
    'SetMasterVolume',
    'QueryBrightness',
    'SetBrightness',
    'GetPhysicalMonitorsFromHMONITOR',
    'WmiMonitorBrightness',
    'QueryPower',
    'PowerSetActiveScheme',
    'GetAdaptersAddresses',
    'GetDiskFreeSpaceExW',
    'CreateToolhelp32Snapshot',
    'Process32FirstW',
    'Process32NextW',
    'GetProcessMemoryInfo'
)

Require 'Quick Settings V4' $content.Quick @(
    'CloudOS.NativeShell.QuickSettings.v4',
    'NativeSystemControlBackend::QueryAudio',
    'NativeSystemControlBackend::SetMasterVolume',
    'NativeSystemControlBackend::ScanWifi',
    'NativeSystemControlBackend::ConnectKnownWifi',
    'NativeSystemControlBackend::DisconnectWifi',
    'NativeSystemControlBackend::QueryBrightness',
    'NativeSystemControlBackend::SetBrightness',
    'NativeSystemControlBackend::SetBalancedPowerPlan',
    'NativeSystemControlBackend::SetPowerSaverPlan',
    'NativeSystemControlBackend::SetHighPerformancePlan',
    'CloudOSNativeSystemControlWindow::Open',
    'ms-settings:network-wifi',
    'ms-settings:bluetooth',
    'NativeAppearanceManager::NextPresetAccent'
)

Require 'First-party CloudOS tray' $content.Tray @(
    'CloudOS.NativeShell.Taskbar.v4',
    'SetWindowSubclass',
    'TaskbarSubclass',
    'PaintTray',
    'DrawSpeaker',
    'DrawWifi',
    'DrawBattery',
    'WM_MOUSEWHEEL',
    'WM_MBUTTONUP',
    'WM_RBUTTONUP',
    'CloudOSNativeSystemControlWindow::Open',
    'NativeSystemControlBackend::SetMasterMute'
)
Forbid 'First-party CloudOS tray' $content.Tray @(
    'Shell_NotifyIcon',
    'SetParent(',
    'CreateRemoteThread',
    'WriteProcessMemory'
)

Require 'Live toast overlay' $content.Toast @(
    'CloudOS.NativeShell.Toast.v4',
    'WS_EX_NOACTIVATE',
    'WS_EX_LAYERED',
    'HWND_MESSAGE',
    'kMaximumQueue',
    'MonitorFromWindow',
    'SetLayeredWindowAttributes',
    'MA_NOACTIVATE',
    'kDismissTimer',
    'kFadeTimer'
)
Forbid 'Live toast overlay' $content.Toast @(
    'SetForegroundWindow',
    'SetParent(',
    'CreateRemoteThread'
)

Require 'Control Plane health service' $content.Service @(
    'CloudOS.NativeShell.ControlPlaneService.v4',
    'HWND_MESSAGE',
    'kRefreshIntervalMs',
    'NativeSystemControlBackend::QueryAudio',
    'NativeSystemControlBackend::QueryPower',
    'NativeSystemControlBackend::QueryWifiConnection',
    'NativeSystemControlBackend::QueryDrives',
    'CriticalBattery',
    'lowest_drive_free_percent',
    'CloudOSNativeNotificationCenter::Post',
    'NativeToastOverlay::Post'
)

Require 'Appearance persistence' $content.Appearance @(
    'Software\\CloudOS\\AppearanceV4',
    'RegCreateKeyExW',
    'RegSetValueExW',
    'RegFlushKey',
    'NextPresetAccent',
    'Transparency',
    'CompactStatus'
)

Require 'Workspace Studio preserved' $content.Studio @(
    'NativeWorkspaceStudioService',
    'HWND_MESSAGE'
)
Require 'Continuity preserved' $content.Continuity @(
    'NativeSessionContinuityService',
    'HWND_MESSAGE'
)

$combined = $content.Quick + "`n" + $content.Tray + "`n" + $content.Toast + "`n" + $content.Service
Forbid 'Control Plane isolation' $combined @('SetParent(', 'WriteProcessMemory', 'CreateRemoteThread')

Write-Host 'PASS: Shell Control Plane V4 contracts passed - unified System Center + Workspace Studio + Continuity, operational Quick Settings, first-party tray, live toasts, health service and persisted appearance.'
