$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'

$paths = @{
    Project = Join-Path $root 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
    Main = Join-Path $src 'main_shell_v2.cpp'
    Desktop = Join-Path $src 'native_desktop_window_v2.cpp'
    Start = Join-Path $src 'native_start_menu_window.cpp'
    StartIndex = Join-Path $src 'native_start_index.cpp'
    Taskbar = Join-Path $src 'native_taskbar_appbar_v4.cpp'
    TaskbarHeader = Join-Path $src 'native_taskbar_appbar.h'
    Hover = Join-Path $src 'native_taskbar_hover_preview.cpp'
    Pins = Join-Path $src 'native_shell_pins.cpp'
    PinsHeader = Join-Path $src 'native_shell_pins.h'
    Theme = Join-Path $src 'native_theme.h'
    Snap = Join-Path $src 'native_snap_assist.cpp'
    Recovery = Join-Path $src 'native_session_recovery.cpp'
    RecoveryHeader = Join-Path $src 'native_session_recovery.h'
    Watchdog = Join-Path $src 'native_watchdog.cpp'
    FileOps = Join-Path $src 'native_file_operations_window.cpp'
    Launcher = Join-Path $src 'native_app_launcher_v3.cpp'
    Browser = Join-Path $src 'native_browser_window.cpp'
    Actions = Join-Path $src 'native_shell_actions.cpp'
    Quick = Join-Path $src 'native_quick_settings_window.cpp'
    Monitor = Join-Path $src 'native_monitor_manager.cpp'
    Drop = Join-Path $src 'native_desktop_drop_target.cpp'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "CloudOS contract file missing [$($entry.Key)]: $($entry.Value)"
    }
}

$content = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}
$content.Pins = $content.PinsHeader + "`n" + $content.Pins
$content.Recovery = $content.RecoveryHeader + "`n" + $content.Recovery
$content.Taskbar = $content.TaskbarHeader + "`n" + $content.Taskbar

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

Require 'Build graph' $content.Project @(
    'src\main_shell_v2.cpp',
    'src\native_desktop_window_v2.cpp',
    'src\native_start_menu_window.cpp',
    'src\native_start_index.cpp',
    'src\native_shell_pins.cpp',
    'src\native_taskbar_appbar_v4.cpp',
    'src\native_taskbar_hover_preview.cpp',
    'src\native_snap_assist.cpp',
    'src\native_session_recovery.cpp',
    'src\native_watchdog.cpp',
    'src\native_file_operations_window.cpp',
    'src\native_app_launcher_v3.cpp',
    'src\native_browser_window.cpp'
)
Forbid 'Build graph' $content.Project @(
    '<ClCompile Include="src\main.cpp"',
    '<ClCompile Include="src\native_desktop_window.cpp"',
    '<ClCompile Include="src\native_taskbar_appbar.cpp"',
    '<ClCompile Include="src\native_web_desktop_window.cpp"',
    '<ClCompile Include="src\native_app_launcher.cpp"',
    '<ClCompile Include="src\native_app_launcher_v2.cpp"'
)

Require 'Session shell' $content.Main @(
    'CloudOSDesktopSurface desktop_',
    'CloudOSNativeWindowManager window_manager_',
    'CloudOSNativeStartMenuWindow start_menu_',
    'CloudOSTaskbarAppBar',
    'BuildTaskbars()',
    'window_manager_.SetReservedBottomPixels(0)',
    'NativeTaskbarHoverPreview::Attach',
    'snap_assist_.Start',
    'session_recovery_.BeginSession',
    'session_recovery_.Restore',
    'session_recovery_.Tick',
    'session_recovery_.MarkCleanExit',
    'WM_QUERYENDSESSION',
    'WM_ENDSESSION',
    'PBT_APMSUSPEND',
    'NativeWatchdog::AcquireSessionMutex',
    'NativeWatchdog::StartForCurrentProcess',
    'OleInitialize(nullptr)'
)
Forbid 'Session shell' $content.Main @('tiling_on_start')

Require 'Start V4' $content.Start @(
    'CloudOS.NativeShell.Start.v4',
    'ViewMode::Home',
    'L"Fixados"',
    'L"Recomendados"',
    'ShellPinStore::Instance().StartPins()',
    'StartMenuMRUTracker::Instance().GetTopApps',
    'NativeSearchEngine::FilterApps',
    'NativeStartIndex::Instance().Query',
    'NativeStartIndex::Instance().Launch',
    'NativeStartIndex::Instance().RefreshAsync',
    'DrawWindowsIcon',
    'ShowResultContextMenu',
    'ShowPinContextMenu',
    'Fixar no Iniciar',
    'Fixar na barra',
    'Mover para a esquerda',
    'Mover para a direita',
    'NM_RCLICK',
    'NM_CUSTOMDRAW',
    'LVS_NOCOLUMNHEADER',
    'BS_OWNERDRAW',
    'ApplyWebFlyoutMaterial'
)
Forbid 'Start V4' $content.Start @(
    'CloudOS.NativeShell.Start.v3',
    'WS_EX_CLIENTEDGE',
    'L"Origem / descricao"'
)
Require 'Windows app index' $content.StartIndex @(
    'FOLDERID_Programs',
    'FOLDERID_CommonPrograms',
    'shell:AppsFolder',
    'BHID_EnumItems',
    'SIGDN_DESKTOPABSOLUTEPARSING',
    'recursive_directory_iterator',
    'std::thread',
    'CoInitializeEx',
    'MatchScore',
    'ShellExecuteW'
)

Require 'Persistent pins' $content.Pins @(
    'ShellPinKind',
    'shell_pins_v1.dat',
    'StartPins()',
    'TaskbarPins()',
    'ToggleStart',
    'ToggleTaskbar',
    'MoveStart',
    'MoveTaskbar',
    'MOVEFILE_REPLACE_EXISTING',
    'MOVEFILE_WRITE_THROUGH'
)

Require 'Taskbar V4' $content.Taskbar @(
    'CloudOS.NativeShell.Taskbar.v4',
    'kTaskbarHeightDip = DesignV12::TaskbarHeight',
    'SHAppBarMessage(ABM_NEW',
    'SHAppBarMessage(ABM_QUERYPOS',
    'SHAppBarMessage(ABM_SETPOS',
    'SHAppBarMessage(ABM_REMOVE',
    'ABN_POSCHANGED',
    'ShellPinStore::Instance().TaskbarPins()',
    'TaskGroup',
    'ShowPinnedContextMenu',
    'ShowTaskContextMenu',
    'ShowTaskGroupPicker',
    'ShowTaskOverflowMenu',
    'visible_task_group_count_',
    'MoveTaskToWorkspace',
    'SetWindowFloating',
    'MoveTaskbar',
    'SetCapture',
    'CLOUDOS_WM_TASKBAR_QUERY_HIT',
    'GetSystemPowerStatus',
    'SwitchWorkspace',
    'FocusWindow',
    'DrawStartGlyph',
    'DrawQuickGlyph'
)
Require 'DWM hover preview' $content.Hover @(
    'CloudOS.NativeShell.TaskPreview.v2',
    'CLOUDOS_WM_TASKBAR_QUERY_HIT',
    'DwmRegisterThumbnail',
    'DwmQueryThumbnailSourceSize',
    'DwmUpdateThumbnailProperties',
    'DwmUnregisterThumbnail',
    'ApplyWebFlyoutMaterial',
    'WM_CLOSE',
    'FocusWindow'
)
Forbid 'DWM hover preview' $content.Hover @('kPinnedCount = 5')

# Visual Experience V6 is semantic native design, not a frozen copy of old CSS hex values.
Require 'WebSkin' $content.Theme @(
    'namespace WebSkin',
    'BgSolid = DesignV12::Canvas',
    'BgPrimary = DesignV12::Background',
    'BgSecondary = DesignV12::Surface',
    'Accent = DesignV12::Accent',
    'AccentHover = DesignV12::AccentHover',
    'AccentCyan = DesignV12::Accent',
    'RadiusXL = DesignV12::RadiusLarge',
    'DrawRoundedPanel',
    'DrawElevatedPanel',
    'PaintWindowBackground',
    'PaintOwnerDrawButton',
    'WindowSkinSubclass',
    'ApplyWebFlyoutMaterial',
    'ApplyWebWindowMaterial'
)
Require 'Desktop shell' $content.Desktop @(
    'CloudOS.NativeShell.Desktop.v2',
    'NativeDesktopDropTarget::Register',
    'NativeWallpaperManager::Draw',
    'desktop_model_.Start',
    'NativeIconCacheV12::Instance().Get',
    'NativeDesktopContextMenu::Show',
    'WebSkin::BgPrimary'
)
Require 'Quick Settings' $content.Quick @(
    'IAudioEndpointVolume',
    'GetMasterVolumeLevelScalar',
    'SetMasterVolumeLevelScalar',
    'SetMute',
    'GetSystemPowerStatus',
    'ms-settings:network-wifi',
    'ms-settings:bluetooth'
)
Require 'Multi-monitor' $content.Monitor @(
    'EnumDisplayMonitors',
    'GetMonitorInfoW',
    'SM_XVIRTUALSCREEN',
    'MonitorFromWindow',
    'MoveWindowToAdjacentMonitor'
)
Require 'Desktop drag/drop' $content.Drop @(
    'IDropTarget',
    'RegisterDragDrop',
    'RevokeDragDrop',
    'CF_HDROP',
    'IFileOperation'
)

Require 'Snap Assist' $content.Snap @(
    'SetWinEventHook',
    'EVENT_SYSTEM_MOVESIZESTART',
    'EVENT_SYSTEM_MOVESIZEEND',
    'EVENT_OBJECT_LOCATIONCHANGE',
    'WINEVENT_OUTOFCONTEXT',
    'CloudOS.NativeShell.SnapAssistOverlay.v1',
    'TopLeftQuarter',
    'BottomRightQuarter',
    'LeftTwoThirds',
    'RightTwoThirds',
    'SetWindowPos'
)
Forbid 'Snap Assist' $content.Snap @('CreateRemoteThread', 'WriteProcessMemory')
Require 'File Operations' $content.FileOps @(
    'IFileOperationProgressSink',
    'CLSID_FileOperation',
    'CopyItem',
    'MoveItem',
    'PerformOperations',
    'GetAnyOperationsAborted',
    'FOFX_ADDUNDORECORD',
    'operation->Advise',
    'UpdateProgress',
    'tar.exe -a -c -f',
    'tar.exe -xf',
    'CREATE_NO_WINDOW'
)
Require 'Recovery' $content.Recovery @(
    'session_v3.dat',
    'session_v3.unclean',
    'FOLDERID_LocalAppData',
    'NativeAppLauncher::LaunchById',
    'PreviousSessionUnclean',
    'GetWindowPlacement'
)
Require 'Watchdog' $content.Watchdog @(
    'CloudOS.NativeShell.Session.v1',
    '--watchdog',
    'OpenProcess',
    'WaitForSingleObject',
    'CreateProcessW',
    'AcquireSessionMutex',
    'StartForCurrentProcess'
)

Require 'Launcher' $content.Launcher @(
    '#include "native_files_window.h"',
    'CloudOSNativeBrowserWindow::Open',
    'StartMenuMRUTracker::Instance().RecordLaunch',
    'else if (id == L"files")',
    'CloudOSNativeFilesWindow::Open(instance);',
    'else if (id == L"drive")',
    'CloudOSNativeFilesWindow::Open(instance, root);',
    'else if (id == L"systemdrive")',
    'CloudOSNativeFilesWindow::Open(instance, system_volume);'
)
Forbid 'Launcher' $content.Launcher @('L"explorer.exe"', 'SetParent(', 'kExternalHostClass')
Require 'Browser' $content.Browser @(
    'CreateCoreWebView2EnvironmentWithOptions',
    'CreateCoreWebView2Controller',
    'NavigationCompleted',
    'HistoryChanged',
    'BrowserProfile'
)

$actionPattern = '(?m)^\s*\{L"[^"]+".*ShellActionCategory::[A-Za-z]+,\s*ShellActionKind::[A-Za-z]+\},\s*$'
$actionCount = ([regex]::Matches($content.Actions, $actionPattern)).Count
if ($actionCount -lt 100) {
    throw "Shell action catalog regressed below 100 actions: $actionCount"
}

Write-Host "PASS: CloudOS shell contracts passed - Start V4, Taskbar V4, persistent pins, grouped/overflow tasks, Visual Experience V6, Snap, DWM previews, recovery, first-party Files integration and $actionCount shell actions."
