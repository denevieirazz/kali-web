[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$headerPath = Join-Path $root 'desktop\CloudOS.SystemBroker\src\job_manager_v21.h'
$sourcePath = Join-Path $root 'desktop\CloudOS.SystemBroker\src\job_manager_v21.cpp'
$suitePath = Join-Path $root 'scripts\native\test-native-contract-suite.ps1'
foreach ($path in @($headerPath, $sourcePath, $suitePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Job Manager V22 hardening input missing: $path"
    }
}

$header = Get-Content -LiteralPath $headerPath -Raw
$source = Get-Content -LiteralPath $sourcePath -Raw
$suite = Get-Content -LiteralPath $suitePath -Raw

foreach ($required in @(
    'mutable std::mutex info_mutex',
    'kMaxRetainedJobs = 512',
    'kMaxQueuedJobs = 256',
    'std::clamp<size_t>(worker_count, 1, 16)',
    'if (type.empty() || !func || !running_.load()) return {}',
    'jobs_.size() >= kMaxRetainedJobs',
    'queue_.size() >= kMaxQueuedJobs',
    'std::lock_guard<std::mutex> info_lock',
    'job->cancel_flag.store(true)',
    'job.cancelled',
    'std::isfinite(p)',
    'std::clamp(p, 0.0, 100.0)',
    'catch (...)',
    'unhandled_job_exception'
)) {
    if (-not ($header + $source).Contains($required, [StringComparison]::Ordinal)) {
        throw "Job Manager V22 hardening contract missing: $required"
    }
}

if ($source.Contains('job->info.progress = p;', [StringComparison]::Ordinal)) {
    throw 'Job Manager progress must not mutate shared JobInfo without validation/locking.'
}
if ($source.Contains('job->info.state = JobState::Cancelled;`n        job->info.updated_at_ms', [StringComparison]::Ordinal)) {
    throw 'Job Manager cancellation must not mutate shared JobInfo outside its per-job mutex.'
}
if (-not $suite.Contains('test-system-broker-job-manager-v22-contract.ps1', [StringComparison]::Ordinal)) {
    throw 'Central native suite must protect Job Manager V22 hardening.'
}

Write-Host '[PASS] System Broker Job Manager V22: per-job synchronization, bounded workers/queue/history, cancellation state and worker exceptions are fail-closed.'
