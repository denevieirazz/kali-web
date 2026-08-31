$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$src=Join-Path $root 'desktop/CloudOS.NativeShell/src'
function Read([string]$name){Get-Content -LiteralPath (Join-Path $src $name) -Raw}
function Require([string]$text,[string[]]$tokens){foreach($token in $tokens){if(-not $text.Contains($token)){throw "V12 missing: $token"}}}
function Forbid([string]$text,[string[]]$tokens){foreach($token in $tokens){if($text.Contains($token)){throw "V12 forbidden: $token"}}}
function Body([string]$text,[string]$signature){
    $start=$text.IndexOf($signature); if($start -lt 0){throw "Missing function $signature"}
    $start=$text.IndexOf('{',$start);$depth=1;$end=$start+1
    while($depth -and $end -lt $text.Length){if($text[$end] -eq '{'){$depth++};if($text[$end] -eq '}'){$depth--};$end++}
    if($depth){throw "Unbalanced function $signature"};$text.Substring($start,$end-$start)
}
foreach($file in @('native_desktop_window_v2.cpp','native_taskbar_appbar_v4.cpp','native_start_menu_window.cpp')){
    $paint=Body (Read $file) '::Paint()'
    Require $paint @('NativeBackbufferV12::Acquire','PerformanceV12::PaintScope','paint.rcPaint')
    Forbid $paint @('SHGetFileInfo','directory_iterator','RefreshAsync','NativeSystemStats::Query','NativeMonitorManager::Enumerate','CreateCompatibleBitmap','GetSystemPowerStatus')
}
$main=Read 'main_shell_v2.cpp'
Require $main @('CLOUDOS_WM_MODEL_CHANGED_V12','view_update_pending_','recovery_dirty_','--stability-probe')
Forbid $main @('SetTimer(desktop_.Hwnd(), kReconcileTimer, 1000','SetTimer(desktop_.Hwnd(), kMetricsTimer','start_menu_.ToggleNear(taskbars_.front()->Bounds())')
Require (Read 'native_desktop_model_v12.h') @('ReadDirectoryChangesW','FILE_FLAG_OVERLAPPED','CancelIoEx','GetOverlappedResult','worker_.join()')
Require (Read 'native_icon_cache_v12.h') @('SHGetFileInfoW','std::thread','CopyIcon','DestroyIcon','entries_.size() >= 512')
Require (Read 'native_render_cache_v12.h') @('WM_NCDESTROY','RemoveWindowSubclass','DeleteObject(bitmap_)','width_ != width','dpi_ != dpi')
Require (Read 'native_design_system_v12.h') @('TaskbarHeight=52','StartWidth=640','StartHeight=680','QuickWidth=420','AnimationInterval=16')
Require (Read 'native_quick_settings_window_v4.cpp') @('!IsWindowVisible(window_)','model_v12_.Action','scroll_v12_.Update','KillTimer(window_, kRefreshTimer)')
Forbid (Read 'native_control_plane_service.cpp') @('::ScanWifi','::QueryBrightness')
Forbid (Read 'native_cloudos_tray.cpp') @('SetTimer(window_, kAttachTimer')
Forbid (Read 'native_start_menu_window.cpp') @('SetTimer(window_, kIndexTimer')
Forbid (Read 'native_quick_settings_media_v8.h') @('SetTimer(panel, RefreshTimerId','SetTimer(window, RefreshTimerId','inline Bootstrap bootstrap;')
Forbid (Body (Read 'native_quick_settings_media_v8.h') 'inline void PaintPanel') @('CreateStreamOnHGlobal','CreateCompatibleBitmap')
Require (Read 'native_performance_v12.h') @('InterlockedExchangeAdd64','IconLoadInPaint','FilesystemScan','paint_total_us','paint_max_us','CreateFileMappingW')
Write-Host 'PASS: V12 event-driven shell, cached paint, bounded icons, asynchronous controls, numeric telemetry and responsive design contracts.'

Forbid (Body (Read 'native_workspace_automation.cpp') 'void NativeWorkspaceAutomationEngine::Tick') @('Reconcile(')
Forbid (Body (Read 'native_session_continuity_service.cpp') 'void NativeSessionContinuityService::Tick') @('Reconcile(')
Forbid (Read 'native_workspace_studio_service.cpp') @('SetTimer(engine_window_, kEngineTimer')
