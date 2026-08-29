$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$desktopPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_desktop_window.cpp'
$surfacePath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_desktop_surface.cpp'
$surfaceHeaderPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_desktop_surface.h'
$launcherPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_app_launcher.cpp'
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

foreach ($path in @(
    $desktopPath,$surfacePath,$surfaceHeaderPath,$launcherPath,$mainPath,$settingsPath,$settingsHeaderPath,
    $themePath,$mruPath,$platformPath,$shellViewPath,$drivePath,$trashPath,$filesPath,$filesInternalPath,
    $filesStylePath,$filesNavigationPath,$filesOperationsPath,$filesSupportPath,$projectsPath,$projectPath,
    $researchPolicyPath,$filesResearchPath,$desktopResearchPath
)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required native shell file missing: $path" }
}

$desktop = Get-Content -LiteralPath $desktopPath -Raw
$surface = Get-Content -LiteralPath $surfacePath -Raw
$surfaceHeader = Get-Content -LiteralPath $surfaceHeaderPath -Raw
$launcher = Get-Content -LiteralPath $launcherPath -Raw
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

foreach ($token in @('Neo-Tokyo','22°C','OCT 26, 2045','CloudOS Architecture Sync','Sistema 100% Operacional','CloudOS Native Kernel v2.0')) {
    if ($desktop.Contains($token)) { throw "Synthetic desktop data regressed into native UI: $token" }
}

foreach ($token in @('CurrentWorkspaceWindows','StartMenuMRUTracker::Instance().GetTopApps','cloudos_native_runtime_abi','FocusWindow','SwitchWorkspace')) {
    if (-not $desktop.Contains($token)) { throw "Desktop contract missing: $token" }
}
foreach ($token in @('BuildDesktopShortcuts','BuildDockApps','BuildStartApps','start_menu_open_','start_button_rect_','system_button_rect_','clock_rect_','Tiling manual')) {
    if (-not $desktop.Contains($token)) { throw "Desktop shell UX contract missing: $token" }
}
foreach ($token in @('dashboard central permanente','DesktopSurface','Taskbar','StartMenu','WindowManager','DWM','Shell Launcher')) {
    if (-not $desktopResearch.Contains($token)) { throw "Desktop shell architecture research missing: $token" }
}

if (-not $surface.Contains('return native_.Create(instance, window_manager)')) { throw 'Native desktop surface must be authoritative at startup.' }
foreach ($token in @('web_.Create','native_web_desktop_window.h','web_active_')) {
    if ($surface.Contains($token) -or $surfaceHeader.Contains($token)) { throw "Web-first desktop presentation regressed into the authoritative shell surface: $token" }
}
if (-not $surfaceHeader.Contains('UsingWebUi() const noexcept { return false; }')) { throw 'Desktop surface must report native-only presentation.' }

if ($main.Contains('tiling_on_start') -or $main.Contains('CloudOSNativeSettingsWindow::Load')) { throw 'Tiling must never be restored or auto-enabled during shell startup.' }
if (-not $main.Contains('window_manager_.ToggleTiling()') -or -not $main.Contains('{HotTiling, modifiers, L''T''}')) { throw 'Manual tiling toggle contract missing.' }
if ($settings.Contains('TilingOnStart') -and -not $settings.Contains('RegDeleteValueW')) { throw 'Legacy TilingOnStart persistence must be removed, not loaded.' }
if ($settingsHeader.Contains('tiling_on_start') -or $settingsHeader.Contains('tiling_checkbox_')) { throw 'Startup tiling setting must not exist in the settings model or UI.' }

foreach ($token in @('GetDateFormatEx','GetTimeFormatEx','GetWindowsDirectoryW','GetVolumePathNameW')) {
    if (-not $platform.Contains($token)) { throw "Platform contract missing: $token" }
}
foreach ($token in @('CanonicalAppId','SEE_MASK_NOCLOSEPROCESS','StartMenuMRUTracker::Instance().RecordLaunch','CloudOSNativeProjectsWindow::Open','NativeCloudOSDrive::EnsureReady','CloudOSNativeFilesWindow::Open(instance, root)','OpenWslTerminal','systemdrive','ms-settings:dateandtime')) {
    if (-not $launcher.Contains($token)) { throw "Launcher contract missing: $token" }
}
foreach ($token in @('kExternalHostClass','CollectProcessFamily','SetParent(application_window, state->host)','WS_CHILD','CloudOSNativeFilesWindow::Open(instance, system_volume)')) {
    if (-not $launcher.Contains($token)) { throw "Contained external app contract missing: $token" }
}
if ($launcher.Contains('External Windows programs stay independent top-level HWNDs')) { throw 'Launcher must not intentionally allow managed external apps to escape the CloudOS surface.' }
if (-not $main.Contains('HotSearch') -or -not $main.Contains('VK_SPACE')) { throw 'Global native search hotkey contract missing.' }
if ($theme.Contains('Disco Local (C:)') -or $theme.Contains('Disco C:')) { throw 'System volume label must not assume Windows is installed on C:.' }
if (-not $theme.Contains('L"drive", L"CloudOS Drive"') -or -not $theme.Contains('L"systemdrive", L"Disco do Sistema"') -or -not $theme.Contains('L"projects", L"Projetos"') -or -not $theme.Contains('L"wsl", L"WSL / Kali"')) { throw 'CloudOS Drive, system volume, Projects and WSL must remain distinct truthful app identities.' }
if (-not $mru.Contains('SHGetKnownFolderPath') -or -not $mru.Contains('FOLDERID_LocalAppData') -or -not $mru.Contains('MoveFileExW')) { throw 'MRU persistence must use Known Folders and atomic replacement.' }

foreach ($token in @('CLSID_ExplorerBrowser','IExplorerBrowserEvents','OleInitialize','browser->Initialize','browser->Advise','BrowseToIDList','IFolderView2','DoRename','InvokeVerbOnSelection','SetViewModeAndIconSize','FVM_DETAILS','CloudOS.NativeFiles.ShellView.v2','browser_->Destroy')) {
    if (-not $shellView.Contains($token)) { throw "Native Windows Shell view contract missing: $token" }
}
if ($shellView.Contains('#include <WebView2.h>') -or $shellView.Contains('ICoreWebView2')) { throw 'Native Shell view must not depend on WebView2.' }

foreach ($token in @('DWMWA_SYSTEMBACKDROP_TYPE','DWMSBT_MAINWINDOW','DWMWA_WINDOW_CORNER_PREFERENCE','DWMWA_USE_IMMERSIVE_DARK_MODE','PaintRoundedSurface')) {
    if (-not $filesStyle.Contains($token)) { throw "Modern Files visual contract missing: $token" }
}

foreach ($token in @('CLOUDOS_DRIVE_DIR','FOLDERID_LocalAppData','.cloudos-system','FILE_ATTRIBUTE_REPARSE_POINT','ValidateSegments','NativeCloudOSDrive::List','NativeCloudOSDrive::Read','NativeCloudOSDrive::Write','NativeCloudOSDrive::Mkdir','NativeCloudOSDrive::Move','NativeCloudOSDrive::Copy','NativeCloudOSDrive::Trash','NativeCloudOSDrive::ListTrash','NativeCloudOSDrive::RestoreTrash','NativeCloudOSDrive::DeleteTrash','NativeCloudOSDrive::EmptyTrash')) {
    if (-not $drive.Contains($token)) { throw "CloudOS Drive native contract missing: $token" }
}

foreach ($token in @('shell_view_.Create','FOLDERID_Profile','FOLDERID_Desktop','FOLDERID_Documents','FOLDERID_Downloads','SHGetStockIconInfo','NavigateCloudOSDrive','CloudOSNativeDriveTrashWindow::Open','NativeCloudOSDrive::List','NativeCloudOSDrive::Mkdir','NativeCloudOSDrive::Trash','NativeCloudOSDrive::Move','shell_view_.BeginRenameSelection','shell_view_.DeleteSelection','FOF_ALLOWUNDO','LVS_ICON','SHGFI_LARGEICON','ListView_SetIconSpacing','destroy_deletes_self_','CustomDrawSidebar','NM_CUSTOMDRAW','CloudOS Drive  •  Windows  •  WSL','ApplyWindowChrome')) {
    if (-not $files.Contains($token)) { throw "Native Files integration contract missing: $token" }
}
if ($files.Contains('CloudOS::DarkWindow(window_)')) { throw 'Files must not force a dark frame around a light Windows Shell surface.' }

foreach ($token in @('NativeCloudOSDrive::ListTrash','NativeCloudOSDrive::RestoreTrash','NativeCloudOSDrive::DeleteTrash','NativeCloudOSDrive::EmptyTrash')) {
    if (-not $trash.Contains($token)) { throw "Native Drive Trash contract missing: $token" }
}
foreach ($token in @('kProjectsSegments','NativeCloudOSDrive::List','NativeCloudOSDrive::Mkdir','NativeCloudOSDrive::Move','NativeCloudOSDrive::Trash','CloudOSNativeFilesWindow::Open','CloudOSNativeTerminalWindow::Open','code.cmd')) {
    if (-not $projects.Contains($token)) { throw "Native Projects contract missing: $token" }
}
foreach ($source in @('src\native_cloudos_drive.cpp','src\native_cloudos_trash_window.cpp','src\native_projects_window.cpp','src\native_shell_view_host.cpp','src\native_files_navigation.cpp','src\native_files_operations.cpp','src\native_files_support.cpp','src\native_files_style.cpp')) {
    if (-not $project.Contains($source)) { throw "Required native source not compiled by project: $source" }
}

foreach ($token in @('pesquisar antes de implementar','docs/native/research/','Microsoft Learn','licença')) {
    if (-not $researchPolicy.Contains($token)) { throw "Research-before-implementation policy missing: $token" }
}
foreach ($token in @('IExplorerBrowser','Windows-classic-samples','MIT','Explorer++','GPL-3.0','nenhum código GPL','CloudOS Drive','mr-foxxo/vibe-os','inconsistência de licença','Nenhum código do VibeOS foi copiado','Microsoft Fluent','DWMWA_SYSTEMBACKDROP_TYPE','Mica','Files Community','duas camadas claras')) {
    if (-not $filesResearch.Contains($token)) { throw "Files research record missing: $token" }
}

foreach ($source in @('src\native_start_menu_window.cpp','src\native_taskbar_window.cpp','src\native_dash_window.cpp')) {
    if ($project.Contains($source)) { throw "Empty/provisional shell placeholder returned to build: $source" }
}

Write-Host 'PASS: CloudOS native desktop shell, Start/taskbar/workspaces, manual tiling, contained external apps, Drive, modern Files, Windows Shell view and Projects contracts are truthful and functional.'
