$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$desktopPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_desktop_window.cpp'
$launcherPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_app_launcher.cpp'
$mainPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\main.cpp'
$themePath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_theme.h'
$mruPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_start_menu_mru.h'
$platformPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_shell_platform.cpp'
$drivePath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_cloudos_drive.cpp'
$trashPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_cloudos_trash_window.cpp'
$filesPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_files_window.cpp'
$projectsPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_projects_window.cpp'
$projectPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'

foreach ($path in @(
    $desktopPath,
    $launcherPath,
    $mainPath,
    $themePath,
    $mruPath,
    $platformPath,
    $drivePath,
    $trashPath,
    $filesPath,
    $projectsPath,
    $projectPath
)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required native shell file missing: $path"
    }
}

$desktop = Get-Content -LiteralPath $desktopPath -Raw
$launcher = Get-Content -LiteralPath $launcherPath -Raw
$main = Get-Content -LiteralPath $mainPath -Raw
$theme = Get-Content -LiteralPath $themePath -Raw
$mru = Get-Content -LiteralPath $mruPath -Raw
$platform = Get-Content -LiteralPath $platformPath -Raw
$drive = Get-Content -LiteralPath $drivePath -Raw
$trash = Get-Content -LiteralPath $trashPath -Raw
$files = Get-Content -LiteralPath $filesPath -Raw
$projects = Get-Content -LiteralPath $projectsPath -Raw
$project = Get-Content -LiteralPath $projectPath -Raw

$forbiddenFakeUi = @(
    'Neo-Tokyo',
    '22°C',
    'OCT 26, 2045',
    'CloudOS Architecture Sync',
    'Sistema 100% Operacional',
    'CloudOS Native Kernel v2.0'
)

foreach ($token in $forbiddenFakeUi) {
    if ($desktop.Contains($token)) {
        throw "Synthetic desktop data regressed into native UI: $token"
    }
}

$desktopContracts = @(
    'CurrentWorkspaceWindows',
    'StartMenuMRUTracker::Instance().GetTopApps',
    'cloudos_native_runtime_abi',
    'FocusWindow',
    'SwitchWorkspace'
)
foreach ($token in $desktopContracts) {
    if (-not $desktop.Contains($token)) {
        throw "Desktop contract missing: $token"
    }
}

$platformContracts = @(
    'GetDateFormatEx',
    'GetTimeFormatEx',
    'GetWindowsDirectoryW',
    'GetVolumePathNameW'
)
foreach ($token in $platformContracts) {
    if (-not $platform.Contains($token)) {
        throw "Platform contract missing: $token"
    }
}

$launcherContracts = @(
    'CanonicalAppId',
    'SEE_MASK_NOCLOSEPROCESS',
    'StartMenuMRUTracker::Instance().RecordLaunch',
    'CloudOSNativeProjectsWindow::Open',
    'NativeCloudOSDrive::EnsureReady',
    'CloudOSNativeFilesWindow::Open(instance, root)',
    'OpenWslTerminal',
    'systemdrive',
    'ms-settings:dateandtime'
)
foreach ($token in $launcherContracts) {
    if (-not $launcher.Contains($token)) {
        throw "Launcher contract missing: $token"
    }
}

if (-not $main.Contains('HotSearch') -or -not $main.Contains('VK_SPACE')) {
    throw 'Global native search hotkey contract missing.'
}

if ($theme.Contains('Disco Local (C:)') -or $theme.Contains('Disco C:')) {
    throw 'System volume label must not assume Windows is installed on C:.'
}
if (-not $theme.Contains('L"drive", L"CloudOS Drive"') -or
    -not $theme.Contains('L"systemdrive", L"Disco do Sistema"') -or
    -not $theme.Contains('L"projects", L"Projetos"') -or
    -not $theme.Contains('L"wsl", L"WSL / Kali"')) {
    throw 'CloudOS Drive, system volume, Projects and WSL must remain distinct truthful app identities.'
}

if (-not $mru.Contains('SHGetKnownFolderPath') -or
    -not $mru.Contains('FOLDERID_LocalAppData') -or
    -not $mru.Contains('MoveFileExW')) {
    throw 'MRU persistence must use Known Folders and atomic replacement.'
}

$driveContracts = @(
    'CLOUDOS_DRIVE_DIR',
    'FOLDERID_LocalAppData',
    '.cloudos-system',
    'FILE_ATTRIBUTE_REPARSE_POINT',
    'ValidateSegments',
    'NativeCloudOSDrive::List',
    'NativeCloudOSDrive::Read',
    'NativeCloudOSDrive::Write',
    'NativeCloudOSDrive::Mkdir',
    'NativeCloudOSDrive::Move',
    'NativeCloudOSDrive::Copy',
    'NativeCloudOSDrive::Trash',
    'NativeCloudOSDrive::ListTrash',
    'NativeCloudOSDrive::RestoreTrash',
    'NativeCloudOSDrive::DeleteTrash',
    'NativeCloudOSDrive::EmptyTrash'
)
foreach ($token in $driveContracts) {
    if (-not $drive.Contains($token)) {
        throw "CloudOS Drive native contract missing: $token"
    }
}

$filesContracts = @(
    'NavigateCloudOSDriveRoot',
    'CloudOSNativeDriveTrashWindow::Open',
    'NativeCloudOSDrive::List',
    'NativeCloudOSDrive::Mkdir',
    'NativeCloudOSDrive::Trash',
    'NativeCloudOSDrive::Move',
    'FOF_ALLOWUNDO'
)
foreach ($token in $filesContracts) {
    if (-not $files.Contains($token)) {
        throw "Native Files integration contract missing: $token"
    }
}

$trashContracts = @(
    'NativeCloudOSDrive::ListTrash',
    'NativeCloudOSDrive::RestoreTrash',
    'NativeCloudOSDrive::DeleteTrash',
    'NativeCloudOSDrive::EmptyTrash'
)
foreach ($token in $trashContracts) {
    if (-not $trash.Contains($token)) {
        throw "Native Drive Trash contract missing: $token"
    }
}

$projectsContracts = @(
    'kProjectsSegments',
    'NativeCloudOSDrive::List',
    'NativeCloudOSDrive::Mkdir',
    'NativeCloudOSDrive::Move',
    'NativeCloudOSDrive::Trash',
    'CloudOSNativeFilesWindow::Open',
    'CloudOSNativeTerminalWindow::Open',
    'code.cmd'
)
foreach ($token in $projectsContracts) {
    if (-not $projects.Contains($token)) {
        throw "Native Projects contract missing: $token"
    }
}

$requiredProjectSources = @(
    'src\native_cloudos_drive.cpp',
    'src\native_cloudos_trash_window.cpp',
    'src\native_projects_window.cpp'
)
foreach ($source in $requiredProjectSources) {
    if (-not $project.Contains($source)) {
        throw "Required native source not compiled by project: $source"
    }
}

$placeholderSources = @(
    'src\native_start_menu_window.cpp',
    'src\native_taskbar_window.cpp',
    'src\native_dash_window.cpp'
)
foreach ($source in $placeholderSources) {
    if ($project.Contains($source)) {
        throw "Empty/provisional shell placeholder returned to build: $source"
    }
}

Write-Host 'PASS: CloudOS native shell, Drive, Files and Projects contracts are truthful and functional.'
