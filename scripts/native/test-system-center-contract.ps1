$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'

$paths = @{
    BackendHeader = Join-Path $src 'native_system_control_backend.h'
    Backend = Join-Path $src 'native_system_control_backend.cpp'
    WindowHeader = Join-Path $src 'native_system_control_window.h'
    Window = Join-Path $src 'native_system_control_window.cpp'
    Launcher = Join-Path $src 'native_app_launcher_v4.cpp'
    Theme = Join-Path $src 'native_theme.h'
    Search = Join-Path $src 'native_search_engine.cpp'
    Project = Join-Path $root 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "System Center contract file missing [$($entry.Key)]: $($entry.Value)"
    }
}

$content = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

function Require([string]$name, [string]$text, [string[]]$tokens) {
    foreach ($token in $tokens) {
        if (-not $text.Contains($token)) {
            throw "$name contract missing: $token"
        }
    }
}

function Forbid([string]$name, [string]$text, [string[]]$tokens) {
    foreach ($token in $tokens) {
        if ($text.Contains($token)) {
            throw "$name forbidden regression found: $token"
        }
    }
}

Require 'Backend API surface' $content.BackendHeader @(
    'NativeWifiNetwork',
    'NativeNetworkAdapter',
    'NativeDriveInfo',
    'NativeProcessInfo',
    'NativeServiceInfo',
    'NativeAudioState',
    'NativeBrightnessState',
    'NativePowerState',
    'NativeSystemSummary',
    'ScanWifi()',
    'ConnectKnownWifi',
    'DisconnectWifi',
    'QueryAudio()',
    'SetMasterVolume',
    'SetMasterMute',
    'QueryBrightness()',
    'SetBrightness',
    'SetBalancedPowerPlan',
    'SetPowerSaverPlan',
    'SetHighPerformancePlan',
    'QueryAdapters()',
    'QueryDrives()',
    'QueryProcesses',
    'QueryCoreServices()'
)

Require 'Native Wi-Fi' $content.Backend @(
    '#include <wlanapi.h>',
    'WlanOpenHandle',
    'WlanEnumInterfaces',
    'WlanQueryInterface',
    'wlan_intf_opcode_current_connection',
    'WlanGetAvailableNetworkList',
    'WlanConnect',
    'wlan_connection_mode_profile',
    'WlanDisconnect',
    'profile_name.empty()'
)

Require 'Core Audio' $content.Backend @(
    '#include <endpointvolume.h>',
    'IMMDeviceEnumerator',
    'GetDefaultAudioEndpoint',
    'IAudioEndpointVolume',
    'GetMasterVolumeLevelScalar',
    'SetMasterVolumeLevelScalar',
    'GetMute',
    'SetMute',
    'PKEY_Device_FriendlyName'
)

Require 'Brightness stack' $content.Backend @(
    'GetNumberOfPhysicalMonitorsFromHMONITOR',
    'GetPhysicalMonitorsFromHMONITOR',
    'GetMonitorBrightness',
    'SetMonitorBrightness',
    'DestroyPhysicalMonitors',
    'ROOT\\WMI',
    'WmiMonitorBrightness',
    'WmiMonitorBrightnessMethods',
    'WmiSetBrightness',
    'DDC/CI',
    'state.source = L"WMI"'
)

Require 'Power control' $content.Backend @(
    'GetSystemPowerStatus',
    'PowerGetActiveScheme',
    'PowerSetActiveScheme',
    'GUID_TYPICAL_POWER_SAVINGS',
    'GUID_MAX_POWER_SAVINGS',
    'GUID_MIN_POWER_SAVINGS'
)

Require 'Network/storage/process/service telemetry' $content.Backend @(
    'GetAdaptersAddresses',
    'InetNtopW',
    'GetLogicalDriveStringsW',
    'GetVolumeInformationW',
    'GetDiskFreeSpaceExW',
    'CreateToolhelp32Snapshot',
    'Process32FirstW',
    'GetProcessMemoryInfo',
    'OpenSCManagerW',
    'OpenServiceW',
    'QueryServiceStatusEx'
)

Require 'System Center surface' $content.WindowHeader @(
    'CloudOSNativeSystemControlWindow',
    'enum class Page',
    'Overview = 0',
    'Wifi,',
    'Display,',
    'Audio,',
    'Power,',
    'Network,',
    'Storage,',
    'Processes,'
)
Require 'System Center implementation' $content.Window @(
    'CloudOS.Native.SystemControl.v1',
    'Central do Sistema - CloudOS',
    'Visao Geral',
    'Wi-Fi',
    'Armazenamento',
    'Processos',
    'Page::Overview',
    'Page::Wifi',
    'Page::Display',
    'Page::Audio',
    'Page::Power',
    'Page::Network',
    'Page::Storage',
    'Page::Processes',
    'RefreshOverview',
    'RefreshWifi',
    'RefreshDisplay',
    'RefreshAudio',
    'RefreshPower',
    'RefreshNetwork',
    'RefreshStorage',
    'RefreshProcesses',
    'ConnectSelectedWifi',
    'DisconnectSelectedWifi',
    'SetMasterVolume',
    'SetMasterMute',
    'SetBrightness',
    'SetBalancedPowerPlan',
    'SetPowerSaverPlan',
    'SetHighPerformancePlan',
    'TerminateProcess',
    'MB_DEFBUTTON2',
    'ApplyWebWindowMaterial',
    'PaintOwnerDrawButton',
    'HandleListViewCustomDraw'
)
Forbid 'System Center native-only UI' $content.Window @(
    'WebView2',
    '<html',
    'React',
    'SetParent('
)

Require 'Catalog + launcher' ($content.Theme + "`n" + $content.Launcher) @(
    'std::array<AppItem, 23>',
    '{L"systemcenter", L"Central do Sistema"',
    '#include "native_system_control_window.h"',
    'return L"systemcenter"',
    'CloudOSNativeSystemControlWindow::Open',
    'kSystemCenter = 1143',
    'Central do Sistema  ·  hardware e rede'
)
Require 'Search discovery' $content.Search @(
    'L"hardware"',
    'L"central do sistema"',
    'L"system center"',
    'L"wifi"',
    'L"brilho"',
    'L"volume"',
    'L"bateria"',
    'return id == L"systemcenter"'
)

Require 'MSVC graph and libraries' $content.Project @(
    'src\native_app_launcher_v4.cpp',
    'src\native_system_control_backend.h',
    'src\native_system_control_backend.cpp',
    'src\native_system_control_window.h',
    'src\native_system_control_window.cpp',
    'dxva2.lib',
    'iphlpapi.lib',
    'powrprof.lib',
    'psapi.lib',
    'propsys.lib',
    'wlanapi.lib',
    'wbemuuid.lib',
    'ws2_32.lib'
)
Forbid 'MSVC authoritative launcher' $content.Project @(
    '<ClCompile Include="src\native_app_launcher_v3.cpp"'
)

Write-Host 'PASS: CloudOS System Center contracts passed - native Wi-Fi, audio, brightness DDC/WMI, power plans, network, storage, processes, services and Launcher V4 are protected.'
