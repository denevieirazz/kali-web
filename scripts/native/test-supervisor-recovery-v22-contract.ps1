[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$v11Path = Join-Path $root 'desktop\CloudOS.NativeRecovery\main.cpp'
$v22Path = Join-Path $root 'desktop\CloudOS.NativeRecovery\main_v22.cpp'
$projectPath = Join-Path $root 'desktop\CloudOS.NativeRecovery\CloudOS.NativeRecovery.vcxproj'

foreach ($path in @($v11Path, $v22Path, $projectPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Supervisor V22 contract input missing: $path"
    }
}

$v11 = Get-Content -LiteralPath $v11Path -Raw
$v22 = Get-Content -LiteralPath $v22Path -Raw
$project = Get-Content -LiteralPath $projectPath -Raw

# V22 is additive over the reviewed V11 heartbeat/recovery implementation.
foreach ($required in @(
    '#define wWinMain CloudOSLegacySupervisorMainV11',
    '#include "main.cpp"',
    'RunSupervisorV22',
    'SelfTestV22',
    'STARTING',
    'HEALTHY',
    'DEGRADED',
    'RESTARTING',
    'CRASH_LOOP',
    'SAFE_MODE',
    'STOPPING',
    'kV22CrashWindowMs = 60000ull',
    'supervisor-state-v22.json',
    'MoveFileExW',
    'MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH',
    'CreateJobObjectW',
    'JobObjectExtendedLimitInformation',
    'JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE',
    'AssignProcessToJobObject',
    'RecordFailureV22',
    'EnterSafeModeV22',
    'FallbackToExplorer(options.suppress_explorer)',
    'RestartBackoff(failure_count)',
    'WaitForReady',
    'MonitorShell',
    'StopHungProcess'
)) {
    if (-not $v22.Contains($required)) {
        throw "Supervisor V22 recovery contract missing: $required"
    }
}

# Never weaken V11 target/process identity or Explorer recovery safeguards.
foreach ($required in @(
    'IsAllowedTarget',
    'TokenSessionId',
    'EqualSid',
    'ExplorerShellPresent',
    'OpenWindowsExplorer',
    'RequestGracefulExit',
    'HeartbeatFresh'
)) {
    if (-not $v11.Contains($required)) {
        throw "Preserved Supervisor V11 safety primitive missing: $required"
    }
}

if ($project -notmatch '<ClCompile Include="main_v22\.cpp">' -or
    $project -notmatch '<TargetName>CloudOS\.Supervisor</TargetName>') {
    throw 'CloudOS.Supervisor must compile the V22 wrapper while preserving the binary identity.'
}
if ($project -match '<ClCompile Include="main\.cpp">') {
    throw 'main.cpp must not be compiled separately when main_v22.cpp includes it.'
}

foreach ($forbidden in @(
    'Winlogon',
    'HKEY_LOCAL_MACHINE',
    'RegSetValue',
    'SetParent(',
    'ShellExecuteW(nullptr, L"runas"'
)) {
    if ($v22.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Supervisor V22 introduced a forbidden authority mutation: $forbidden"
    }
}

Write-Host '[PASS] Supervisor/Recovery V22 contract: explicit states, rolling crash budget, atomic journal, kill-on-close Job Object, bounded restart and Explorer safe mode.'
