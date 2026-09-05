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

# 1. Display Service V25
Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\display_service_v25.h' -Needles @(
    'struct DisplayModeInfoV25',
    'struct MonitorInfoV25',
    'class DisplayServiceV25',
    'ListMonitors()',
    'ListSupportedModes(',
    'SetDisplayMode(',
    'RestoreBaseline('
) -Description 'Display Service V25 Header'

Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\display_service_v25.cpp' -Needles @(
    'EnumDisplayMonitors',
    'EnumDisplaySettingsW',
    'ChangeDisplaySettingsExW',
    'CDS_TEST',
    'display.changed',
    'GetDpiForMonitor'
) -Description 'Display Service V25 Implementation'

# 2. Audio Service V25
Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\audio_service_v25.h' -Needles @(
    'struct AudioEndpointInfoV25',
    'struct AudioStateV25',
    'class AudioServiceV25',
    'GetAudioState()',
    'SetVolume(',
    'SetMute('
) -Description 'Audio Service V25 Header'

Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\audio_service_v25.cpp' -Needles @(
    'IMMDeviceEnumerator',
    'IAudioEndpointVolume',
    'GetMasterVolumeLevelScalar',
    'SetMasterVolumeLevelScalar',
    'audio.changed'
) -Description 'Audio Service V25 Implementation'

# 3. System Settings Service V25
Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\system_settings_service_v25.h' -Needles @(
    'struct PowerStatusV25',
    'struct NetworkInterfaceV25',
    'struct WifiNetworkV25',
    'struct BluetoothStatusV25',
    'struct StorageDriveV25',
    'struct PersonalizationSettingsV25',
    'struct DateTimeLocaleV25',
    'class SystemSettingsServiceV25',
    'GetPowerStatus()',
    'GetNetworkInterfaces()',
    'GetWifiNetworks()',
    'GetBluetoothStatus()',
    'GetStorageDrives()',
    'GetPersonalization()',
    'SetPersonalization('
) -Description 'System Settings Service V25 Header'

Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\system_settings_service_v25.cpp' -Needles @(
    'GetSystemPowerStatus',
    'GetAdaptersAddresses',
    'WlanGetAvailableNetworkList',
    'BluetoothFindFirstRadio',
    'GetLogicalDriveStringsW',
    'GetDiskFreeSpaceExW',
    'MoveFileExW',
    'GetDynamicTimeZoneInformation'
) -Description 'System Settings Service V25 Implementation'

# 4. Broker Server V21 RPC Dispatches
Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\broker_server_v21.cpp' -Needles @(
    'if (method == "display.listMonitors")',
    'if (method == "display.listSupportedModes")',
    'if (method == "display.setMode")',
    'if (method == "display.restore")',
    'if (method == "audio.getState")',
    'if (method == "audio.setVolume")',
    'if (method == "audio.setMute")',
    'if (method == "power.getStatus")',
    'if (method == "network.getInterfaces")',
    'if (method == "network.getWifi")',
    'if (method == "bluetooth.getStatus")',
    'if (method == "storage.getDrives")',
    'if (method == "personalization.get")',
    'if (method == "personalization.set")',
    'if (method == "datetime.get")',
    'if (method == "datetime.setTime")',
    'if (method == "performance.getProfile")',
    'if (method == "performance.setProfile")',
    'if (method == "wsl.getDistros")',
    'if (method == "quicksettings.getState")'
) -Description 'Broker Server V21 RPC Endpoints'

# 5. Inviolable Security & Architectural Boundaries
$prohibitedPatterns = @(
    'Winlogon',
    'explorer.exe /f',
    'taskkill /f /im explorer.exe',
    'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon',
    'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
)
foreach ($rel in @(
    'desktop\CloudOS.SystemBroker\src\system_settings_service_v25.cpp',
    'desktop\CloudOS.SystemBroker\src\display_service_v25.cpp',
    'desktop\CloudOS.SystemBroker\src\audio_service_v25.cpp'
)) {
    $code = Get-Content -LiteralPath (Join-Path $root $rel) -Raw
    foreach ($bad in $prohibitedPatterns) {
        if ($code.Contains($bad)) {
            throw "Security violation in ${rel}: contains prohibited pattern '$bad'"
        }
    }
}

Write-Host '[PASS] System Settings & Controls V25: Display, Audio, Power, Network, Wifi, Bluetooth, Storage, Personalization, DateTime and QuickSettings RPC contracts verified with strict security boundaries.'
