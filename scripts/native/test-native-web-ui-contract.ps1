$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$paths = @{
    Main = Join-Path $root 'desktop\CloudOS.NativeShell\src\main_shell_v2.cpp'
    Surface = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_desktop_surface.cpp'
    SurfaceHeader = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_desktop_surface.h'
    Desktop = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_desktop_window_v2.cpp'
    Start = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_start_menu_window.cpp'
    Taskbar = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_taskbar_appbar_v4.cpp'
    Pins = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_shell_pins.cpp'
    Theme = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_theme.h'
    Browser = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_browser_window.cpp'
    Project = Join-Path $root 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
    Packages = Join-Path $root 'desktop\CloudOS.NativeShell\packages.config'
    FrontendCss = Join-Path $root 'frontend\src\index.css'
    StartCss = Join-Path $root 'frontend\src\components\StartMenu\StartMenu.css'
    TaskbarCss = Join-Path $root 'frontend\src\components\Taskbar\Taskbar.css'
    WebSkinDoc = Join-Path $root 'docs\native\UNIFIED_WEBSKIN_NATIVE.md'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Native WebSkin contract file missing: $($entry.Value)"
    }
}

$content = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

function Require-Tokens([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) {
            throw "$Name contract missing: $token"
        }
    }
}

function Forbid-Tokens([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if ($Text.Contains($token)) {
            throw "$Name forbidden hybrid regression found: $token"
        }
    }
}

Require-Tokens 'Main native authority' $content.Main @(
    'CloudOSDesktopSurface desktop_',
    'CloudOSNativeWindowManager window_manager_',
    'CloudOSNativeStartMenuWindow start_menu_',
    'CloudOSTaskbarAppBar',
    'NativeSnapAssist snap_assist_',
    'NativeSessionRecovery session_recovery_'
)
Require-Tokens 'Native desktop facade' $content.Surface @(
    'return native_.Create(instance, window_manager)',
    'native_.UpdateLayout(work_area)',
    'native_.SetActionCallback',
    'native_.SetHotKeyCallback',
    'native_.SetTimerCallback'
)
Forbid-Tokens 'Native desktop facade' $content.Surface @(
    'web_.Create', 'fallback_.Create', 'web_.SetActionCallback', 'fallback_.SetActionCallback'
)
Require-Tokens 'Native desktop facade header' $content.SurfaceHeader @(
    'CloudOSNativeDesktopWindow native_',
    'UsingWebUi() const noexcept { return false; }'
)
Forbid-Tokens 'Native desktop facade header' $content.SurfaceHeader @(
    'CloudOSNativeWebDesktopWindow', 'NativeWebViewHost'
)

Require-Tokens 'Native build graph' $content.Project @(
    'src\main_shell_v2.cpp',
    'src\native_desktop_surface.cpp',
    'src\native_desktop_window_v2.cpp',
    'src\native_start_menu_window.cpp',
    'src\native_taskbar_appbar_v4.cpp',
    'src\native_shell_pins.cpp',
    'src\native_browser_window.cpp',
    'Microsoft.Web.WebView2'
)
Forbid-Tokens 'Native build graph' $content.Project @(
    '<ClCompile Include="src\native_taskbar_appbar.cpp"',
    '<ClCompile Include="src\native_web_desktop_window.cpp"',
    '<ClCompile Include="src\native_webview_host.cpp"',
    '<ClInclude Include="src\native_web_desktop_window.h"',
    '<ClInclude Include="src\native_webview_host.h"',
    'CopyWebUi'
)

Require-Tokens 'Native WebView2 Browser' $content.Browser @(
    'CreateCoreWebView2EnvironmentWithOptions',
    'CreateCoreWebView2Controller',
    'NavigationCompleted',
    'HistoryChanged',
    'BrowserProfile'
)
if (-not $content.Packages.Contains('Microsoft.Web.WebView2') -or
    -not $content.Packages.Contains('1.0.4078.44')) {
    throw 'Pinned Microsoft.Web.WebView2 package for the native Browser is missing.'
}

Require-Tokens 'Unified native WebSkin' $content.Theme @(
    'namespace WebSkin',
    'RGB(10, 10, 15)',
    'RGB(17, 17, 24)',
    'RGB(26, 26, 36)',
    'RGB(99, 102, 241)',
    'RGB(129, 140, 248)',
    'DrawRoundedPanel',
    'PaintOwnerDrawButton',
    'WindowSkinSubclass',
    'ApplyWebFlyoutMaterial',
    'ApplyWebWindowMaterial'
)
Require-Tokens 'Native Start V4 skin/functionality' $content.Start @(
    'CloudOS.NativeShell.Start.v4',
    'L"Fixados"',
    'L"Recomendados"',
    'ApplyWebFlyoutMaterial',
    'BS_OWNERDRAW',
    'NM_CUSTOMDRAW',
    'ShellPinStore::Instance().StartPins()',
    'ShowResultContextMenu',
    'WebSkin::Accent'
)
Require-Tokens 'Native Taskbar V4 skin/functionality' $content.Taskbar @(
    'CloudOS.NativeShell.Taskbar.v4',
    'SHAppBarMessage(ABM_NEW',
    'kTaskbarHeightDip = 68',
    'ShellPinStore::Instance().TaskbarPins()',
    'TaskGroup',
    'ShowTaskContextMenu',
    'ShowTaskOverflowMenu',
    'MoveTaskbar',
    'DrawStartGlyph',
    'DrawQuickGlyph',
    'WebSkin::BgPrimary',
    'WebSkin::Accent'
)
Require-Tokens 'Persistent pin model' $content.Pins @(
    'shell_pins_v1.dat',
    'MOVEFILE_REPLACE_EXISTING',
    'MoveStart',
    'MoveTaskbar'
)
Require-Tokens 'Native Desktop skin' $content.Desktop @(
    'CloudOS.NativeShell.Desktop.v2',
    'WebSkin::BgPrimary',
    'NativeWallpaperManager::Draw',
    'NativeDesktopDropTarget::Register'
)

# The old frontend remains only a design specification for the native surfaces.
Require-Tokens 'Legacy CSS design reference' $content.FrontendCss @(
    '--accent: #6366f1',
    '--bg-solid: #0a0a0f',
    '--bg-primary: #111118',
    '--bg-secondary: #1a1a24',
    '--radius-xl: 16px',
    '--shadow-flyout'
)
Require-Tokens 'Legacy Start design reference' $content.StartCss @(
    '.start-menu', '.start-search', '.start-pinned-grid', '.start-bottom'
)
Require-Tokens 'Legacy Taskbar design reference' $content.TaskbarCss @(
    '.taskbar', '.taskbar-app-btn', '.system-tray', '.taskbar-clock'
)
Require-Tokens 'Unified WebSkin documentation' $content.WebSkinDoc @(
    'Funcionalidade e lifecycle ficam nativos',
    'frontend antigo funciona apenas como especificação visual',
    'WindowSkinSubclass',
    'não volta a controlar Desktop, Taskbar, Start'
)

Write-Host 'PASS: old web UI remains design-reference-only; Start V4 and Taskbar V4 are native, persistent and WebSkin-styled; WebView2 stays scoped to Browser.'
