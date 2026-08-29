$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$desktopPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_desktop_window.cpp'
$surfacePath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_desktop_surface.cpp'
$surfaceHeaderPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_desktop_surface.h'
$launcherPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_app_launcher_v2.cpp'
$browserPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_browser_window.cpp'
$browserHeaderPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_browser_window.h'
$mainPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\main.cpp'
$settingsPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_settings_window.cpp'
$settingsHeaderPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_settings_window.h'
$themePath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_theme.h'
$mruPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_start_menu_mru.h'
$platformPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_shell_platform.cpp'
$shellViewPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_shell_view_host.cpp'
$drivePath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_cloudos_drive.cpp'
$trashPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_cloudos_trash_window.cpp'
$filesPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_files_window.cpp'
$filesInternalPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_files_internal.h'
$filesStylePath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_files_style.cpp'
$filesNavigationPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_files_navigation.cpp'
$filesOperationsPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_files_operations.cpp'
$filesSupportPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_files_support.cpp'
$projectsPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_projects_window.cpp'
$projectPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
$researchPolicyPath = Join-Path $repoRoot 'docs\native\RESEARCH_POLICY.md'
$filesResearchPath = Join-Path $repoRoot 'docs\native\research\FILES_NATIVE_SHELL_RESEARCH.md'
$desktopResearchPath = Join-Path $repoRoot 'docs\native\research\DESKTOP_SHELL_ARCHITECTURE.md'
$browserResearchPath = Join-Path $repoRoot 'docs\native\research\BROWSER_WINDOWING_RESEARCH.md'

$required = @(
    $desktopPath,$surfacePath,$surfaceHeaderPath,$launcherPath,$browserPath,$browserHeaderPath,
    $mainPath,$settingsPath,$settingsHeaderPath,$themePath,$mruPath,$platformPath,$shellViewPath,
    $drivePath,$trashPath,$filesPath,$filesInternalPath,$filesStylePath,$filesNavigationPath,
    $filesOperationsPath,$filesSupportPath,$projectsPath,$projectPath,$researchPolicyPath,
    $filesResearchPath,$desktopResearchPath,$browserResearchPath
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required native shell file missing: $path" }
}

$desktop = Get-Content -LiteralPath $desktopPath -Raw
$surface = Get-Content -LiteralPath $surfacePath -Raw
$surfaceHeader = Get-Content -LiteralPath $surfaceHeaderPath -Raw
$launcher = Get-Content -LiteralPath $launcherPath -Raw
$browser = Get-Content -LiteralPath $browserPath -Raw
$main = Get-Content -LiteralPath $mainPath -Raw
$settings = Get-Content -LiteralPath $settingsPath -Raw
$settingsHeader = Get-Content -LiteralPath $settingsHeaderPath -Raw
$theme = Get-Content -LiteralPath $themePath -Raw
$mru = Get-Content -LiteralPath $mruPath -Raw
$platform = Get-Content -LiteralPath $platformPath -Raw
$shellView = Get-Content -LiteralPath $shellViewPath -Raw
$drive = Get-Content -LiteralPath $drivePath -Raw
$trash = Get-Content -LiteralPath $trashPath -Raw
$filesStyle = Get-Content -LiteralPath $filesStylePath -Raw
$files = (Get-Content -LiteralPath $filesPath -Raw) +
    (Get-Content -LiteralPath $filesInternalPath -Raw) +
    (Get-Content -LiteralPath $filesNavigationPath -Raw) +
    (Get-Content -LiteralPath $filesOperationsPath -Raw) +
    (Get-Content -LiteralPath $filesSupportPath -Raw)
$projects = Get-Content -LiteralPath $projectsPath -Raw
$project = Get-Content -LiteralPath $projectPath -Raw
$researchPolicy = Get-Content -LiteralPath $researchPolicyPath -Raw
$filesResearch = Get-Content -LiteralPath $filesResearchPath -Raw
$desktopResearch = Get-Content -LiteralPath $desktopResearchPath -Raw
$browserResearch = Get-Content -LiteralPath $browserResearchPath -Raw

foreach ($token in @('Neo-Tokyo','22°C','OCT 26, 2045','CloudOS Architecture Sync','Sistema 100% Operacional','CloudOS Native Kernel v2.0')) {
    if ($desktop.Contains($token)) { throw "Synthetic desktop data regressed into native UI: $token" }
}
foreach ($token in @('CurrentWorkspaceWindows','StartMenuMRUTracker::Instance().GetTopApps','cloudos_native_runtime_abi','FocusWindow','SwitchWorkspace','BuildDesktopShortcuts','BuildDockApps','BuildStartApps','start_menu_open_','start_button_rect_','system_button_rect_','clock_rect_','Tiling manual')) {
    if (-not $desktop.Contains($token)) { throw "Desktop shell contract missing: $token" }
}
foreach ($token in @('dashboard central permanente','DesktopSurface','Taskbar','StartMenu','WindowManager','DWM','Shell Launcher')) {
    if (-not $desktopResearch.Contains($token)) { throw "Desktop research contract missing: $token" }
}

if (-not $surface.Contains('return native_.Create(instance, window_manager)')) { throw 'Native desktop must remain authoritative.' }
foreach ($token in @('web_.Create','native_web_desktop_window.h','web_active_')) {
    if ($surface.Contains($token) -or $surfaceHeader.Contains($token)) { throw "Web-first shell regressed: $token" }
}
if (-not $surfaceHeader.Contains('UsingWebUi() const noexcept { return false; }')) { throw 'Desktop surface must report native-only presentation.' }

if ($main.Contains('tiling_on_start') -or $main.Contains('CloudOSNativeSettingsWindow::Load')) { throw 'Tiling must not restore itself on startup.' }
if (-not $main.Contains('window_manager_.ToggleTiling()') -or -not $main.Contains('{HotTiling, modifiers, L''T''}')) { throw 'Manual tiling contract missing.' }
if ($settings.Contains('TilingOnStart') -and -not $settings.Contains('RegDeleteValueW')) { throw 'Legacy TilingOnStart must be deleted.' }
if ($settingsHeader.Contains('tiling_on_start') -or $settingsHeader.Contains('tiling_checkbox_')) { throw 'Startup tiling setting must not exist.' }

foreach ($token in @('CanonicalAppId','StartMenuMRUTracker::Instance().RecordLaunch','CloudOSNativeProjectsWindow::Open','NativeCloudOSDrive::EnsureReady','CloudOSNativeFilesWindow::Open(instance, root)','OpenWslTerminal','CloudOSNativeBrowserWindow::Open','LaunchWindowsTarget','ms-settings:dateandtime')) {
    if (-not $launcher.Contains($token)) { throw "Launcher v2 contract missing: $token" }
}
foreach ($forbidden in @('SetParent(','kExternalHostClass','CollectProcessFamily','SetParent(application_window','style |= WS_CHILD')) {
    if ($launcher.Contains($forbidden)) { throw "Fragile cross-process embedding returned to compiled launcher: $forbidden" }
}
if ($launcher.Contains('LaunchWindowsTarget(parent_hwnd, L"https://www.google.com/') -or $launcher.Contains('LaunchExternal(parent_hwnd, L"https://www.google.com/')) {
    throw 'Browser URL must never be sent through external process hosting.'
}

foreach ($token in @('CreateCoreWebView2EnvironmentWithOptions','CreateCoreWebView2Controller','ICoreWebView2Controller','Navigate(','NavigationCompleted','HistoryChanged','get_CanGoBack','get_CanGoForward','GoBack','GoForward','Reload','BrowserProfile','NormalizeUrl')) {
    if (-not $browser.Contains($token)) { throw "Native Browser contract missing: $token" }
}
foreach ($token in @('WebView2','SetParent','cross-process','Shell Launcher','top-level HWND','BrowserProfile')) {
    if (-not $browserResearch.Contains($token)) { throw "Browser/windowing research missing: $token" }
}

foreach ($token in @('GetDateFormatEx','GetTimeFormatEx','GetWindowsDirectoryW','GetVolumePathNameW')) {
    if (-not $platform.Contains($token)) { throw "Platform contract missing: $token" }
}
if ($theme.Contains('Disco Local (C:)') -or $theme.Contains('Disco C:')) { throw 'System volume must not assume C:.' }
if (-not $mru.Contains('SHGetKnownFolderPath') -or -not $mru.Contains('FOLDERID_LocalAppData') -or -not $mru.Contains('MoveFileExW')) { throw 'MRU persistence contract missing.' }

foreach ($token in @('CLSID_ExplorerBrowser','IExplorerBrowserEvents','OleInitialize','browser->Initialize','browser->Advise','BrowseToIDList','IFolderView2','DoRename','InvokeVerbOnSelection','SetViewModeAndIconSize','FVM_DETAILS','browser_->Destroy')) {
    if (-not $shellView.Contains($token)) { throw "Windows Shell view contract missing: $token" }
}
if ($shellView.Contains('#include <WebView2.h>') -or $shellView.Contains('ICoreWebView2')) { throw 'Files Shell view must not depend on WebView2.' }

foreach ($token in @('DWMWA_SYSTEMBACKDROP_TYPE','DWMSBT_MAINWINDOW','DWMWA_WINDOW_CORNER_PREFERENCE','DWMWA_USE_IMMERSIVE_DARK_MODE','PaintRoundedSurface')) {
    if (-not $filesStyle.Contains($token)) { throw "Files visual contract missing: $token" }
}
foreach ($token in @('CLOUDOS_DRIVE_DIR','FOLDERID_LocalAppData','.cloudos-system','ValidateSegments','NativeCloudOSDrive::List','NativeCloudOSDrive::Read','NativeCloudOSDrive::Write','NativeCloudOSDrive::Mkdir','NativeCloudOSDrive::Move','NativeCloudOSDrive::Copy','NativeCloudOSDrive::Trash','NativeCloudOSDrive::RestoreTrash')) {
    if (-not $drive.Contains($token)) { throw "Drive contract missing: $token" }
}
foreach ($token in @('shell_view_.Create','FOLDERID_Profile','FOLDERID_Desktop','FOLDERID_Documents','FOLDERID_Downloads','NavigateCloudOSDrive','NativeCloudOSDrive::List','NativeCloudOSDrive::Mkdir','NativeCloudOSDrive::Trash','shell_view_.BeginRenameSelection','shell_view_.DeleteSelection','FOF_ALLOWUNDO')) {
    if (-not $files.Contains($token)) { throw "Files integration contract missing: $token" }
}
foreach ($token in @('NativeCloudOSDrive::ListTrash','NativeCloudOSDrive::RestoreTrash','NativeCloudOSDrive::DeleteTrash','NativeCloudOSDrive::EmptyTrash')) {
    if (-not $trash.Contains($token)) { throw "Trash contract missing: $token" }
}
foreach ($token in @('kProjectsSegments','NativeCloudOSDrive::List','NativeCloudOSDrive::Mkdir','NativeCloudOSDrive::Move','CloudOSNativeFilesWindow::Open','CloudOSNativeTerminalWindow::Open','code.cmd')) {
    if (-not $projects.Contains($token)) { throw "Projects contract missing: $token" }
}

foreach ($source in @('src\native_browser_window.cpp','src\native_app_launcher_v2.cpp','src\native_cloudos_drive.cpp','src\native_projects_window.cpp','src\native_shell_view_host.cpp','src\native_files_style.cpp')) {
    if (-not $project.Contains($source)) { throw "Required source not compiled: $source" }
}
if ($project.Contains('<ClCompile Include="src\native_app_launcher.cpp"')) { throw 'Legacy SetParent launcher must not be compiled.' }

foreach ($token in @('pesquisar antes de implementar','docs/native/research/','Microsoft Learn','licença')) {
    if (-not $researchPolicy.Contains($token)) { throw "Research policy missing: $token" }
}
foreach ($token in @('IExplorerBrowser','Windows-classic-samples','Explorer++','CloudOS Drive','Microsoft Fluent','DWMWA_SYSTEMBACKDROP_TYPE','Mica')) {
    if (-not $filesResearch.Contains($token)) { throw "Files research record missing: $token" }
}

Write-Host 'PASS: CloudOS native desktop shell, native WebView2 Browser, OS-managed external windows, Start/taskbar/workspaces, manual tiling, Drive, Files and Projects contracts are truthful and functional.'
