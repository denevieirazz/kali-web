$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'

$paths = @{
    HealthSignal = Join-Path $src 'native_health_signal_v9.h'
    HealthBootstrap = Join-Path $src 'native_health_bootstrap_v9.h'
    WatchdogHeader = Join-Path $src 'native_watchdog.h'
    Watchdog = Join-Path $src 'native_watchdog.cpp'
    HealthReader = Join-Path $root 'scripts\native\native-health-v9.ps1'
    Soak = Join-Path $root 'scripts\native\run-native-soak-v9.ps1'
    Diagnostics = Join-Path $root 'scripts\native\collect-native-diagnostics.ps1'
    Build = Join-Path $root 'scripts\native\build-cloudos-native.cmd'
    Package = Join-Path $root 'scripts\native\package-cloudos-native.ps1'
    Workflow = Join-Path $root '.github\workflows\cloudos-native-full-system.yml'
    Document = Join-Path $root 'docs\native\STABILITY_READINESS_V9.md'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Stability/Readiness V9 file missing [$($entry.Key)]: $($entry.Value)"
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

Require 'Health ABI V9' $content.HealthSignal @(
    'NativeHealthSnapshotV9',
    'static_assert(sizeof(NativeHealthSnapshotV9) == 96)',
    'Local\\CloudOS.NativeShell.Health.v9',
    'Local\\CloudOS.NativeShell.Ready.v9',
    '0x39484F43u',
    'InterlockedIncrement64',
    'MemoryBarrier',
    'GetGuiResources(process, GR_GDIOBJECTS)',
    'GetGuiResources(process, GR_USEROBJECTS)',
    'GetProcessHandleCount',
    'heartbeat_tick_ms',
    'heartbeat_count'
)

Require 'UI heartbeat bootstrap V9' $content.HealthBootstrap @(
    'SetWinEventHook',
    'EVENT_OBJECT_SHOW',
    'SetWindowSubclass',
    'WM_TIMER',
    'HealthIntervalMilliseconds = 1000',
    'AttachAfterInitialization()',
    'TryAttach(FindWindowW(DesktopClass, nullptr))',
    'RequiredShellSurfacesExist',
    'consecutive_ready_checks_ >= 2',
    'signal_.MarkReady',
    'signal_.MarkShuttingDown',
    'CloudOS.NativeShell.Taskbar.v4',
    'CloudOS.NativeShell.Start.v4',
    'CloudOS.NativeShell.QuickSettings.v4',
    'CloudOS.NativeShell.NotificationCenter.v2'
)

Require 'Watchdog integration V9' $content.WatchdogHeader @(
    '#include "native_health_bootstrap_v9.h"',
    '--stability-probe'
)
Require 'Probe watchdog bypass V9' $content.Watchdog @(
    'HealthBootstrapV9::bootstrap.AttachAfterInitialization()',
    'kStabilityProbeArgument[] = L"--stability-probe"',
    'if (HasArgument(kStabilityProbeArgument))',
    'Stability/soak runs must observe the original process directly.'
)

Require 'Health reader V9' $content.HealthReader @(
    'MemoryMappedFile]::OpenExisting',
    'MemoryMappedFileRights]::Read',
    'sequence1',
    'sequence2',
    'CloudOS health V9 shared-memory ABI mismatch',
    'Wait-CloudOSReadyV9',
    'Test-CloudOSHeartbeatFreshV9'
)

Require 'Automated soak V9' $content.Soak @(
    "--stability-probe",
    'Wait-CloudOSReadyV9',
    'Test-CloudOSHeartbeatFreshV9',
    'WindowNotResponding',
    'UiHeartbeatStale',
    'WorkingSetGrowthBudgetExceeded',
    'PrivateBytesGrowthBudgetExceeded',
    'HandleGrowthBudgetExceeded',
    'GdiGrowthBudgetExceeded',
    'UserGrowthBudgetExceeded',
    'ThreadGrowthBudgetExceeded',
    'AverageCpuBudgetExceeded',
    'No window titles, filenames, command lines, URLs, credentials, session contents, dumps or uploads.'
)

Forbid 'Automated soak V9 privacy' $content.Soak @(
    'MainWindowTitle',
    'Win32_Process',
    'Get-CimInstance',
    'Get-WmiObject',
    'CommandLine ='
)

Require 'Diagnostics V9' $content.Diagnostics @(
    'native-health-v9.ps1',
    'Get-CloudOSHealthSnapshotV9',
    'health_state',
    'heartbeat_count',
    'gdi_objects',
    'user_objects',
    'health_handles'
)

Require 'Developer build V9 contract' $content.Build @(
    'test-stability-readiness-v9-contract.ps1',
    'STABILITY_READINESS_V9='
)

Require 'Portable package V9' $content.Package @(
    "'native-health-v9.ps1'",
    "'collect-native-diagnostics.ps1'",
    "'run-native-soak-v9.ps1'",
    'Coletar Diagnostico 60s.cmd',
    'Stability/Readiness V9'
)

Require 'Native CI V9' $content.Workflow @(
    'Smoke Stability/Readiness V9',
    'run-native-soak-v9.ps1',
    '-DurationSeconds 20',
    'stability-v9-smoke.json'
)

Require 'V9 documentation' $content.Document @(
    'ABI binario fixo de 96 bytes',
    'heartbeat da thread de UI',
    '--stability-probe',
    'DurationSeconds 86400',
    'criterio de aceite, nao uma alegacao'
)

Write-Host 'PASS: Stability/Readiness V9 contracts passed - fixed health ABI, deterministic post-initialize UI heartbeat, automated soak, local diagnostics, portable tooling and CI smoke are protected.'
