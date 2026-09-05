[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$recoveryCpp = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_session_recovery.cpp'
$recoveryH = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_session_recovery.h'
$lifecycleH = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_lifecycle_v10.h'
$eventsH = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_session_events_v7.h'
$supervisorV22 = Join-Path $root 'desktop\CloudOS.NativeRecovery\main_v22.cpp'
$brokerServer = Join-Path $root 'desktop\CloudOS.SystemBroker\src\broker_server_v21.cpp'
$settingsService = Join-Path $root 'desktop\CloudOS.SystemBroker\src\system_settings_service_v25.cpp'
$recoveryModels = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\models\recovery_models.dart'
$bridgeDart = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\services\cloudos_bridge.dart'
$brokerExe = Join-Path $root 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.SystemBroker.exe'

foreach ($file in @(
    $recoveryCpp, $recoveryH, $lifecycleH, $eventsH, $supervisorV22,
    $brokerServer, $settingsService, $recoveryModels, $bridgeDart, $brokerExe
)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Recovery/Lifecycle contract input missing: $file"
    }
}

$recoveryCppContent = Get-Content -LiteralPath $recoveryCpp -Raw
$recoveryHContent = Get-Content -LiteralPath $recoveryH -Raw
$lifecycleHContent = Get-Content -LiteralPath $lifecycleH -Raw
$eventsHContent = Get-Content -LiteralPath $eventsH -Raw
$supervisorContent = Get-Content -LiteralPath $supervisorV22 -Raw
$brokerContent = Get-Content -LiteralPath $brokerServer -Raw
$settingsContent = Get-Content -LiteralPath $settingsService -Raw
$modelsContent = Get-Content -LiteralPath $recoveryModels -Raw
$bridgeContent = Get-Content -LiteralPath $bridgeDart -Raw

# 1. Config Corruption Recovery Contract
foreach ($token in @(
    'state_path_ + L".corrupt"',
    'MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH'
)) {
    if (-not $recoveryCppContent.Contains($token)) {
        throw "Session recovery does not implement corrupted state quarantine: $token"
    }
}

foreach ($token in @(
    '.corrupt.bak',
    'PersonalizationSettingsV25 defaults{}'
)) {
    if (-not $settingsContent.Contains($token)) {
        throw "Settings service does not implement corrupted json quarantine and default restoration: $token"
    }
}

# 2. Supervisor Crash Loop & Safe Mode Contract
foreach ($token in @(
    'kV22CrashWindowMs = 60000ull',
    'RecordFailureV22',
    'EnterSafeModeV22',
    'FallbackToExplorer',
    'JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE',
    'ProbeReadyHeartbeatV22'
)) {
    if (-not $supervisorContent.Contains($token)) {
        throw "Supervisor does not fulfill crash loop protection contract: $token"
    }
}

# 3. Session & Power Lifecycle Contract
foreach ($token in @(
    'WM_POWERBROADCAST',
    'IsPowerSuspend',
    'IsPowerResume',
    'RevalidateShellSurfaces',
    'WM_QUERYENDSESSION',
    'WM_ENDSESSION'
)) {
    if (-not $lifecycleHContent.Contains($token) -and -not $recoveryHContent.Contains($token)) {
        throw "Lifecycle coordinator missing power or end session handler: $token"
    }
}

foreach ($token in @(
    'WTS_REMOTE_CONNECT',
    'WTS_REMOTE_DISCONNECT',
    'WTS_SESSION_LOCK',
    'WTS_SESSION_UNLOCK'
)) {
    if (-not $eventsHContent.Contains($token)) {
        throw "Session events handler missing WTS/RDP event: $token"
    }
}

# 4. SystemBroker RPC Endpoints Contract
foreach ($token in @(
    'recovery.getStatus',
    'recovery.enterSafeMode',
    'system.requestShutdown'
)) {
    if (-not $brokerContent.Contains($token)) {
        throw "Broker server missing recovery lifecycle RPC method: $token"
    }
}

# 5. Flutter Shell Models & Bridge Contract
foreach ($token in @(
    'CloudOSRecoveryStatus',
    'isHealthy',
    'isSafeMode',
    'isCrashLoop',
    'getRecoveryStatus()',
    'enterSafeMode()',
    'requestShutdown()'
)) {
    if (-not $modelsContent.Contains($token) -and -not $bridgeContent.Contains($token)) {
        throw "Flutter shell models or bridge missing recovery contract: $token"
    }
}

# 6. Functional Verification
$selfTestOutput = & $brokerExe --self-test
if ($LASTEXITCODE -ne 0) {
    throw "SystemBroker self-test failed with exit code $LASTEXITCODE"
}

$statusScript = Join-Path $PSScriptRoot 'get-cloudos-recovery-status-v22.ps1'
$status = & $statusScript
if ($status['schema'] -ne 22) {
    throw "Recovery status report returned unexpected schema: $($status['schema'])"
}

Write-Host '[PASS] Recovery & Lifecycle V26 Contract: session state corruption quarantine, settings fallback, supervisor crash loop protection, power suspend/resume, WTS/RDP session events, orderly shutdown RPC and Flutter bridge.'
