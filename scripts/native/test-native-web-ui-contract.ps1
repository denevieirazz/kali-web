$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$paths = @{
    Main = Join-Path $root 'desktop\CloudOS.NativeShell\src\main.cpp'
    Surface = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_desktop_surface.cpp'
    WebDesktop = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_web_desktop_window.cpp'
    WebHost = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_webview_host.cpp'
    Project = Join-Path $root 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
    Packages = Join-Path $root 'desktop\CloudOS.NativeShell\packages.config'
    FrontendMain = Join-Path $root 'frontend\src\main.tsx'
    Bridge = Join-Path $root 'frontend\src\native-shell\nativeBridge.ts'
    ReactSurface = Join-Path $root 'frontend\src\native-shell\NativeShellSurface.tsx'
    Css = Join-Path $root 'frontend\src\native-shell\NativeShellSurface.css'
    Research = Join-Path $root 'docs\native\research\NATIVE_WEB_UI_RESEARCH.md'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Hybrid native/web UI contract file missing: $($entry.Value)"
    }
}

$content = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

foreach ($token in @('CloudOSDesktopSurface desktop_','ICC_LISTVIEW_CLASSES','ICC_WIN95_CLASSES','CloudOSNativeWindowManager')) {
    if (-not $content.Main.Contains($token)) { throw "Main native authority contract missing: $token" }
}
foreach ($token in @('web_.Create','fallback_.Create','web_.SetActionCallback','fallback_.SetActionCallback')) {
    if (-not $content.Surface.Contains($token)) { throw "Desktop fallback facade contract missing: $token" }
}
foreach ($token in @('SetVirtualHostNameToFolderMapping','https://cloudos.local','add_WebMessageReceived','get_Source','TryGetWebMessageAsString','add_NavigationStarting','PostWebMessageAsJson','COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS')) {
    if (-not $content.WebHost.Contains($token)) { throw "WebView2 presentation host contract missing: $token" }
}
if ($content.WebHost.Contains('AddHostObjectToScript')) { throw 'Generic WebView2 host objects are forbidden.' }

foreach ($token in @('CurrentWorkspaceWindows','NativeSystemStats::Query','app.launch:','window.focus:','workspace.switch:','tiling.toggle','CLOUDOS_WM_NATIVE_WINDOW_EVENT')) {
    if (-not $content.WebDesktop.Contains($token)) { throw "Native bridge authority contract missing: $token" }
}
if ($content.WebDesktop.Contains('ShellExecute') -or $content.WebDesktop.Contains('CreateProcess')) {
    throw 'Presentation surface must delegate launches to C++ callbacks.'
}

foreach ($token in @('isNativeShellWebView','NativeShellSurface','await import(''./App'')','nativeSurface')) {
    if (-not $content.FrontendMain.Contains($token)) { throw "Conditional native UI bootstrap contract missing: $token" }
}
if ($content.FrontendMain.Contains("import App from './App'")) {
    throw 'Legacy App must be lazy-loaded so its runtime is not evaluated inside the native WebView2 surface.'
}

foreach ($token in @('postMessage','subscribeNativeShell','sendNativeCommand','state.request','cloudos.state')) {
    if (-not $content.Bridge.Contains($token)) { throw "Narrow web bridge contract missing: $token" }
}
foreach ($forbidden in @('/api','WebSocket','useProcessManager','useWindowManager','useFileSystem','kernel.','exec(')) {
    if ($content.Bridge.Contains($forbidden)) { throw "Native bridge restored forbidden legacy authority: $forbidden" }
}

foreach ($token in @('DESKTOP_IDS','app.launch:','window.focus:','workspace.switch:','tiling.toggle','NativeShellState','HWNDs reais','native-launchpad')) {
    if (-not $content.ReactSurface.Contains($token)) { throw "React presentation contract missing: $token" }
}
foreach ($forbidden in @('useProcessManager','useWindowManager','useFileSystem','useRegistry','useUserStore','/api','WebSocket')) {
    if ($content.ReactSurface.Contains($forbidden)) { throw "React presentation restored forbidden legacy authority: $forbidden" }
}
foreach ($token in @('backdrop-filter','native-launchpad','native-dock','native-menubar','native-status-card')) {
    if (-not $content.Css.Contains($token)) { throw "Modern native web UI visual contract missing: $token" }
}

if (-not $content.Packages.Contains('Microsoft.Web.WebView2') -or -not $content.Packages.Contains('1.0.4078.44')) {
    throw 'Pinned Microsoft.Web.WebView2 package is missing.'
}
foreach ($token in @('WebView2LoaderPreference','Static','Microsoft.Web.WebView2','CopyWebUi','native_desktop_surface.cpp','native_web_desktop_window.cpp','native_webview_host.cpp')) {
    if (-not $content.Project.Contains($token)) { throw "Native WebView2 build contract missing: $token" }
}
foreach ($token in @('SetVirtualHostNameToFolderMapping','WebMessageReceived','PostWebMessageAsJson','Evergreen','WebView2Samples','autoridade','fallback','frontend/src/index.css')) {
    if (-not $content.Research.Contains($token)) { throw "Research record missing: $token" }
}

Write-Host 'PASS: WebView2 is presentation-only; C++/Win32 remains CloudOS authority and the GDI desktop remains a fallback.'
