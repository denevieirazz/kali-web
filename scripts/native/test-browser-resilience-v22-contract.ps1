[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$cppPath = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_browser_window.cpp'
$headerPath = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_browser_window.h'
$manifestPath = Join-Path $root 'desktop\CloudOS.NativeShell\app.manifest'

foreach ($path in @($cppPath, $headerPath, $manifestPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Browser Resilience V22 input missing: $path"
    }
}

$cpp = Get-Content -LiteralPath $cppPath -Raw
$header = Get-Content -LiteralPath $headerPath -Raw
$manifest = Get-Content -LiteralPath $manifestPath -Raw

foreach ($required in @(
    'add_ProcessFailed',
    'remove_ProcessFailed',
    'COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED',
    'COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_UNRESPONSIVE',
    'COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED',
    'ScheduleWebViewRecovery',
    'kMaximumRecoveryAttempts',
    'add_PermissionRequested',
    'get_IsUserInitiated',
    'COREWEBVIEW2_PERMISSION_STATE_DENY',
    'COREWEBVIEW2_PERMISSION_STATE_ALLOW',
    'add_NewWindowRequested',
    'put_Handled(TRUE)',
    'Popup com protocolo externo bloqueado',
    'WM_DPICHANGED',
    'COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC'
)) {
    if (-not $cpp.Contains($required)) {
        throw "Browser Resilience V22 implementation missing: $required"
    }
}

foreach ($required in @(
    'process_failed_registered_',
    'permission_requested_registered_',
    'new_window_requested_registered_',
    'recovery_attempts_',
    'ResetWebView() noexcept'
)) {
    if (-not $header.Contains($required)) {
        throw "Browser Resilience V22 state contract missing: $required"
    }
}

if (-not $manifest.Contains('PerMonitorV2')) {
    throw 'CloudOS shell must remain PerMonitorV2 DPI aware.'
}

foreach ($forbidden in @(
    'ShellExecuteW(nullptr, L"open", uri',
    'put_State(COREWEBVIEW2_PERMISSION_STATE_ALLOW); // default',
    'COREWEBVIEW2_PERMISSION_STATE_ALLOW); // allow all'
)) {
    if ($cpp.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Browser Resilience V22 unsafe regression: $forbidden"
    }
}

Write-Host '[PASS] Browser Resilience V22: ProcessFailed recovery, bounded retry, explicit web permission policy, internal popup routing and PerMonitorV2 resize are protected.'
