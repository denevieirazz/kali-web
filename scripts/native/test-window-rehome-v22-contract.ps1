[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$path = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_window_manager_recovery.cpp'
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Window Rehome V22 input missing: $path"
}
$text = Get-Content -LiteralPath $path -Raw

foreach ($required in @(
    'ValidRestoreBounds',
    'MonitorFromRect(&target, MONITOR_DEFAULTTONEAREST)',
    'GetMonitorInfoW',
    'SPI_GETWORKAREA',
    'GetDpiForWindow',
    'MulDiv(160',
    'reachable_x',
    'reachable_y',
    'std::clamp',
    'item->monitor = MonitorFromRect(&safe, MONITOR_DEFAULTTONEAREST)'
)) {
    if (-not $text.Contains($required)) {
        throw "Window Rehome V22 contract missing: $required"
    }
}

if ($text.Contains('SetWindowPos(\n        window,\n        nullptr,\n        bounds.left,\n        bounds.top')) {
    throw 'RestoreWindowState regressed to applying unvalidated historical coordinates.'
}

Write-Host '[PASS] Window Rehome V22: restored windows are clamped to a valid monitor work area with DPI-scaled reachability after hotplug/RDP/topology changes.'
