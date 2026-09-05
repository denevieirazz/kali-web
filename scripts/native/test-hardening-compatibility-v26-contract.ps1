[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$securityCpp = Join-Path $root 'desktop\CloudOS.SystemBroker\src\security_v21.cpp'
$perfManager = Join-Path $root 'desktop\CloudOS.SystemBroker\src\performance_manager_v21.cpp'
$jobManager = Join-Path $root 'desktop\CloudOS.SystemBroker\src\job_manager_v21.h'
$appService = Join-Path $root 'desktop\CloudOS.SystemBroker\src\app_service_v21.cpp'
$brokerServer = Join-Path $root 'desktop\CloudOS.SystemBroker\src\broker_server_v21.cpp'
$systemService = Join-Path $root 'desktop\CloudOS.SystemBroker\src\system_service_v21.cpp'
$wslService = Join-Path $root 'desktop\CloudOS.SystemBroker\src\wsl_service_v21.cpp'
$modelsDart = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\models\system_settings_models.dart'
$recoveryDart = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\models\recovery_models.dart'
$bridgeDart = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\services\cloudos_bridge.dart'
$brokerExe = Join-Path $root 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.SystemBroker.exe'

foreach ($file in @(
    $securityCpp, $perfManager, $jobManager, $appService, $brokerServer,
    $systemService, $wslService, $modelsDart, $recoveryDart, $bridgeDart, $brokerExe
)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Hardening & Compatibility contract input missing: $file"
    }
}

$securityContent = Get-Content -LiteralPath $securityCpp -Raw
$perfContent = Get-Content -LiteralPath $perfManager -Raw
$jobContent = Get-Content -LiteralPath $jobManager -Raw
$appContent = Get-Content -LiteralPath $appService -Raw
$brokerContent = Get-Content -LiteralPath $brokerServer -Raw
$systemContent = Get-Content -LiteralPath $systemService -Raw
$wslContent = Get-Content -LiteralPath $wslService -Raw
$modelsContent = Get-Content -LiteralPath $modelsDart -Raw
$recoveryContent = Get-Content -LiteralPath $recoveryDart -Raw
$bridgeContent = Get-Content -LiteralPath $bridgeDart -Raw

# 1. Economy Profile & Low-End Hardware Detection
foreach ($token in @(
    'is_low_end_hardware_ = (total_ram_mb_ <= 8192 || cpu_cores_ <= 4);',
    'PerformanceProfile::Economy',
    'system.performanceProfileChanged',
    'kMaxRetainedJobs = 64',
    'kMaxQueuedJobs = 64'
)) {
    if (-not $perfContent.Contains($token) -and -not $jobContent.Contains($token)) {
        throw "Economy profile or low-end hardware protection missing: $token"
    }
}

# 2. IPC Security & Named Pipe DACL / SID Validation
foreach ($token in @(
    'D:P(A;;GA;;;',
    'BuildDenyAllSecurityAttributes',
    'ValidateNamedPipeClient',
    'client_session != broker_session',
    '_wcsicmp(broker_sid.c_str(), client_sid.c_str())',
    'ERROR_ACCESS_DENIED'
)) {
    if (-not $securityContent.Contains($token)) {
        throw "IPC Security fail-closed DACL/SID contract missing: $token"
    }
}

# 3. Command Injection & Arbitrary Execution Prevention
foreach ($token in @(
    'calc.exe && malicious_command',
    'powershell.exe -enc AAAAA'
)) {
    $selfTestCode = Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.SystemBroker\src\broker_main.cpp') -Raw
    if (-not $selfTestCode.Contains($token)) {
        throw "SystemBroker self-test missing command injection verification: $token"
    }
}

# 4. Capability Model & Graceful Degradation
foreach ($token in @(
    'system.getCapabilities',
    'audio_control',
    'brightness_control',
    'wsl_runtime',
    'economy_mode',
    'rdp_session',
    'multi_monitor'
)) {
    if (-not $brokerContent.Contains($token) -and -not $recoveryContent.Contains($token)) {
        throw "System capabilities contract missing: $token"
    }
}

# 5. Flutter Shell Data Models & Bridge
foreach ($token in @(
    'CloudHardwareMetrics',
    'isEconomyProfile',
    'CloudOSSystemCapabilities',
    'getSystemCapabilities()',
    'getHardwareMetrics()'
)) {
    if (-not $modelsContent.Contains($token) -and -not $recoveryContent.Contains($token) -and -not $bridgeContent.Contains($token)) {
        throw "Flutter shell models or bridge missing hardening contract: $token"
    }
}

# 6. Functional Verification
$selfTestOutput = & $brokerExe --self-test
if ($LASTEXITCODE -ne 0) {
    throw "SystemBroker self-test failed with exit code $LASTEXITCODE"
}

Write-Host '[PASS] Hardening & Compatibility V26 Contract: low-end hardware detection, economy profile enforcement, protected DACL fail-closed IPC security, command injection prevention, comprehensive capabilities map and Flutter bridge.'
