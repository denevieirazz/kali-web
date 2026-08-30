$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src'

$paths = @{
    Project = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
    Main = Join-Path $src 'main_shell_v2.cpp'
    Desktop = Join-Path $src 'native_desktop_window_v2.cpp'
    Taskbar = Join-Path $src 'native_taskbar_appbar.cpp'
    HoverPreview = Join-Path $src 'native_taskbar_hover_preview.cpp'
    Start = Join-Path $src 'native_start_menu_window.cpp'
    StartIndex = Join-Path $src 'native_start_index.cpp'
    ShellPins = Join-Path $src 'native_shell_pins.cpp'
    ShellPinsHeader = Join-Path $src 'native_shell_pins.h'
    Theme = Join-Path $src 'native_theme.h'
    Switcher = Join-Path $src 'native_task_switcher_window.cpp'
    Quick = Join-Path $src 'native_quick_settings_window.cpp'
    Notifications = Join-Path $src 'native_notification_center.cpp'
    CommandCenter = Join-Path $src 'native_command_center_window.cpp'
    Calculator = Join-Path $src 'native_calculator_window.cpp'
    Notepad = Join-Path $src 'native_notepad_window.cpp'
    Settings = Join-Path $src 'native_settings_window.cpp'
    SystemMonitor = Join-Path $src 'native_system_monitor_window.cpp'
    FilesStyleHeader = Join-Path $src 'native_files_style.h'
    FilesStyle = Join-Path $src 'native_files_style.cpp'
    Monitor = Join-Path $src 'native_monitor_manager.cpp'
    Snap = Join-Path $src 'native_snap_assist.cpp'
    Recovery = Join-Path $src 'native_session_recovery.cpp'
    RecoveryHeader = Join-Path $src 'native_session_recovery.h'
    Watchdog = Join-Path $src 'native_watchdog.cpp'
    WindowRecovery = Join-Path $src 'native_window_manager_recovery.cpp'
    FileOps = Join-Path $src 'native_file_operations_window.cpp'
    Drop = Join-Path $src 'native_desktop_drop_target.cpp'
    Context = Join-Path $src 'native_desktop_context_menu.cpp'
    Wallpaper = Join-Path $src 'native_wallpaper_manager.cpp'
    Launcher = Join-Path $src 'native_app_launcher_v3.cpp'
    Browser = Join-Path $src 'native_browser_window.cpp'
    Actions = Join-Path $src 'native_shell_actions.cpp'
    ResearchV2 = Join-Path $repoRoot 'docs\native\research\DESKTOP_INFRASTRUCTURE_V2_RESEARCH.md'
    ResearchV3 = Join-Path $repoRoot 'docs\native\research\SHELL_V3_PRODUCTIVITY_RECOVERY_RESEARCH.md'
    FeaturesV3 = Join-Path $repoRoot 'docs\native\SHELL_V3_FEATURES.md'
    ShellLauncher = Join-Path $repoRoot 'scripts\native\configure-cloudos-shell-launcher.ps1'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Required CloudOS shell file missing [$($entry.Key)]: $($entry.Value)"
    }
}

$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $text[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}
$text.Recovery = $text.Recovery + "`n" + $text.RecoveryHeader
$text.ShellPins = $text.ShellPinsHeader + "`n" + $text.ShellPins

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

# Build graph: V4 Start/taskbar additions must be real compiled C++.
Require-Tokens 'Project' $text.Project @(
    'src\main_shell_v2.cpp',
    'src\native_desktop_window_v2.cpp',
    'src\native_taskbar_appbar.cpp',
    'src\native_taskbar_hover_preview.cpp',
    'src\native_start_menu_window.cpp',
    'src\native_start_index.cpp',
    'src\native_shell_pins.cpp',
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
    'src\native_wallpaper_manager.cpp',
    'src\native_app_launcher_v3.cpp',
    'src\native_browser_window.cpp'
)
Forbid-Tokens 'Project' $text.Project @(
    '<ClCompile Include="src\main.cpp"',
    '<ClCompile Include="src\native_desktop_window.cpp"',
    '<ClCompile Include="src\native_app_launcher.cpp"',
    '<ClCompile Include="src\native_app_launcher_v2.cpp"',
    '<ClCompile Include="src\native_web_desktop_window.cpp"'
)

# Main shell and lifecycle stay authoritative.
Require-Tokens 'Main Shell' $text.Main @(
    'NativeMonitorManager::VirtualBounds()',
    'window_manager_.SetReservedBottomPixels(0)',
    'BuildTaskbars()',
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
    'MOD_WIN | MOD_SHIFT',
    'HotTiling, modifiers, L''T''',
    'OleInitialize(nullptr)'
)
Forbid-Tokens 'Main Shell' $text.Main @('tiling_on_start', 'CloudOSNativeSettingsWindow::Load')

$initializePosition = $text.Main.IndexOf('if (!application.Initialize())')
$watchdogPosition = $text.Main.IndexOf('NativeWatchdog::StartForCurrentProcess')
if ($initializePosition -lt 0 -or $watchdogPosition -lt 0 -or $watchdogPosition -lt $initializePosition) {
    throw 'Watchdog must start only after a successful CloudOSApplication::Initialize().'
}

# AppBar/taskbar V3: persistent pins, grouping, contexts, workspace movement, and truthful hit geometry.
Require-Tokens 'Taskbar AppBar V3' $text.Taskbar @(
    'CloudOS.NativeShell.Taskbar.v3',
    'kTaskbarHeightDip = 68',
    'SHAppBarMessage(ABM_NEW',
    'SHAppBarMessage(ABM_QUERYPOS',
    'SHAppBarMessage(ABM_SETPOS',
    'SHAppBarMessage(ABM_REMOVE',
    'ABN_POSCHANGED',
    'ShellPinStore::Instance().TaskbarPins()',
    'TaskGroup',
    'ShowTaskContextMenu',
    'ShowTaskGroupPicker',
    'MoveTaskToWorkspace',
    'SetWindowFloating',
    'MoveTaskbar',
    'SetCapture',
    'CLOUDOS_WM_TASKBAR_QUERY_HIT',
    'GetSystemPowerStatus',
    'SwitchWorkspace',
    'FocusWindow'
)
Require-Tokens 'Persistent shell pins' $text.ShellPins @(
    'shell_pins_v1.dat',
    'ShellPinKind',
    'StartPins()',
    'TaskbarPins()',
    'ToggleStart',
    'ToggleTaskbar',
    'MoveStart',
    'MoveTaskbar',
    'MOVEFILE_REPLACE_EXISTING',
    'MOVEFILE_WRITE_THROUGH'
)

Require-Tokens 'DWM switcher' $text.Switcher @(
    'DwmRegisterThumbnail', 'DwmQueryThumbnailSourceSize',
    'DwmUpdateThumbnailProperties', 'DwmUnregisterThumbnail',
    'CurrentWorkspaceWindows()', 'VK_TAB', 'Commit()'
)
Require-Tokens 'Taskbar hover preview V2' $text.HoverPreview @(
    'CloudOS.NativeShell.TaskPreview.v2',
    'CLOUDOS_WM_TASKBAR_QUERY_HIT',
    'SetWindowSubclass',
    'ApplyWebFlyoutMaterial',
    'DwmRegisterThumbnail',
    'DwmQueryThumbnailSourceSize',
    'DwmUpdateThumbnailProperties',
    'DwmUnregisterThumbnail',
    'DWM_TNP_RECTDESTINATION',
    'WM_MOUSELEAVE',
    'WM_CLOSE',
    'FocusWindow'
)
Forbid-Tokens 'Taskbar hover preview V2' $text.HoverPreview @('kPinnedCount = 5')

# Start V4: Home first, pinned grid, recommendations, search/all-apps and context actions.
Require-Tokens 'Start V4' $text.Start @(
    'CloudOS.NativeShell.Start.v4',
    'ViewMode::Home',
    'L"Fixados"',
    'L"Recomendados"',
    'ShellPinStore::Instance().StartPins()',
    'StartMenuMRUTracker::Instance().GetTopApps',
    'ShowResultContextMenu',
    'ShowPinContextMenu',
    'Fixar no Iniciar',
    'Fixar na barra',
    'Mover para a esquerda',
    'Mover para a direita',
    'NativeSearchEngine::FilterApps',
    'NativeStartIndex::Instance().Query',
    'NativeStartIndex::Instance().Launch',
    'NativeStartIndex::Instance().RefreshAsync',
    'DrawWindowsIcon',
    'LVS_NOCOLUMNHEADER',
    'BS_OWNERDRAW',
    'NM_CUSTOMDRAW',
    'NM_RCLICK',
    'ApplyWebFlyoutMaterial',
    'WebSkin::Accent',
    'NM_DBLCLK',
    'NM_RETURN',
    'VK_ESCAPE',
    'Central de Comandos'
)
Forbid-Tokens 'Start V4' $text.Start @('WS_EX_CLIENTEDGE', 'L"Origem / descricao"', 'CloudOS.NativeShell.Start.v3')
Require-Tokens 'Start index' $text.StartIndex @(
    'FOLDERID_Programs', 'FOLDERID_CommonPrograms', 'shell:AppsFolder',
    'BHID_EnumItems', 'IEnumShellItems', 'SIGDN_NORMALDISPLAY',
    'SIGDN_DESKTOPABSOLUTEPARSING', 'recursive_directory_iterator',
    'std::thread', 'CoInitializeEx', 'MatchScore', 'ShellExecuteW'
)

# Existing desktop/system primitives.
Require-Tokens 'Quick Settings' $text.Quick @(
    'IAudioEndpointVolume', 'GetDefaultAudioEndpoint',
    'GetMasterVolumeLevelScalar', 'SetMasterVolumeLevelScalar',
    'SetMute', 'GetSystemPowerStatus', 'ms-settings:network-wifi',
    'ms-settings:bluetooth', 'ms-settings:display', 'ms-settings:sound'
)
Require-Tokens 'Notifications' $text.Notifications @(
    'CloudOS.NativeShell.NotificationCenter.v2', 'UnreadCount',
    'MarkAllRead', 'g_notifications', '100'
)
Require-Tokens 'Multi-monitor' $text.Monitor @(
    'EnumDisplayMonitors', 'GetMonitorInfoW', 'SM_XVIRTUALSCREEN',
    'SM_CXVIRTUALSCREEN', 'MonitorFromWindow', 'MoveWindowToAdjacentMonitor'
)
Require-Tokens 'Desktop' $text.Desktop @(
    'CloudOS.NativeShell.Desktop.v2', 'NativeDesktopDropTarget::Register',
    'NativeWallpaperManager::Draw', 'FOLDERID_Desktop', 'SHGetFileInfoW',
    'ShellExecuteW', 'NativeDesktopContextMenu::Show'
)
Forbid-Tokens 'Compiled Desktop' $text.Desktop @('start_menu_open_', 'start_button_rect_', 'taskbar_y')
Require-Tokens 'OLE drop' $text.Drop @(
    'IDropTarget', 'RegisterDragDrop', 'RevokeDragDrop', 'CF_HDROP',
    'IFileOperation', 'CopyItem', 'PerformOperations'
)
Require-Tokens 'Wallpaper' $text.Wallpaper @(
    'Software\\CloudOS\\ShellV2', 'WallpaperPath', 'RegSetValueExW',
    'SPI_SETDESKWALLPAPER', 'GetOpenFileNameW', 'InterpolationModeHighQualityBicubic'
)

# Unified old-web visual language implemented natively.
Require-Tokens 'Native unified web skin' $text.Theme @(
    'namespace WebSkin',
    'RGB(10, 10, 15)',
    'RGB(17, 17, 24)',
    'RGB(99, 102, 241)',
    'RGB(129, 140, 248)',
    'RadiusXL = 16',
    'DrawRoundedPanel',
    'PaintWindowBackground',
    'PrepareListView',
    'PaintOwnerDrawButton',
    'WindowSkinSubclass',
    'ApplyWebFlyoutMaterial',
    'ApplyWebWindowMaterial'
)
Require-Tokens 'Taskbar WebSkin' $text.Taskbar @(
    'WebSkin::BgPrimary', 'WebSkin::Accent',
    'DrawCloudLogo', 'DrawQuickGlyphs', 'WebSkin::BgHover'
)
Require-Tokens 'Desktop WebSkin' $text.Desktop @(
    'WebSkin::BgPrimary', 'Subtle ambient accents', 'WebSkin::TextPrimary'
)
Forbid-Tokens 'Desktop WebSkin' $text.Desktop @('Scale(920, dpi)')
Require-Tokens 'Quick Settings WebSkin' $text.Quick @(
    'BS_OWNERDRAW', 'ApplyWebFlyoutMaterial',
    'WebSkin::PaintOwnerDrawButton', 'WebSkin::PaintWindowBackground'
)
Require-Tokens 'Notification WebSkin' $text.Notifications @(
    'ApplyWebFlyoutMaterial', 'WebSkin::PrepareListView',
    'WebSkin::HandleListViewCustomDraw', 'BS_OWNERDRAW'
)
Require-Tokens 'Calculator WebSkin' $text.Calculator @(
    'ApplyWebWindowMaterial', 'BS_OWNERDRAW',
    'WebSkin::PaintOwnerDrawButton', 'ButtonTone::Accent', 'ButtonTone::Danger'
)
Require-Tokens 'Notepad WebSkin' $text.Notepad @(
    'ApplyWebWindowMaterial', 'Cascadia Mono',
    'BS_OWNERDRAW', 'WebSkin::PrepareEdit', 'ButtonTone::Accent'
)
Require-Tokens 'Settings WebSkin' $text.Settings @(
    'ApplyWebWindowMaterial', 'BS_OWNERDRAW',
    'WebSkin::PrepareEdit', 'WebSkin::PaintWindowBackground'
)
Require-Tokens 'System Monitor WebSkin' $text.SystemMonitor @(
    'ApplyWebWindowMaterial', 'WebSkin::BgSecondary',
    'WebSkin::Accent', 'Monitor do Sistema'
)
Require-Tokens 'Files dark palette' $text.FilesStyleHeader @(
    'RGB(10, 10, 15)', 'RGB(17, 17, 24)',
    'RGB(99, 102, 241)', 'RGB(240, 240, 245)'
)
Require-Tokens 'Files dark Mica chrome' $text.FilesStyle @(
    'DWMWA_USE_IMMERSIVE_DARK_MODE', 'DWMSBT_MAINWINDOW', 'kPalette.border'
)
Require-Tokens 'Command Center shared skin' $text.CommandCenter @('DarkWindow(window_)')
Require-Tokens 'File Operations shared skin' $text.FileOps @('DarkWindow(window_)')

# Snap Assist.
Require-Tokens 'Snap Assist' $text.Snap @(
    'SetWinEventHook', 'EVENT_SYSTEM_MOVESIZESTART',
    'EVENT_SYSTEM_MOVESIZEEND', 'EVENT_OBJECT_LOCATIONCHANGE',
    'WINEVENT_OUTOFCONTEXT', 'CloudOS.NativeShell.SnapAssistOverlay.v1',
    'WS_EX_NOACTIVATE', 'WS_EX_TRANSPARENT', 'TopLeftQuarter',
    'BottomRightQuarter', 'CenterThird', 'LeftTwoThirds', 'RightTwoThirds',
    'GetKeyState(VK_CONTROL)', 'GetKeyState(VK_SHIFT)',
    'window_manager_->SetWindowFloating', 'SetWindowPos'
)
Forbid-Tokens 'Snap Assist' $text.Snap @('CreateRemoteThread', 'WriteProcessMemory', 'SetWindowsHookEx')

# Copy/move/progress/ZIP.
Require-Tokens 'Advanced File Operations' $text.FileOps @(
    'CloudOS.Native.FileOperations.v1', 'IFileOperationProgressSink',
    'CLSID_FileOperation', 'CopyItem', 'MoveItem', 'PerformOperations',
    'GetAnyOperationsAborted', 'FOFX_ADDUNDORECORD', 'operation->Advise',
    'operation->Unadvise', 'UpdateProgress', 'ERROR_CANCELLED',
    'PBM_SETPOS', 'PBM_SETMARQUEE', 'IFileOpenDialog', 'IFileSaveDialog',
    'tar.exe -a -c -f', 'tar.exe -xf', 'CREATE_NO_WINDOW', 'TerminateProcess'
)
Require-Tokens 'Desktop File Operations entry' $text.Context @(
    'Operacoes de arquivos / ZIP', 'CloudOSNativeFileOperationsWindow::Open'
)

# Recovery/window-manager/watchdog.
Require-Tokens 'Session recovery' $text.Recovery @(
    'session_v3.dat', 'session_v3.unclean', 'FOLDERID_LocalAppData',
    'MOVEFILE_REPLACE_EXISTING', 'MOVEFILE_WRITE_THROUGH',
    'AllManagedWindows', 'RestoreWindowState', 'NativeAppLauncher::LaunchById',
    'PreviousSessionUnclean', 'CloudOS.Native.FileOperations.v1',
    'transient', 'GetWindowPlacement'
)
Require-Tokens 'Window recovery primitives' $text.WindowRecovery @(
    'AllManagedWindows', 'WorkspaceFor', 'SetWindowFloating',
    'RestoreWindowState', 'MarkWorkspaceHidden', 'SW_MAXIMIZE', 'SW_MINIMIZE'
)
Require-Tokens 'Watchdog' $text.Watchdog @(
    'CloudOS.NativeShell.Session.v1', '--watchdog', 'OpenProcess',
    'SYNCHRONIZE', 'PROCESS_QUERY_LIMITED_INFORMATION', 'WaitForSingleObject',
    'CreateProcessW', 'AcquireSessionMutex', 'StartForCurrentProcess',
    'SurfaceExistingShell'
)

# Browser/launcher remain truthful. Main Files delegates to Windows Explorer for speed.
Forbid-Tokens 'Launcher V3' $text.Launcher @('SetParent(', 'kExternalHostClass', 'CollectProcessFamily')
Require-Tokens 'Launcher V3' $text.Launcher @(
    'CloudOSNativeBrowserWindow::Open', 'CloudOSNativeCommandCenterWindow::Open',
    'StartMenuMRUTracker::Instance().RecordLaunch',
    'L"explorer.exe"'
)
Require-Tokens 'Browser' $text.Browser @(
    'CreateCoreWebView2EnvironmentWithOptions', 'CreateCoreWebView2Controller',
    'NavigationCompleted', 'HistoryChanged', 'BrowserProfile'
)

$actionPattern = '(?m)^\s*\{L"[^"]+".*ShellActionCategory::[A-Za-z]+,\s*ShellActionKind::[A-Za-z]+\},\s*$'
$actionCount = ([regex]::Matches($text.Actions, $actionPattern)).Count
if ($actionCount -lt 100) {
    throw "Shell action catalog regressed below 100 actions: $actionCount"
}

# Research/compatibility records remain available.
Require-Tokens 'V2 research' $text.ResearchV2 @(
    'SHAppBarMessage', 'ABM_NEW', 'DwmRegisterThumbnail', 'RegisterDragDrop',
    'IAudioEndpointVolume', 'EnumDisplayMonitors', 'WESL_UserSetting'
)
Require-Tokens 'V3 research' $text.ResearchV3 @(
    'SetWinEventHook', 'WINEVENT_OUTOFCONTEXT', 'DwmRegisterThumbnail',
    'FOLDERID_Programs', 'FOLDERID_CommonPrograms', 'shell:AppsFolder',
    'IFileOperationProgressSink', 'tar.exe -a -c -f', 'session_v3.dat',
    'CreateProcessW', 'WaitForSingleObject', 'WM_QUERYENDSESSION'
)
Require-Tokens 'V3 matrix' $text.FeaturesV3 @(
    'Snap Assist', 'Hover previews da taskbar', 'Start Indexer',
    'Operações de arquivos', 'Session Recovery', 'Watchdog', '150.'
)
Require-Tokens 'Official Shell Launcher script' $text.ShellLauncher @(
    'root/standardcimv2/embedded', 'WESL_UserSetting', 'SetCustomShell',
    'SetEnabled', 'RemoveCustomShell', 'Enterprise|Education|IoT', 'ShouldProcess'
)

Write-Host "PASS: CloudOS shell contracts passed - Start V4 Home/search/pins, Taskbar V3 groups/pins/context, WebSkin, AppBars, Snap, DWM previews, recovery, watchdog, multi-monitor and $actionCount shell actions."
