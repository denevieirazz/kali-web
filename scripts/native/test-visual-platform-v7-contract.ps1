$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'

$paths = @{
    Theme = Join-Path $src 'native_theme.h'
    QuickHeader = Join-Path $src 'native_quick_settings_window.h'
    FilesHeader = Join-Path $src 'native_files_window.h'
    RecoveryHeader = Join-Path $src 'native_session_recovery.h'
    Media = Join-Path $src 'native_media_control_v7.h'
    Mixer = Join-Path $src 'native_audio_mixer_v7.h'
    Bluetooth = Join-Path $src 'native_bluetooth_v7.h'
    Search = Join-Path $src 'native_windows_search_v7.h'
    ContextMenu = Join-Path $src 'native_shell_context_menu_v7.h'
    SessionEvents = Join-Path $src 'native_session_events_v7.h'
    Backend = Join-Path $src 'native_system_control_backend.cpp'
    Blueprint = Join-Path $root 'docs\native\VISUAL_PLATFORM_V7_BLUEPRINT.md'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Visual Platform V7 file missing [$($entry.Key)]: $($entry.Value)"
    }
}

$content = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

function Require([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) { throw "$Name contract missing: $token" }
    }
}

function Forbid([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if ($Text.Contains($token)) { throw "$Name forbidden regression found: $token" }
    }
}

Require 'Visual Experience V7' $content.Theme @(
    'Visual Experience V7',
    'DrawRevealHighlight',
    'PathGradientBrush',
    'CursorInControl',
    'EaseOutCubic',
    'EaseOutQuint',
    'MotionFrameMilliseconds = 8',
    'DWMSBT_TRANSIENTWINDOW',
    'DWMSBT_MAINWINDOW',
    'Specular light edge'
)
Forbid 'Visual Experience V7' $content.Theme @(
    'const int transient_backdrop = 3',
    'const int main_backdrop = 2',
    'DWMSBT_ACRYLIC'
)

Require 'GSMTC service' $content.Media @(
    'GlobalSystemMediaTransportControlsSessionManager',
    'RequestAsync().get()',
    'TryGetMediaPropertiesAsync().get()',
    'GetPlaybackInfo()',
    'TryTogglePlayPauseAsync().get()',
    'TrySkipNextAsync().get()',
    'TrySkipPreviousAsync().get()',
    'std::thread',
    'multi_threaded',
    'RefreshAsync'
)

Require 'Per-app CoreAudio mixer' $content.Mixer @(
    'IAudioSessionManager2',
    'IAudioSessionEnumerator',
    'IAudioSessionControl2',
    'ISimpleAudioVolume',
    'GetSessionEnumerator',
    'GetMasterVolume',
    'SetMasterVolume',
    'SetMute',
    'GetProcessId'
)

Require 'Modern Bluetooth provider' $content.Bluetooth @(
    'BluetoothDevice::GetDeviceSelector()',
    'BluetoothLEDevice::GetDeviceSelector()',
    'DeviceInformation::FindAllAsync',
    'PairAsync().get()',
    'UnpairAsync().get()',
    'multi_threaded'
)

Require 'Windows Search SystemIndex' $content.Search @(
    'CLSID_CSearchManager',
    'GetCatalog(L"SystemIndex"',
    'ISearchQueryHelper',
    'GenerateSQLFromUserQuery',
    'get_ConnectionString',
    'CLSID_MSDAINITIALIZE',
    'ICommandText',
    'IID_IRowset',
    'System.ItemName,System.ItemPathDisplay,System.ItemUrl',
    'maximum_results = 80u'
)

Require 'IContextMenu3 Shell bridge' $content.ContextMenu @(
    'SHBindToParent',
    'GetUIObjectOf',
    'IID_IContextMenu',
    'IContextMenu2',
    'IContextMenu3',
    'HandleMenuMsg2',
    'QueryContextMenu',
    'InvokeCommand'
)

Require 'WTS session bridge' $content.SessionEvents @(
    'WTSRegisterSessionNotification',
    'WTSUnRegisterSessionNotification',
    'WM_WTSSESSION_CHANGE',
    'WTS_SESSION_LOCK',
    'WTS_SESSION_UNLOCK',
    'ShouldCheckpoint',
    'ShouldRefresh'
)

Require 'Native platform headers compiled by shell' $content.QuickHeader @(
    '#include "native_audio_mixer_v7.h"',
    '#include "native_bluetooth_v7.h"',
    '#include "native_media_control_v7.h"',
    '#include "native_windows_search_v7.h"'
)
Require 'Files context menu bridge compiled' $content.FilesHeader @(
    '#include "native_shell_context_menu_v7.h"'
)
Require 'Session events bridge compiled' $content.RecoveryHeader @(
    '#include "native_session_events_v7.h"'
)

Require 'Native WLAN already first-party' $content.Backend @(
    'WlanOpenHandle',
    'WlanEnumInterfaces',
    'WlanGetAvailableNetworkList',
    'WlanConnect',
    'WlanDisconnect'
)

Require 'Blueprint accuracy' $content.Blueprint @(
    'DWMSBT_TRANSIENTWINDOW',
    'does **not** contain `DWMSBT_ACRYLIC`',
    'IAudioSessionManager2',
    'SystemIndex',
    'WTSRegisterSessionNotification',
    'Restart Manager is **not** a replacement',
    'No blocking GSMTC calls on the UI thread',
    'Floating Taskbar/Dock V7'
)

Write-Host 'PASS: Visual Platform V7 contracts passed - Fluent reveal/materials, GSMTC, CoreAudio mixer, Bluetooth, SystemIndex, IContextMenu3, WTS and native WLAN foundations are protected.'
