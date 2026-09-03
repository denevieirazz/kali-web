[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$headerPath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_conpty_manager.h'
$sourcePath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_conpty_manager.cpp'
foreach ($path in @($headerPath, $sourcePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Flutter ConPTY V22 contract input missing: $path"
    }
}
$header = Get-Content -LiteralPath $headerPath -Raw
$source = Get-Content -LiteralPath $sourcePath -Raw

if ($header -notmatch 'UniqueWinHandle\s+job\s*;') {
    throw 'Each Flutter ConPTY session must own a Windows Job Object handle.'
}

foreach ($required in @(
    'JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE',
    'CreateJobObjectW',
    'SetInformationJobObject',
    'CREATE_SUSPENDED',
    'AssignProcessToJobObject',
    'ResumeThread',
    'TerminateJobObject',
    'WaitForSingleObject(process, 250)',
    'WaitForSingleObject(process, 5000)',
    'session->job = std::move(job)',
    'session->job.reset()'
)) {
    if (-not $source.Contains($required)) {
        throw "Flutter ConPTY V22 lifecycle guard missing: $required"
    }
}

$createIndex = $source.IndexOf('CreateProcessW(', [StringComparison]::Ordinal)
$assignIndex = $source.IndexOf('AssignProcessToJobObject', [StringComparison]::Ordinal)
$resumeIndex = $source.IndexOf('ResumeThread', [StringComparison]::Ordinal)
if ($createIndex -lt 0 -or $assignIndex -le $createIndex -or $resumeIndex -le $assignIndex) {
    throw 'Flutter ConPTY must create suspended, assign to the session job, then resume in that order.'
}

$closeIndex = $source.IndexOf('bool CloudOSConPTYManager::CloseSession', [StringComparison]::Ordinal)
$terminateProcessAfterClose = if ($closeIndex -ge 0) {
    $source.IndexOf('TerminateProcess(', $closeIndex, [StringComparison]::Ordinal)
} else { -1 }
if ($terminateProcessAfterClose -ge 0) {
    throw 'CloseSession must terminate the whole ConPTY job instead of killing only the root process.'
}

Write-Host '[PASS] Flutter ConPTY Lifecycle V22: sessions are assigned to kill-on-close Job Objects before resume, graceful EOF is bounded, and close/shutdown terminates the whole descendant tree instead of only the root process.'
