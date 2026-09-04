[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$supervisorPath = Join-Path $root 'desktop\CloudOS.NativeRecovery\main_v22.cpp'
$launcherPath = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_app_launcher_v3.cpp'
$suitePath = Join-Path $root 'scripts\native\test-native-contract-suite.ps1'

foreach ($path in @($supervisorPath, $launcherPath, $suitePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "External App Breakaway V22 contract input missing: $path"
    }
}

$supervisor = Get-Content -LiteralPath $supervisorPath -Raw
$launcher = Get-Content -LiteralPath $launcherPath -Raw
$suite = Get-Content -LiteralPath $suitePath -Raw

foreach ($required in @(
    'CREATE_SUSPENDED | CREATE_DEFAULT_ERROR_MODE',
    'AssignShellToJobV22(job, process.hProcess)',
    'ResumeThread(process.hThread)',
    'JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE',
    'JOB_OBJECT_LIMIT_BREAKAWAY_OK',
    'QueryInformationJobObject',
    'job_breakaway_enabled'
)) {
    if (-not $supervisor.Contains($required)) {
        throw "Supervisor Job policy V22 contract missing: $required"
    }
}

foreach ($required in @(
    'LaunchExternalBreakawayProcess',
    'CREATE_BREAKAWAY_FROM_JOB | CREATE_DEFAULT_ERROR_MODE',
    'HasProtocolScheme',
    'ShellExecuteExW',
    'Internal CloudOS apps never pass through this function.',
    'code.cmd',
    'mspaint.exe',
    'SnippingTool.exe',
    'regedit.exe',
    'ms-settings:'
)) {
    if (-not $launcher.Contains($required)) {
        throw "External app launcher V22 contract missing: $required"
    }
}

# Silent breakaway would detach every descendant, defeating process-tree
# supervision. Only explicitly classified external targets may escape.
if ($supervisor.Contains('JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK')) {
    throw 'Supervisor must not silently break away every child process.'
}

# Internal first-party apps must remain direct CloudOS window calls rather than
# being converted into external process launches.
foreach ($required in @(
    'CloudOSNativeTerminalWindow::Open',
    'CloudOSNativeFilesWindow::Open',
    'CloudOSNativeBrowserWindow::Open',
    'CloudOSNativeSettingsWindow::Open',
    'CloudOSNativeSystemMonitorWindow::Open'
)) {
    if (-not $launcher.Contains($required)) {
        throw "Internal app boundary regressed: $required"
    }
}

if (-not $suite.Contains('test-external-app-breakaway-v22-contract.ps1')) {
    throw 'Central native suite must protect External App Breakaway V22.'
}

Write-Host '[PASS] External App Breakaway V22: CloudOS tree is supervised, explicitly classified Win32 apps can escape, first-party apps stay internal.'
