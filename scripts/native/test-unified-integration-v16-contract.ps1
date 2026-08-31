[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$src = Join-Path $Root 'desktop\CloudOS.NativeShell\src'
$paths = @{
    IntegrationHeader = Join-Path $src 'native_integration_v16.h'
    Integration = Join-Path $src 'native_integration_v16.cpp'
    Launchers = Join-Path $src 'native_integration_v16_launchers.h'
    PickerHeader = Join-Path $src 'native_folder_picker_v16.h'
    Picker = Join-Path $src 'native_folder_picker_v16.cpp'
    BrowserHeader = Join-Path $src 'native_browser_window.h'
    Browser = Join-Path $src 'native_browser_window.cpp'
    AppsHeader = Join-Path $src 'native_apps_window.h'
    Apps = Join-Path $src 'native_apps_window.cpp'
    Desktop = Join-Path $src 'native_desktop_model_v12.h'
    Files = Join-Path $src 'native_files_window_v5.cpp'
    Project = Join-Path $Root 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
    Runtime = Join-Path $Root 'desktop\CloudOS.NativeRuntime\include\cloudos_native_runtime.h'
    Document = Join-Path $Root 'docs\native\UNIFIED_INTEGRATION_V16.md'
    CodeMap = Join-Path $Root 'docs\native\CODEMAP.md'
    Agents = Join-Path $Root 'AGENTS.md'
    Suite = Join-Path $PSScriptRoot 'test-native-contract-suite.ps1'
    Smoke = Join-Path $PSScriptRoot 'run-native-integration-smoke-v16.ps1'
    Workflow = Join-Path $Root '.github\workflows\cloudos-native-full-system.yml'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Unified Integration V16 file missing [$($entry.Key)]: $($entry.Value)"
    }
}

$content = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

function Require {
    param([string]$Name, [string]$Text, [string[]]$Tokens)
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) { throw "$Name contract missing: $token" }
    }
}

function Forbid {
    param([string]$Name, [string]$Text, [string[]]$Tokens)
    foreach ($token in $Tokens) {
        if ($Text.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "$Name forbidden regression found: $token"
        }
    }
}

Require 'V16 compiled graph' $content.Project @(
    'src\native_integration_v16.h',
    'src\native_integration_v16.cpp',
    'src\native_folder_picker_v16.h',
    'src\native_folder_picker_v16.cpp'
)

Require 'WebView2 CloudOS download routing' ($content.BrowserHeader + "`n" + $content.Browser) @(
    'add_DownloadStarting',
    'remove_DownloadStarting',
    'ICoreWebView2DownloadStartingEventHandler',
    'get_ResultFilePath',
    'put_ResultFilePath',
    'put_Handled(TRUE)',
    'put_Cancel(TRUE)',
    'CloudOSNativeFolderPickerV16::Pick',
    'NativeIntegrationV16::DownloadsFolder',
    'UniqueDownloadPath'
)

Require 'First-party folder picker' ($content.PickerHeader + "`n" + $content.Picker) @(
    'CloudOS.NativeShell.FolderPicker.v16',
    'NativeIntegrationV16::DownloadsFolder()',
    'NativeIntegrationV16::DesktopFolder()',
    'NativeIntegrationV16::DocumentsFolder()',
    'NativeIntegrationV16::WslRoot()',
    'WC_LISTVIEWW',
    'Selecionar esta pasta',
    'FindFirstFileExW'
)
Forbid 'V16 folder picker stays first-party' $content.Picker @(
    'IFileDialog',
    'SHBrowseForFolder',
    'explorer.exe'
)

Require 'Unified Windows integration boundary' ($content.IntegrationHeader + "`n" + $content.Integration) @(
    'UnifiedAppPlatformV16',
    'EnumerateWindowsInstalledApps',
    'SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall',
    'HKEY_CURRENT_USER',
    'HKEY_LOCAL_MACHINE',
    'KEY_WOW64_64KEY',
    'KEY_WOW64_32KEY',
    'DisplayName',
    'UninstallString',
    'QuietUninstallString',
    'winget.exe',
    ' install --name ',
    ' uninstall --name ',
    '--exact'
)
Forbid 'V16 Windows inventory must remain read-only' $content.Integration @(
    'RegSetValue',
    'RegCreateKey',
    'RegDeleteKey',
    'RegDeleteValue',
    'KEY_WRITE',
    'KEY_SET_VALUE',
    'UserChoice',
    'SetUserFTA',
    'CreateServiceW'
)

Require 'Unified Linux WSLg integration boundary' ($content.IntegrationHeader + "`n" + $content.Integration) @(
    'EnumerateWslDistributions',
    ' --list --quiet',
    '\\\\wsl.localhost',
    '\\usr\\share\\applications',
    '.desktop',
    'X-Flatpak',
    'X-SnapInstanceName',
    'gtk-launch',
    'dpkg-query -S',
    'flatpak uninstall',
    'sudo snap remove',
    'sudo apt remove',
    'sudo apt install',
    'SafeLinuxPackageToken'
)

Require 'Shared Linux launcher adapter' ($content.IntegrationHeader + "`n" + $content.Launchers) @(
    'EnsureLinuxLauncherShortcut',
    'LinuxApplicationsDirectory',
    'IntegrationV16',
    'LinuxShortcuts',
    'IShellLinkW',
    'IPersistFile',
    'gtk-launch'
)

Require 'Unified Apps surface' ($content.AppsHeader + "`n" + $content.Apps) @(
    'InstalledWindows',
    'LinuxGui',
    'Aplicativos - Windows + Linux - CloudOS',
    'InstallFromSearch',
    'UninstallSelection',
    'RefreshCatalog',
    'NativeIntegrationV16::EnumerateWindowsInstalledApps',
    'NativeIntegrationV16::EnumerateLinuxGuiApps',
    'NativeIntegrationV16::BuildWingetInstallCommand',
    'NativeIntegrationV16::BuildLinuxInstallCommand',
    'NativeIntegrationV16::ResolveLinuxRemovalCommand',
    'CloudOSNativeTerminalWindow::Open',
    'MB_YESNO'
)

Require 'Desktop integration notifications' $content.Desktop @(
    'FOLDERID_Desktop',
    'NativeIntegrationV16::PublicDesktopFolder()',
    'FOLDERID_Programs',
    'FOLDERID_CommonPrograms',
    'FindFirstChangeNotificationW',
    'FindNextChangeNotification',
    'NativeStartIndex::Instance().RefreshAsync()',
    'NativeIntegrationV16::EnumerateLinuxGuiApps()',
    'NativeIntegrationV16::EnsureLinuxLauncherShortcut(app)',
    'NativeIntegrationV16::LinuxApplicationsDirectory(distro)'
)
Forbid 'Desktop integration remains event-driven' $content.Desktop @(
    'SetTimer(',
    'Sleep(1000)',
    'Sleep(2000)'
)

Require 'Files exposes Linux namespace' $content.Files @(
    'FOLDERID_Downloads',
    'L"WSL / Linux"',
    'wsl.localhost'
)

Require 'Existing low-level WSL runtime is preserved' $content.Runtime @(
    'cloudos_native_wsl_is_registered',
    'cloudos_native_wsl_get_configuration',
    'cloudos_native_wsl_launch'
)

Require 'V16 documentation' $content.Document @(
    'DownloadStarting',
    'WinGet',
    'WSLg',
    '\\wsl.localhost',
    'default apps',
    'PackageDeploymentManager',
    'hosted CI',
    'não altera Winlogon'
)
Require 'V16 code map' $content.CodeMap @('native_integration_v16.*', 'native_folder_picker_v16.*', 'test-unified-integration-v16-contract.ps1')
Require 'V16 agent boundary' $content.Agents @('native_integration_v16.*', 'default apps/file associations', 'WinGet')

Require 'Non-mutating V16 smoke' $content.Smoke @(
    "test = 'CloudOS Unified Windows Linux Integration V16'",
    'mutating_package_operation_executed = $false',
    'production_winlogon_unchanged',
    'No package was installed, upgraded or removed.'
)

Require 'Central contract suite contains V16' $content.Suite @('test-unified-integration-v16-contract.ps1')
Require 'Full-System CI protects V16' $content.Workflow @(
    'Contract Unified Integration V16',
    'test-unified-integration-v16-contract.ps1',
    'Smoke Unified Integration V16',
    'run-native-integration-smoke-v16.ps1',
    'integration-v16-smoke.json'
)

Write-Host 'PASS: Unified Integration V16 contracts passed - first-party download picker, read-only Windows inventory, explicit WinGet/WSL package flows, shared WSLg launcher adaptation and event-driven Desktop/Start integration are protected.'
