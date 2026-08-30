$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src'
$projectPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
$researchV2Path = Join-Path $repoRoot 'docs\native\research\DESKTOP_INFRASTRUCTURE_V2_RESEARCH.md'
$researchV3Path = Join-Path $repoRoot 'docs\native\research\SHELL_V3_PRODUCTIVITY_RECOVERY_RESEARCH.md'
$featuresV3Path = Join-Path $repoRoot 'docs\native\SHELL_V3_FEATURES.md'
$shellLauncherScript = Join-Path $repoRoot 'scripts\native\configure-cloudos-shell-launcher.ps1'

$paths = @{
    Project = $projectPath
    Main = Join-Path $src 'main_shell_v2.cpp'
    Desktop = Join-Path $src 'native_desktop_window_v2.cpp'
    Taskbar = Join-Path $src 'native_taskbar_appbar.cpp'
    HoverPreview = Join-Path $src 'native_taskbar_hover_preview.cpp'
    Start = Join-Path $src 'native_start_menu_window.cpp'
    StartIndex = Join-Path $src 'native_start_index.cpp'
    Switcher = Join-Path $src 'native_task_switcher_window.cpp'
    Quick = Join-Path $src 'native_quick_settings_window.cpp'
    Notifications = Join-Path $src 'native_notification_center.cpp'
    Monitor = Join-Path $src 'native_monitor_manager.cpp'
    Snap = Join-Path $src 'native_snap_assist.cpp'
    Recovery = Join-Path $src 'native_session_recovery.cpp'
    Watchdog = Join-Path $src 'native_watchdog.cpp'
    WindowRecovery = Join-Path $src 'native_window_manager_recovery.cpp'
    FileOps = Join-Path $src 'native_file_operations_window.cpp'
    Drop = Join-Path $src 'native_desktop_drop_target.cpp'
    Context = Join-Path $src 'native_desktop_context_menu.cpp'
    Wallpaper = Join-Path $src 'native_wallpaper_manager.cpp'
    Launcher = Join-Path $src 'native_app_launcher_v3.cpp'
    Browser = Join-Path $src 'native_browser_window.cpp'
    Actions = Join-Path $src 'native_shell_actions.cpp'
    Files = Join-Path $src 'native_files_window.cpp'
    ShellView = Join-Path $src 'native_shell_view_host.cpp'
    ResearchV2 = $researchV2Path
    ResearchV3 = $researchV3Path
    FeaturesV3 = $featuresV3Path
    ShellLauncher = $shellLauncherScript
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Required CloudOS Shell V3 file missing [$($entry.Key)]: $($entry.Value)"
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

# ---------------------------------------------------------------------------
# Build graph: V3 sources must actually compile, old monolithic/legacy launchers
# must remain outside of the graph.
# ---------------------------------------------------------------------------
Require-Tokens 'Project' $text.Project @(
    'src\main_shell_v2.cpp',
    'src\native_desktop_window_v2.cpp',
    'src\native_taskbar_appbar.cpp',
    'src\native_taskbar_hover_preview.cpp',
    'src\native_start_menu_window.cpp',
    'src\native_start_index.cpp',
    'src\native_task_switcher_window.cpp',
    'src\native_quick_settings_window.cpp',
    'src\native_notification_center.cpp',
    'src\native_monitor_manager.cpp',
    'src\native_snap_assist.cpp',
    'src\native_session_recovery.cpp',
    'src\native_watchdog.cpp',
    'src\native_window_manager_recovery.cpp',
    'src\native_file_operations_window.cpp',
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

# ---------------------------------------------------------------------------
# Main session shell integration.
# ---------------------------------------------------------------------------
Require-Tokens 'Main Shell V3 integration' $text.Main @(
    'NativeMonitorManager::VirtualBounds()',
    'window_manager_.SetReservedBottomPixels(0)',
    'BuildTaskbars()',
    'CloudOSTaskbarAppBar',
    'CloudOSNativeStartMenuWindow',
    'CloudOSNativeQuickSettingsWindow',
    'CloudOSNativeNotificationCenter',
    'CloudOSNativeTaskSwitcherWindow',
    'NativeTaskbarHoverPreview::Attach',
    'snap_assist_.Start',
    'session_recovery_.BeginSession',
    'session_recovery_.Restore',
    'session_recovery_.Tick',
    'session_recovery_.MarkCleanExit',
    'WM_QUERYENDSESSION',
    'WM_ENDSESSION',
    'PBT_APMSUSPEND',
    'NativeWatchdog::IsWatchdogInvocation',
    'NativeWatchdog::RunWatchdogInvocation',
    'NativeWatchdog::AcquireSessionMutex',
    'NativeWatchdog::StartForCurrentProcess',
    'MOD_ALT | MOD_NOREPEAT',
    'VK_TAB',
    'MOD_WIN | MOD_SHIFT',
    'HotTiling, modifiers, L''T''',
    'OleInitialize(nullptr)'
)
Forbid-Tokens 'Main Shell V3 startup' $text.Main @(
    'tiling_on_start',
    'CloudOSNativeSettingsWindow::Load'
)

# Watchdog must begin only after UI initialization succeeds, not before it.
$initializePosition = $text.Main.IndexOf('if (!application.Initialize())')
$watchdogStartPosition = $text.Main.IndexOf('NativeWatchdog::StartForCurrentProcess')
if ($initializePosition -lt 0 -or $watchdogStartPosition -lt 0 -or $watchdogStartPosition -lt $initializePosition) {
    throw 'Watchdog must start only after CloudOSApplication::Initialize() has succeeded.'
}

# ---------------------------------------------------------------------------
# V2 shell primitives stay real.
# ---------------------------------------------------------------------------
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

Require-Tokens 'Independent Start V3' $text.Start @(
    'CloudOS.NativeShell.Start.v3',
    'WS_POPUP',
    'WS_EX_TOOLWINDOW | WS_EX_TOPMOST',
    'NativeSearchEngine::FilterApps',
    'NativeStartIndex::Instance().Query',
    'NativeStartIndex::Instance().Launch',
    'NativeStartIndex::Instance().RefreshAsync',
    'Reindexar',
    'NM_DBLCLK',
    'NM_RETURN',
    'VK_ESCAPE',
    'Central de Comandos'
)

Require-Tokens 'Start background index' $text.StartIndex @(
    'FOLDERID_Programs',
    'FOLDERID_CommonPrograms',
    'shell:AppsFolder',
    'BHID_EnumItems',
    'IEnumShellItems',
    'SIGDN_NORMALDISPLAY',
    'SIGDN_DESKTOPABSOLUTEPARSING',
    'recursive_directory_iterator',
    'std::thread',
    'CoInitializeEx',
    'NativeStartIndex::Query',
    'MatchScore',
    'ShellExecuteW'
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

# ---------------------------------------------------------------------------
# Snap Assist V3.
# ---------------------------------------------------------------------------
Require-Tokens 'Snap Assist' $text.Snap @(
    'SetWinEventHook',
    'EVENT_SYSTEM_MOVESIZESTART',
    'EVENT_SYSTEM_MOVESIZEEND',
    'EVENT_OBJECT_LOCATIONCHANGE',
    'WINEVENT_OUTOFCONTEXT',
    'CloudOS.NativeShell.SnapAssistOverlay.v1',
    'WS_EX_NOACTIVATE',
    'WS_EX_TRANSPARENT',
    'TopLeftQuarter',
    'BottomRightQuarter',
    'CenterThird',
    'LeftTwoThirds',
    'RightTwoThirds',
    'GetKeyState(VK_CONTROL)',
    'GetKeyState(VK_SHIFT)',
    'window_manager_->SetWindowFloating',
    'SetWindowPos'
)
Forbid-Tokens 'Snap Assist injection policy' $text.Snap @(
    'SetWindowsHookEx',
    'WriteProcessMemory',
    'CreateRemoteThread'
)

# ---------------------------------------------------------------------------
# Taskbar hover preview V3.
# ---------------------------------------------------------------------------
Require-Tokens 'Taskbar hover preview' $text.HoverPreview @(
    'CloudOS.NativeShell.TaskPreview.v1',
    'SetWindowSubclass',
    'DwmRegisterThumbnail',
    'DwmQueryThumbnailSourceSize',
    'DwmUpdateThumbnailProperties',
    'DwmUnregisterThumbnail',
    'DWM_TNP_RECTDESTINATION',
    'CurrentWorkspaceWindows()',
    'WM_MOUSELEAVE',
    'WM_CLOSE',
    'FocusWindow'
)

# ---------------------------------------------------------------------------
# Desktop and OLE.
# ---------------------------------------------------------------------------
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
Forbid-Tokens 'Compiled Desktop V2' $text.Desktop @(
    'start_menu_open_',
    'start_button_rect_',
    'taskbar_y'
)

Require-Tokens 'Desktop context menu' $text.Context @(
    'Nova pasta',
    'Novo arquivo de texto',
    'Abrir no Terminal',
    'Mudar wallpaper',
    'Operacoes de arquivos / ZIP',
    'CloudOSNativeFileOperationsWindow::Open',
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

# ---------------------------------------------------------------------------
# Advanced file operations / ZIP.
# ---------------------------------------------------------------------------
Require-Tokens 'Advanced file operations' $text.FileOps @(
    'CloudOS.Native.FileOperations.v1',
    'IFileOperationProgressSink',
    'CLSID_FileOperation',
    'IFileOperation',
    'CopyItem',
    'MoveItem',
    'PerformOperations',
    'GetAnyOperationsAborted',
    'FOFX_ADDUNDORECORD',
    'operation->Advise',
    'operation->Unadvise',
    'UpdateProgress',
    'ERROR_CANCELLED',
    'PBM_SETPOS',
    'PBM_SETMARQUEE',
    'IFileOpenDialog',
    'IFileSaveDialog',
    'tar.exe -a -c -f',
    'tar.exe -xf',
    'CREATE_NO_WINDOW',
    'TerminateProcess'
)

# ---------------------------------------------------------------------------
# Recovery and watchdog.
# ---------------------------------------------------------------------------
Require-Tokens 'Session recovery' $text.Recovery @(
    'session_v3.dat',
    'session_v3.unclean',
    'FOLDERID_LocalAppData',
    'MOVEFILE_REPLACE_EXISTING',
    'MOVEFILE_WRITE_THROUGH',
    'AllManagedWindows',
    'RestoreWindowState',
    'NativeAppLauncher::LaunchById',
    'PreviousSessionUnclean',
    'CloudOS.Native.FileOperations.v1',
    'transient',
    'GetWindowPlacement'
)

Require-Tokens 'Window-manager recovery primitives' $text.WindowRecovery @(
    'AllManagedWindows',
    'WorkspaceFor',
    'SetWindowFloating',
    'RestoreWindowState',
    'MarkWorkspaceHidden',
    'SW_MAXIMIZE',
    'SW_MINIMIZE'
)

Require-Tokens 'Watchdog' $text.Watchdog @(
    'CloudOS.NativeShell.Session.v1',
    '--watchdog',
    'OpenProcess',
    'SYNCHRONIZE',
    'WaitForSingleObject',
    'CreateProcessW',
    'AcquireSessionMutex',
    'StartForCurrentProcess',
    'PROCESS_QUERY_LIMITED_INFORMATION',
    'SurfaceExistingShell'
)

# ---------------------------------------------------------------------------
# Browser, launcher and shell actions stay truthful.
# ---------------------------------------------------------------------------
Forbid-Tokens 'Compiled launcher v3' $text.Launcher @(
    'SetParent(',
    'kExternalHostClass',
    'CollectProcessFamily'
)
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

# ---------------------------------------------------------------------------
# Research records and supported Shell Launcher path.
# ---------------------------------------------------------------------------
Require-Tokens 'Infrastructure V2 research' $text.ResearchV2 @(
    'SHAppBarMessage',
    'ABM_NEW',
    'DwmRegisterThumbnail',
    'RegisterDragDrop',
    'IAudioEndpointVolume',
    'GetSystemPowerStatus',
    'EnumDisplayMonitors',
    'WESL_UserSetting'
)

Require-Tokens 'Shell V3 research' $text.ResearchV3 @(
    'SetWinEventHook',
    'WINEVENT_OUTOFCONTEXT',
    'DwmRegisterThumbnail',
    'FOLDERID_Programs',
    'FOLDERID_CommonPrograms',
    'shell:AppsFolder',
    'IFileOperationProgressSink',
    'tar.exe -a -c -f',
    'session_v3.dat',
    'CreateProcessW',
    'WaitForSingleObject',
    'WM_QUERYENDSESSION'
)

Require-Tokens 'Shell V3 feature matrix' $text.FeaturesV3 @(
    'Snap Assist',
    'Hover previews da taskbar',
    'Start Indexer',
    'Operações de arquivos',
    'Session Recovery',
    'Watchdog',
    '150.'
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

Write-Host "PASS: CloudOS Shell V3 contracts passed - AppBars, Start indexer, Snap Assist, DWM taskbar previews, advanced File Operations/ZIP, session recovery, watchdog, multi-monitor and $actionCount shell actions."
