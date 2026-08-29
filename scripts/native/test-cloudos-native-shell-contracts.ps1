$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$desktopPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_desktop_window.cpp'
$launcherPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_app_launcher.cpp'
$mainPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\main.cpp'
$themePath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_theme.h'
$mruPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_start_menu_mru.h'
$platformPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\src\native_shell_platform.cpp'
$projectPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'

foreach ($path in @($desktopPath, $launcherPath, $mainPath, $themePath, $mruPath, $platformPath, $projectPath)) {
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

if (-not $mru.Contains('SHGetKnownFolderPath') -or
    -not $mru.Contains('FOLDERID_LocalAppData') -or
    -not $mru.Contains('MoveFileExW')) {
    throw 'MRU persistence must use Known Folders and atomic replacement.'
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

Write-Host 'PASS: CloudOS native shell contracts are truthful and functional.'
