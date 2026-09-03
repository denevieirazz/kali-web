[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$v11Path = Join-Path $root 'desktop\CloudOS.NativeRecovery\main.cpp'
$v22Path = Join-Path $root 'desktop\CloudOS.NativeRecovery\main_v22.cpp'
$bootstrapPath = Join-Path $root 'desktop\CloudOS.NativeRecovery\supervisor_bootstrap_v22.h'
$projectPath = Join-Path $root 'desktop\CloudOS.NativeRecovery\CloudOS.NativeRecovery.vcxproj'
$smokePath = Join-Path $root 'scripts\native\run-native-supervisor-smoke-v22.ps1'
$packagePath = Join-Path $root 'scripts\native\package-cloudos-native.ps1'
$workflowPath = Join-Path $root '.github\workflows\cloudos-native-full-system.yml'

foreach ($path in @($v11Path, $v22Path, $bootstrapPath, $projectPath, $smokePath, $packagePath, $workflowPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Supervisor V22 contract input missing: $path"
    }
}

$v11 = Get-Content -LiteralPath $v11Path -Raw
$v22 = Get-Content -LiteralPath $v22Path -Raw
$bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw
$project = Get-Content -LiteralPath $projectPath -Raw
$smoke = Get-Content -LiteralPath $smokePath -Raw
$package = Get-Content -LiteralPath $packagePath -Raw
$workflow = Get-Content -LiteralPath $workflowPath -Raw

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

# Windows Application Restart is a servicing/reboot restoration mechanism only.
# Shell crash/hang supervision remains exclusively owned by Supervisor V22.
foreach ($required in @(
    'RegisterApplicationRestart',
    'RESTART_NO_CRASH | RESTART_NO_HANG',
    'UnregisterApplicationRestart',
    'SEM_FAILCRITICALERRORS',
    'SEM_NOGPFAULTERRORBOX',
    '--windows-restart',
    'Windows restart registration active'
)) {
    if (-not $bootstrap.Contains($required)) {
        throw "Supervisor V22 process bootstrap contract missing: $required"
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

foreach ($required in @(
    '<ClCompile Include="main_v22.cpp">',
    '<TargetName>CloudOS.Supervisor</TargetName>',
    '<ForcedIncludeFiles>supervisor_bootstrap_v22.h;%(ForcedIncludeFiles)</ForcedIncludeFiles>',
    '<ClInclude Include="supervisor_bootstrap_v22.h" />'
)) {
    if (-not $project.Contains($required)) {
        throw "CloudOS.Supervisor project V22 contract missing: $required"
    }
}
if ($project -match '<ClCompile Include="main\.cpp">') {
    throw 'main.cpp must not be compiled separately when main_v22.cpp includes it.'
}

foreach ($required in @(
    '--probe-ready-once',
    '--probe-failure-loop',
    "'SAFE_MODE'",
    'CrashBudgetNotExhausted',
    'remaining_installation_shell_processes',
    'get-cloudos-recovery-status-v22.ps1',
    "test = 'CloudOS Supervisor/Recovery V22'"
)) {
    if (-not $smoke.Contains($required)) {
        throw "Supervisor V22 runtime smoke contract missing: $required"
    }
}

foreach ($required in @(
    "'run-native-supervisor-smoke-v22.ps1'",
    "'get-cloudos-recovery-status-v22.ps1'",
    'CloudOS Supervisor V22',
    'Supervisor/Recovery V22:'
)) {
    if (-not $package.Contains($required)) {
        throw "Portable package V22 recovery contract missing: $required"
    }
}

foreach ($required in @(
    'Smoke Supervisor/Recovery V22',
    'run-native-supervisor-smoke-v22.ps1',
    'supervisor-v22-smoke.json'
)) {
    if (-not $workflow.Contains($required)) {
        throw "Native CI does not yet protect Supervisor V22 runtime: $required"
    }
}

foreach ($forbidden in @(
    'Winlogon',
    'HKEY_LOCAL_MACHINE',
    'RegSetValue',
    'SetParent(',
    'ShellExecuteW(nullptr, L"runas"'
)) {
    if ($v22.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $bootstrap.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Supervisor V22 introduced a forbidden authority mutation: $forbidden"
    }
}

Write-Host '[PASS] Supervisor/Recovery V22 contract: explicit states, rolling crash budget, atomic journal, kill-on-close Job Object, Windows servicing restart registration, runtime smoke and Explorer safe mode.'
