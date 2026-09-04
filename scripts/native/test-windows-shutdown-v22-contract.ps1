[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$shellBootstrapPath = Join-Path $root 'desktop\CloudOS.NativeShell\src\runtime_bootstrap.cpp'
$supervisorBootstrapPath = Join-Path $root 'desktop\CloudOS.NativeRecovery\supervisor_bootstrap_v22.h'
$recoveryHeaderPath = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_session_recovery.h'
$recoverySourcePath = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_session_recovery.cpp'
$suitePath = Join-Path $root 'scripts\native\test-native-contract-suite.ps1'

foreach ($path in @($shellBootstrapPath, $supervisorBootstrapPath, $recoveryHeaderPath, $recoverySourcePath, $suitePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Windows Shutdown V22 contract input missing: $path"
    }
}

$shellBootstrap = Get-Content -LiteralPath $shellBootstrapPath -Raw
$supervisorBootstrap = Get-Content -LiteralPath $supervisorBootstrapPath -Raw
$recoveryHeader = Get-Content -LiteralPath $recoveryHeaderPath -Raw
$recoverySource = Get-Content -LiteralPath $recoverySourcePath -Raw
$suite = Get-Content -LiteralPath $suitePath -Raw

foreach ($required in @(
    'kCloudOSShutdownLevel = 0x300u',
    'SetProcessShutdownParameters',
    'SHUTDOWN_NORETRY',
    'SEM_FAILCRITICALERRORS',
    'SEM_NOGPFAULTERRORBOX',
    'cloudos_native_runtime_abi()',
    'ERROR_REVISION_MISMATCH'
)) {
    if (-not $shellBootstrap.Contains($required)) {
        throw "CloudOS shell startup/shutdown contract missing: $required"
    }
}

foreach ($required in @(
    'kSupervisorShutdownLevel = 0x180u',
    'SetProcessShutdownParameters',
    'SHUTDOWN_NORETRY',
    'RegisterApplicationRestart',
    'RESTART_NO_CRASH | RESTART_NO_HANG'
)) {
    if (-not $supervisorBootstrap.Contains($required)) {
        throw "Supervisor shutdown-order contract missing: $required"
    }
}

foreach ($required in @(
    'WM_QUERYENDSESSION',
    'self->Checkpoint();',
    'return DefSubclassProc(window, message, w_param, l_param);',
    'WM_ENDSESSION && w_param != FALSE',
    'self->MarkEndSessionClean();',
    'owner_->MarkCleanExit(*owner_->session_window_manager_)'
)) {
    if (-not $recoveryHeader.Contains($required)) {
        throw "End-session lifecycle contract missing: $required"
    }
}

# The bounded end-session checkpoint is intentionally local and atomic. These
# primitives in NativeSessionRecovery::Write prove temp-file + flush + replace.
foreach ($required in @(
    'FILE_FLAG_WRITE_THROUGH',
    'FlushFileBuffers(file)',
    'MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH',
    'kMaximumRecords = 256u'
)) {
    if (-not $recoverySource.Contains($required)) {
        throw "Bounded local session checkpoint contract missing: $required"
    }
}

# Never add blocking/remote work directly to the WM_QUERYENDSESSION handler.
$queryBlock = [regex]::Match(
    $recoveryHeader,
    '(?s)if \(message == WM_QUERYENDSESSION\).*?return DefSubclassProc\(window, message, w_param, l_param\);')
if (-not $queryBlock.Success) {
    throw 'Could not isolate WM_QUERYENDSESSION handler for bounded-work checks.'
}
foreach ($forbidden in @(
    'Sleep(',
    'WaitForSingleObject',
    'MessageBox',
    'ShellExecute',
    'CreateProcess',
    'wsl.exe',
    'WinHttp',
    'InternetOpen',
    'WebView2'
)) {
    if ($queryBlock.Value.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "WM_QUERYENDSESSION must not perform blocking/remote work: $forbidden"
    }
}

if (-not $suite.Contains('test-windows-shutdown-v22-contract.ps1')) {
    throw 'Central native suite must protect Windows Shutdown V22.'
}

Write-Host '[PASS] Windows Shutdown V22: CloudOS checkpoints early, Supervisor remains late, end-session work stays local/bounded and no shutdown veto is introduced.'
