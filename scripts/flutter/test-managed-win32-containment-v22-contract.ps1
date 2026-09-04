param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$clientPath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_broker_client_v21.cpp'
$hostPath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_managed_win32_host_v22.h'

if (-not (Test-Path -LiteralPath $clientPath)) { throw "Broker client missing: $clientPath" }
if (-not (Test-Path -LiteralPath $hostPath)) { throw "Managed Win32 host missing: $hostPath" }

$client = Get-Content -LiteralPath $clientPath -Raw
$host = Get-Content -LiteralPath $hostPath -Raw

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
    if (-not $Text.Contains($Needle, [System.StringComparison]::Ordinal)) {
        throw $Message
    }
}

Assert-Contains $client '#include "cloudos_managed_win32_host_v22.h"' 'Broker client must include the managed Win32 host boundary.'
Assert-Contains $client 'ManagedWin32HostV22::IsWindowsCatalogId(app_id)' 'Windows catalog launches must be intercepted before broker dispatch.'
Assert-Contains $client 'return ManagedWin32HostV22::Launch(app_id, err);' 'Windows catalog launches must route through managed containment.'

$launchIndex = $client.IndexOf('CloudOSBrokerClientV21::LaunchApp', [System.StringComparison]::Ordinal)
$containmentIndex = $client.IndexOf('ManagedWin32HostV22::IsWindowsCatalogId(app_id)', $launchIndex, [System.StringComparison]::Ordinal)
$brokerIndex = $client.IndexOf('if (!EnsureConnected())', $launchIndex, [System.StringComparison]::Ordinal)
if ($launchIndex -lt 0 -or $containmentIndex -lt 0 -or $brokerIndex -lt 0 -or $containmentIndex -gt $brokerIndex) {
    throw 'Containment interception must occur before System Broker connectivity/launch fallback.'
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
    'No attributable top-level window appeared; launch was blocked to prevent escape'
)) {
    Assert-Contains $host $needle "Managed Win32 containment contract missing: $needle"
}

foreach ($forbiddenCall in @('ShellExecuteW(', 'ShellExecuteExW(')) {
    if ($host.Contains($forbiddenCall, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Managed Win32 containment boundary must not use external launch fallback: $forbiddenCall"
    }
}

foreach ($unsupported in @('windows:vscode', 'windows:explorer', 'windows:taskmgr')) {
    if ($host.Contains($unsupported, [System.StringComparison]::Ordinal)) {
        throw "Unsupported/singleton Windows app must not be silently allowlisted yet: $unsupported"
    }
}

if (-not $host.Contains('return app_id.rfind("windows:", 0) == 0;', [System.StringComparison]::Ordinal)) {
    throw 'All windows:* IDs must be recognized as belonging to the fail-closed containment boundary.'
}

Write-Host 'Managed Win32 containment V22 contract: PASS'
