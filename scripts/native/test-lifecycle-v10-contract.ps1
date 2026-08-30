$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'

$paths = @{
    Lifecycle = Join-Path $src 'native_lifecycle_v10.h'
    Recovery = Join-Path $src 'native_session_recovery.h'
    Watchdog = Join-Path $src 'native_watchdog.cpp'
    Smoke = Join-Path $root 'scripts\native\run-native-lifecycle-smoke-v10.ps1'
    Build = Join-Path $root 'scripts\native\build-cloudos-native.cmd'
    Package = Join-Path $root 'scripts\native\package-cloudos-native.ps1'
    Workflow = Join-Path $root '.github\workflows\cloudos-native-full-system.yml'
    Document = Join-Path $root 'docs\native\LIFECYCLE_V10.md'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Lifecycle V10 file missing [$($entry.Key)]: $($entry.Value)"
    }
}

$content = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

function Require([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) { throw "$Name contract missing: $token" }
    }
}

function Forbid([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if ($Text.Contains($token)) { throw "$Name forbidden regression found: $token" }
    }
}

Require 'Lifecycle primitives V10' $content.Lifecycle @(
    'CloudOS.NativeShell.Desktop.v2',
    'CloudOS.NativeShell.Taskbar.v4',
    '--lifecycle-probe',
    'PBT_APMRESUMEAUTOMATIC',
    'PBT_APMRESUMECRITICAL',
    'PBT_APMRESUMESUSPEND',
    'PBT_APMSUSPEND',
    'WtsRetryEveryTicks = 30u',
    'PostToCurrentProcessClass(TaskbarClass, WM_DISPLAYCHANGE',
    'WM_SETTINGCHANGE, SPI_SETWORKAREA',
    'ProbeSessionReconnectMessage'
)

Require 'Lifecycle coordinator V10' $content.Recovery @(
    '#include "native_lifecycle_v10.h"',
    'class LifecycleCoordinatorV10 final',
    'SetWinEventHook',
    'SetWindowSubclass',
    'NativeLifecycleV10::RetryTimerId',
    'NativeSessionEventsV7::Register(desktop_)',
    'NativeSessionEventsV7::ShouldCheckpoint',
    'NativeSessionEventsV7::ShouldRefresh',
    'NativeLifecycleV10::IsPowerSuspend',
    'NativeLifecycleV10::IsPowerResume',
    'message == WM_DISPLAYCHANGE || message == WM_DEVICECHANGE',
    'owner_->ApplyPending(*manager)',
    'NativeLifecycleV10::RevalidateShellSurfaces(desktop_)',
    'owner_->Save(*manager)',
    'ProbeSuspendMessage',
    'ProbeResumeMessage',
    'ProbeDisplayMessage',
    'ProbeSessionDisconnectMessage',
    'ProbeSessionReconnectMessage'
)

Require 'Single-instance invariant V10' $content.Watchdog @(
    'Local\\CloudOS.NativeShell.Session.v1',
    'AcquireSessionMutex',
    'SurfaceExistingShell',
    'CloudOS.NativeShell.Desktop.v2'
)

Require 'Lifecycle smoke V10' $content.Smoke @(
    "'--stability-probe', '--lifecycle-probe'",
    'SecondInstanceDidNotExit',
    'HealthProcessChanged',
    'ProbeSuspend',
    'ProbeResume',
    'ProbeDisplay',
    'ProbeSessionDisconnect',
    'ProbeSessionReconnect',
    'SessionCheckpointMissing',
    "test = 'CloudOS Lifecycle V10'",
    'Physical suspend/resume, RDP transport and monitor hotplug remain VM/hardware matrix tests.'
)

Forbid 'Lifecycle smoke privacy V10' $content.Smoke @(
    'MainWindowTitle',
    'Get-CimInstance',
    'Get-WmiObject',
    'Win32_Process',
    'CommandLine =',
    'DocumentPath'
)

Require 'Developer build V10' $content.Build @(
    'test-lifecycle-v10-contract.ps1',
    'LIFECYCLE_V10='
)

Require 'Portable package V10' $content.Package @(
    "'run-native-lifecycle-smoke-v10.ps1'",
    'Lifecycle V10:',
    'WTS/RDP lock/disconnect faz checkpoint',
    'matriz de VM/hardware'
)

Require 'Native CI V10' $content.Workflow @(
    'Smoke Lifecycle V10',
    'run-native-lifecycle-smoke-v10.ps1',
    'lifecycle-v10-smoke.json',
    'did not exercise all expected transition checks'
)

Require 'Lifecycle V10 documentation' $content.Document @(
    'PBT_APMRESUMEAUTOMATIC',
    'WTSRegisterSessionNotification',
    'nova tentativa de registro WTS a cada 30 ticks',
    'Single instance',
    'Matriz fisica de aceite',
    'RDP connect -> disconnect -> console reconnect',
    'nao uma alegacao de cobertura fisica'
)

Write-Host 'PASS: Lifecycle V10 contracts passed - suspend/resume revalidation, WTS retry, RDP/session checkpoints, display/AppBar refresh, single-instance and deterministic smoke are protected.'
