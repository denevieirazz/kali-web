param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$clientPath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_broker_client_v21.cpp'
$hostPath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_managed_win32_host_v22.h'
$appServicePath = Join-Path $root 'desktop\CloudOS.SystemBroker\src\app_service_v21.cpp'

if (-not (Test-Path -LiteralPath $clientPath)) { throw "Broker client missing: $clientPath" }
if (-not (Test-Path -LiteralPath $hostPath)) { throw "Managed Win32 host missing: $hostPath" }
if (-not (Test-Path -LiteralPath $appServicePath)) { throw "System Broker app service missing: $appServicePath" }

$clientSource = Get-Content -LiteralPath $clientPath -Raw
$hostSource = Get-Content -LiteralPath $hostPath -Raw
$appServiceSource = Get-Content -LiteralPath $appServicePath -Raw

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
    if (-not $Text.Contains($Needle, [System.StringComparison]::Ordinal)) {
        throw $Message
    }
}

Assert-Contains $clientSource '#include "cloudos_managed_win32_host_v22.h"' 'Broker client must include the managed Win32 host boundary.'
Assert-Contains $clientSource 'ManagedWin32HostV22::IsWindowsCatalogId(app_id)' 'Windows catalog launches must be intercepted before broker dispatch.'
Assert-Contains $clientSource 'return ManagedWin32HostV22::Launch(app_id, err);' 'Windows catalog launches must route through managed containment.'
Assert-Contains $clientSource 'Windows console profiles must be routed to CloudOS Terminal / ConPTY' 'Flutter broker client must fail closed for CMD/PowerShell before generic Win32 containment.'

$launchIndex = $clientSource.IndexOf('CloudOSBrokerClientV21::LaunchApp', [System.StringComparison]::Ordinal)
$consoleGuardIndex = $clientSource.IndexOf('app_id == "windows:cmd" || app_id == "windows:powershell"', $launchIndex, [System.StringComparison]::Ordinal)
$containmentIndex = $clientSource.IndexOf('ManagedWin32HostV22::IsWindowsCatalogId(app_id)', $launchIndex, [System.StringComparison]::Ordinal)
$brokerIndex = $clientSource.IndexOf('if (!EnsureConnected())', $launchIndex, [System.StringComparison]::Ordinal)
if ($launchIndex -lt 0 -or $consoleGuardIndex -lt 0 -or $containmentIndex -lt 0 -or $brokerIndex -lt 0) {
    throw 'Could not locate the console/containment/broker launch boundaries.'
}
if ($consoleGuardIndex -gt $containmentIndex) {
    throw 'CMD/PowerShell must be rejected from generic Win32 containment before the windows:* boundary runs.'
}
if ($containmentIndex -gt $brokerIndex) {
    throw 'Containment interception must occur before System Broker connectivity/launch fallback.'
}

Assert-Contains $appServiceSource 'Windows console profiles must be opened through CloudOS Terminal / ConPTY' 'System Broker must reject direct CMD/PowerShell launch bypasses.'
Assert-Contains $appServiceSource '{"windows:powershell", "PowerShell", "windows", "CloudOS Terminal / ConPTY"' 'Classic Windows PowerShell must not be mislabeled as PowerShell 7.'
Assert-Contains $appServiceSource '{"windows:cmd", "Prompt de Comando", "windows", "CloudOS Terminal / ConPTY"' 'CMD catalog entry must advertise the first-party ConPTY route.'

foreach ($forbidden in @(
    'ShellExecuteW(nullptr, L"open", L"powershell.exe"',
    'ShellExecuteW(nullptr, L"open", L"cmd.exe"',
    '{"windows:powershell", "PowerShell 7"'
)) {
    if ($appServiceSource.Contains($forbidden, [System.StringComparison]::Ordinal)) {
        throw "System Broker console route regressed to an external/misidentified launch: $forbidden"
    }
}

foreach ($needle in @(
    'windows:notepad',
    'windows:cmd',
    'windows:powershell',
    'CreateJobObjectW',
    'JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE',
    'AssignProcessToJobObject',
    'IsProcessInJob',
    'SetParent',
    'WS_CHILD',
    'TerminateJobObject',
    'BlockLaunch(app_id, error)',
    'The application was not allowed to escape into the Windows desktop.',
    'No attributable top-level window appeared; launch was blocked to prevent escape'
)) {
    Assert-Contains $hostSource $needle "Managed Win32 containment contract missing: $needle"
}

foreach ($forbiddenCall in @('ShellExecuteW(', 'ShellExecuteExW(')) {
    if ($hostSource.Contains($forbiddenCall, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Managed Win32 containment boundary must not use external launch fallback: $forbiddenCall"
    }
}

foreach ($unsupported in @('windows:vscode', 'windows:explorer', 'windows:taskmgr')) {
    if ($hostSource.Contains($unsupported, [System.StringComparison]::Ordinal)) {
        throw "Unsupported/singleton Windows app must not be silently allowlisted yet: $unsupported"
    }
}

if (-not $hostSource.Contains('return app_id.rfind("windows:", 0) == 0;', [System.StringComparison]::Ordinal)) {
    throw 'All windows:* IDs must be recognized as belonging to the fail-closed containment boundary.'
}

Write-Host 'Managed Win32 containment + console ConPTY routing V22 contract: PASS'
