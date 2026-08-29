$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src'
$projectPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
$researchPath = Join-Path $repoRoot 'docs\native\research\DESKTOP_INFRASTRUCTURE_V2_RESEARCH.md'
$shellLauncherScript = Join-Path $repoRoot 'scripts\native\configure-cloudos-shell-launcher.ps1'

$paths = @{
    Project = $projectPath
    Main = Join-Path $src 'main_shell_v2.cpp'
    Desktop = Join-Path $src 'native_desktop_window_v2.cpp'
    Taskbar = Join-Path $src 'native_taskbar_appbar.cpp'
    Start = Join-Path $src 'native_start_menu_window.cpp'
    Switcher = Join-Path $src 'native_task_switcher_window.cpp'
    Quick = Join-Path $src 'native_quick_settings_window.cpp'
    Notifications = Join-Path $src 'native_notification_center.cpp'
    Monitor = Join-Path $src 'native_monitor_manager.cpp'
    Drop = Join-Path $src 'native_desktop_drop_target.cpp'
    Context = Join-Path $src 'native_desktop_context_menu.cpp'
    Wallpaper = Join-Path $src 'native_wallpaper_manager.cpp'
    Launcher = Join-Path $src 'native_app_launcher_v3.cpp'
    Browser = Join-Path $src 'native_browser_window.cpp'
    Actions = Join-Path $src 'native_shell_actions.cpp'
    Files = Join-Path $src 'native_files_window.cpp'
    ShellView = Join-Path $src 'native_shell_view_host.cpp'
    Research = $researchPath
    ShellLauncher = $shellLauncherScript
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Required CloudOS V2 file missing [$($entry.Key)]: $($entry.Value)"
    }
}

$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $text[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

function Require-Tokens([string]$Name, [string]$Content, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if (-not $Content.Contains($token)) {
            throw "$Name contract missing: $token"
        }
    }
}

function Forbid-Tokens([string]$Name, [string]$Content, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if ($Content.Contains($token)) {
            throw "$Name forbidden regression found: $token"
        }
    }
}

Require-Tokens 'Project' $text.Project @(
    'src\main_shell_v2.cpp',
    'src\native_desktop_window_v2.cpp',
    'src\native_taskbar_appbar.cpp',
    'src\native_start_menu_window.cpp',
    'src\native_task_switcher_window.cpp',
    'src\native_quick_settings_window.cpp',
    'src\native_notification_center.cpp',
    'src\native_monitor_manager.cpp',
    'src\native_desktop_drop_target.cpp',
    'src\native_desktop_context_menu.cpp',
    'src\native_wallpaper_manager.cpp',
    'src\native_app_launcher_v3.cpp',
    'src\native_browser_window.cpp',
    'src\native_shell_actions.cpp'
)
Forbid-Tokens 'Project' $text.Project @(
    '<ClCompile Include="src\main.cpp"',
    '<ClCompile Include="src\native_desktop_window.cpp"',
    '<ClCompile Include="src\native_app_launcher.cpp"',
    '<ClCompile Include="src\native_app_launcher_v2.cpp"'
)

Require-Tokens 'Main shell V2' $text.Main @(
    'NativeMonitorManager::VirtualBounds()',
    'window_manager_.SetReservedBottomPixels(0)',
    'BuildTaskbars()',
    'CloudOSTaskbarAppBar',
    'CloudOSNativeStartMenuWindow',
    'CloudOSNativeQuickSettingsWindow',
    'CloudOSNativeNotificationCenter',
    'CloudOSNativeTaskSwitcherWindow',
    'MOD_ALT | MOD_NOREPEAT',
    'VK_TAB',
    'MOD_WIN | MOD_SHIFT',
    'HotTiling, modifiers, L''T''',
    'OleInitialize(nullptr)'
)
Forbid-Tokens 'Main shell V2' $text.Main @('tiling_on_start', 'CloudOSNativeSettingsWindow::Load')

Require-Tokens 'Taskbar AppBar' $text.Taskbar @(
    'CloudOS.NativeShell.Taskbar.v2',
    'SHAppBarMessage(ABM_NEW',
    'SHAppBarMessage(ABM_QUERYPOS',
    'SHAppBarMessage(ABM_SETPOS',
    'SHAppBarMessage(ABM_REMOVE',
    'ABN_POSCHANGED',
    'CurrentWorkspaceWindows()',
    'SwitchWorkspace',
    'FocusWindow',
    'CloudOSNativeNotificationCenter::UnreadCount'
)

Require-Tokens 'Independent Start' $text.Start @(
    'CloudOS.NativeShell.Start.v2',
    'WS_POPUP',
    'WS_EX_TOOLWINDOW | WS_EX_TOPMOST',
    'NativeSearchEngine::FilterApps',
    'NM_DBLCLK',
    'NM_RETURN',
    'VK_ESCAPE',
    'Central de Comandos'
)

Require-Tokens 'DWM task switcher' $text.Switcher @(
    'DwmRegisterThumbnail',
    'DwmQueryThumbnailSourceSize',
    'DwmUpdateThumbnailProperties',
    'DwmUnregisterThumbnail',
    'DWM_TNP_RECTDESTINATION',
    'CurrentWorkspaceWindows()',
    'VK_TAB',
    'Commit()'
)

Require-Tokens 'Quick Settings' $text.Quick @(
    'MMDeviceEnumerator',
    'IAudioEndpointVolume',
    'GetDefaultAudioEndpoint',
    'GetMasterVolumeLevelScalar',
    'SetMasterVolumeLevelScalar',
    'SetMute',
    'GetSystemPowerStatus',
    'ms-settings:network-wifi',
    'ms-settings:bluetooth',
    'ms-settings:display',
    'ms-settings:sound'
)

Require-Tokens 'Notification Center' $text.Notifications @(
    'CloudOS.NativeShell.NotificationCenter.v2',
    'UnreadCount',
    'MarkAllRead',
    'g_notifications',
    '100'
)

Require-Tokens 'Multi-monitor' $text.Monitor @(
    'EnumDisplayMonitors',
    'GetMonitorInfoW',
    'SM_XVIRTUALSCREEN',
    'SM_CXVIRTUALSCREEN',
    'MonitorFromWindow',
    'MoveWindowToAdjacentMonitor'
)

Require-Tokens 'Desktop OLE drop target' $text.Drop @(
    'IDropTarget',
    'RegisterDragDrop',
    'RevokeDragDrop',
    'CF_HDROP',
    'IFileOperation',
    'CopyItem',
    'PerformOperations'
)

Require-Tokens 'Desktop V2' $text.Desktop @(
    'CloudOS.NativeShell.Desktop.v2',
    'NativeDesktopDropTarget::Register',
    'NativeWallpaperManager::Draw',
    'FOLDERID_Desktop',
    'SHGetFileInfoW',
    'ShellExecuteW',
    'NativeDesktopContextMenu::Show'
)
Forbid-Tokens 'Compiled Desktop V2' $text.Desktop @('start_menu_open_', 'start_button_rect_', 'taskbar_y')

Require-Tokens 'Desktop context menu' $text.Context @(
    'Nova pasta',
    'Novo arquivo de texto',
    'Abrir no Terminal',
    'Mudar wallpaper',
    'CreateDirectoryW',
    'CreateFileW',
    'CloudOSNativeFilesWindow::Open',
    'CloudOSNativeTerminalWindow::Open'
)

Require-Tokens 'Wallpaper persistence' $text.Wallpaper @(
    'Software\\CloudOS\\ShellV2',
    'WallpaperPath',
    'RegSetValueExW',
    'SPI_SETDESKWALLPAPER',
    'GetOpenFileNameW',
    'InterpolationModeHighQualityBicubic'
)

Forbid-Tokens 'Compiled launcher v3' $text.Launcher @('SetParent(', 'kExternalHostClass', 'CollectProcessFamily')
Require-Tokens 'Compiled launcher v3' $text.Launcher @(
    'CloudOSNativeBrowserWindow::Open',
    'CloudOSNativeCommandCenterWindow::Open',
    'StartMenuMRUTracker::Instance().RecordLaunch'
)

Require-Tokens 'Native Browser' $text.Browser @(
    'CreateCoreWebView2EnvironmentWithOptions',
    'CreateCoreWebView2Controller',
    'NavigationCompleted',
    'HistoryChanged',
    'BrowserProfile'
)

$actionPattern = '(?m)^\s*\{L"[^"]+".*ShellActionCategory::[A-Za-z]+,\s*ShellActionKind::[A-Za-z]+\},\s*$'
$actionCount = ([regex]::Matches($text.Actions, $actionPattern)).Count
if ($actionCount -lt 100) {
    throw "Shell action catalog regressed below 100 actions: $actionCount"
}

Require-Tokens 'Infrastructure research' $text.Research @(
    'SHAppBarMessage',
    'ABM_NEW',
    'DwmRegisterThumbnail',
    'RegisterDragDrop',
    'IAudioEndpointVolume',
    'GetSystemPowerStatus',
    'EnumDisplayMonitors',
    'WESL_UserSetting'
)

Require-Tokens 'Optional official Shell Launcher script' $text.ShellLauncher @(
    "root/standardcimv2/embedded",
    'WESL_UserSetting',
    'SetCustomShell',
    'SetEnabled',
    'RemoveCustomShell',
    "Enterprise|Education|IoT",
    'ShouldProcess'
)

Write-Host "PASS: CloudOS Shell V2 contracts passed — multi-HWND Desktop, AppBar taskbars, independent Start, DWM task switcher, Quick Settings, notifications, OLE desktop drop, wallpaper, multi-monitor and $actionCount shell actions."
