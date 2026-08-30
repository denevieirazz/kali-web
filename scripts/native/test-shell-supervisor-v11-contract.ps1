$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$paths = @{
    Protocol = Join-Path $root 'desktop\CloudOS.NativeCommon\native_supervisor_protocol_v11.h'
    Supervisor = Join-Path $root 'desktop\CloudOS.NativeRecovery\main.cpp'
    Project = Join-Path $root 'desktop\CloudOS.NativeRecovery\CloudOS.NativeRecovery.vcxproj'
    Watchdog = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_watchdog.cpp'
    Health = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_health_bootstrap_v9.h'
    Build = Join-Path $root 'scripts\native\build-cloudos-native.cmd'
    Fingerprint = Join-Path $root 'scripts\native\get-native-build-fingerprint.ps1'
    Manifest = Join-Path $root 'scripts\native\write-native-build-manifest.ps1'
    Verify = Join-Path $root 'scripts\native\verify-native-build-manifest.ps1'
    Package = Join-Path $root 'scripts\native\package-cloudos-native.ps1'
    Smoke = Join-Path $root 'scripts\native\run-native-supervisor-smoke-v11.ps1'
    Workflow = Join-Path $root '.github\workflows\cloudos-native-full-system.yml'
    Document = Join-Path $root 'docs\native\SHELL_SUPERVISOR_V11.md'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Supervisor V11 file missing [$($entry.Key)]: $($entry.Value)"
    }
}
$content = @{}
foreach ($entry in $paths.GetEnumerator()) { $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw }

function Require([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) { throw "$Name contract missing: $token" }
    }
}

Require 'Shared Supervisor V11 protocol' $content.Protocol @(
    'SupervisedArgument[] = L"--supervised"',
    'ProbeFailureArgument[] = L"--supervisor-probe-fail"',
    'Local\\CloudOS.NativeShell.Supervisor.v11',
    'Local\\CloudOS.NativeShell.Health.v9',
    'CloudOS.NativeShell.Desktop.v2',
    'Shell_TrayWnd',
    'RequestGracefulExitMessage = WM_APP + 0x5B1',
    'static_assert(sizeof(NativeHealthSnapshotV9) == HealthStructureSize)'
)

Require 'External Supervisor V11 runtime' $content.Supervisor @(
    'kDefaultReadyTimeoutMs = 30000u',
    'kDefaultHeartbeatTimeoutMs = 5000u',
    'kDefaultMaximumFailures = 3u',
    'RunSupervisor',
    'WaitForReady',
    'MonitorShell',
    'HeartbeatFresh',
    'RequestGracefulExit',
    'StopHungProcess',
    'RestartBackoff',
    'FallbackToExplorer',
    'ExplorerShellPresent',
    'GetWindowsDirectoryW',
    'CreateProcessW',
    'IsAllowedTarget',
    'TokenSessionId',
    'EqualSid',
    '--probe-ready-once',
    '--probe-failure-loop',
    '--probe-no-explorer',
    '--recovery-ui'
)

Require 'Supervisor V11 build identity' $content.Project @(
    '<TargetName>CloudOS.Supervisor</TargetName>',
    '<TreatWarningAsError>true</TreatWarningAsError>',
    '..\CloudOS.NativeShell\bin\$(Configuration)\'
)

Require 'Supervised shell recovery ownership' $content.Watchdog @(
    'SupervisorProtocolV11::SupervisedArgument',
    'SupervisorProtocolV11::ProbeFailureArgument',
    'return static_cast<int>(0xC0000001u);',
    'HealthBootstrapV9::bootstrap.AttachAfterInitialization();'
)

Require 'Graceful supervisor shutdown protocol' $content.Health @(
    'SupervisorProtocolV11::RequestGracefulExitMessage',
    'signal_.MarkShuttingDown(window);',
    'PostQuitMessage(0);'
)

Require 'Native build integrates Supervisor V11' $content.Build @(
    'test-shell-supervisor-v11-contract.ps1',
    'CloudOS.NativeRecovery\\CloudOS.NativeRecovery.vcxproj',
    'CloudOS.Supervisor.exe',
    'SHELL_SUPERVISOR_V11='
)
Require 'Fingerprint covers shared protocol' $content.Fingerprint @(
    'desktop\\CloudOS.NativeCommon',
    'desktop\\CloudOS.NativeRecovery'
)
Require 'Manifest covers Supervisor V11' $content.Manifest @('CloudOS.Supervisor.exe')
Require 'Integrity verifier covers Supervisor V11' $content.Verify @('CloudOS.Supervisor.exe')
Require 'Portable package launches Supervisor V11' $content.Package @(
    "'CloudOS.Supervisor.exe'",
    'CloudOS.Supervisor.exe"',
    '--recovery-ui',
    'Shell Supervisor V11'
)
Require 'Supervisor V11 smoke' $content.Smoke @(
    '--self-test',
    '--probe-ready-once',
    '--probe-failure-loop',
    '--probe-no-explorer',
    'health_mapping_released_after_ready_probe',
    'remaining_installation_shell_processes'
)
Require 'Native CI runs Supervisor V11 smoke' $content.Workflow @(
    'Smoke Shell Supervisor V11',
    'run-native-supervisor-smoke-v11.ps1',
    'supervisor-v11-smoke.json'
)
Require 'Supervisor V11 documentation' $content.Document @(
    '30 segundos',
    'heartbeat',
    'crash-loop',
    'Explorer',
    'nao altera o registro',
    'CloudOS.Supervisor.exe'
)

Write-Host 'PASS: Shell Supervisor V11 contracts passed - external readiness/heartbeat authority, bounded restart policy, graceful exit, safe Explorer fallback, portable packaging and runtime CI smoke are protected.'
