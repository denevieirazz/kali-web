$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$paths = @{
    Protocol = Join-Path $root 'desktop\CloudOS.NativeCommon\native_supervisor_protocol_v11.h'
    SupervisorV11 = Join-Path $root 'desktop\CloudOS.NativeRecovery\main.cpp'
    SupervisorV22 = Join-Path $root 'desktop\CloudOS.NativeRecovery\main_v22.cpp'
    Project = Join-Path $root 'desktop\CloudOS.NativeRecovery\CloudOS.NativeRecovery.vcxproj'
    Watchdog = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_watchdog.cpp'
    Health = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_health_bootstrap_v9.h'
    Build = Join-Path $root 'scripts\native\build-cloudos-native.cmd'
    ContractSuite = Join-Path $root 'scripts\native\test-native-contract-suite.ps1'
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
        throw "Supervisor compatibility file missing [$($entry.Key)]: $($entry.Value)"
    }
}
$content = @{}
foreach ($entry in $paths.GetEnumerator()) { $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw }

function Require([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) { throw "$Name contract missing: $token" }
    }
}

# V11 is now the stable protocol/ABI that V22 extends. Do not confuse the
# compatibility level with the compiled runtime generation.
Require 'Shared Supervisor V11 protocol ABI' $content.Protocol @(
    'SupervisedArgument[] = L"--supervised"',
    'ProbeFailureArgument[] = L"--supervisor-probe-fail"',
    'Local\\CloudOS.NativeShell.Supervisor.v11',
    'Local\\CloudOS.NativeShell.Health.v9',
    'CloudOS.NativeShell.Desktop.v2',
    'Shell_TrayWnd',
    'RequestGracefulExitMessage = WM_APP + 0x5B1',
    'static_assert(sizeof(NativeHealthSnapshotV9) == HealthStructureSize)'
)

Require 'Preserved Supervisor V11 primitives' $content.SupervisorV11 @(
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

Require 'Supervisor V22 wraps reviewed V11 implementation' $content.SupervisorV22 @(
    '#define wWinMain CloudOSLegacySupervisorMainV11',
    '#include "main.cpp"',
    'RunSupervisorV22',
    'STARTING',
    'HEALTHY',
    'CRASH_LOOP',
    'SAFE_MODE'
)

Require 'Supervisor binary identity' $content.Project @(
    '<TargetName>CloudOS.Supervisor</TargetName>',
    '<TreatWarningAsError>true</TreatWarningAsError>',
    '..\CloudOS.NativeShell\bin\$(Configuration)\',
    '<ClCompile Include="main_v22.cpp">'
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

Require 'Native build integrates Supervisor compatibility' $content.Build @(
    'test-native-contract-suite.ps1',
    'CloudOS.NativeRecovery\CloudOS.NativeRecovery.vcxproj',
    'CloudOS.Supervisor.exe'
)
Require 'Central contract suite contains V11 compatibility' $content.ContractSuite @('test-shell-supervisor-v11-contract.ps1')
Require 'Fingerprint covers shared protocol' $content.Fingerprint @(
    'desktop\CloudOS.NativeCommon',
    'desktop\CloudOS.NativeRecovery'
)
Require 'Manifest covers Supervisor binary' $content.Manifest @('CloudOS.Supervisor.exe')
Require 'Integrity verifier covers Supervisor binary' $content.Verify @('CloudOS.Supervisor.exe')
Require 'Portable package launches current Supervisor with V11 ABI compatibility' $content.Package @(
    "'CloudOS.Supervisor.exe'",
    'CloudOS.Supervisor.exe"',
    '--recovery-ui',
    'Supervisor V22',
    'V11 compat'
)
Require 'Supervisor V11 compatibility smoke' $content.Smoke @(
    '--self-test',
    '--probe-ready-once',
    '--probe-failure-loop',
    '--probe-no-explorer',
    'health_mapping_released_after_ready_probe',
    'remaining_installation_shell_processes'
)
Require 'Native CI retains V11 compatibility smoke' $content.Workflow @(
    'run-native-supervisor-smoke-v11.ps1',
    'supervisor-v11-smoke.json'
)
Require 'Supervisor V11 protocol documentation' $content.Document @(
    '30 segundos',
    'heartbeat',
    'crash-loop',
    'Explorer',
    'nao altera o registro',
    'CloudOS.Supervisor.exe'
)

Write-Host 'PASS: Supervisor compatibility contract passed - V22 is the compiled recovery runtime while the reviewed V11 readiness/heartbeat/graceful-exit ABI remains protected.'
