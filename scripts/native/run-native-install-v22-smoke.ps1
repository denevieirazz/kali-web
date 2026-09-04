[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$package = (Resolve-Path -LiteralPath $PackageRoot).Path
$installScript = Join-Path $package 'install-cloudos-native-v22.ps1'
$module = Join-Path $package 'CloudOS.Deployment.V13.psm1'
foreach ($path in @($installScript, $module)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Install V22 smoke dependency missing: $path"
    }
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $env:TEMP ('cloudos-install-v22-smoke-' + [Guid]::NewGuid().ToString('N') + '.json')
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$installRoot = Join-Path $env:TEMP ('CloudOS-Install-V22-' + [Guid]::NewGuid().ToString('N'))

Import-Module -Name $module -Force
$failures = [Collections.Generic.List[string]]::new()
$evidence = [ordered]@{}

try {
    try {
        & $installScript -PackageRoot $package -InstallRoot $installRoot -RetainVersions 2 -HealthTimeoutSeconds 45
    }
    catch {
        $failures.Add('FirstInstallFailed:' + $_.Exception.GetType().Name + ':' + $_.Exception.Message)
    }

    if ($failures.Count -eq 0) {
        $status = Get-CloudOSDeploymentStatus -InstallRoot $installRoot
        $evidence.installed = [bool]$status.installed
        $evidence.active_valid = [bool]$status.active_valid
        $evidence.active_version = [string]$status.active_version
        $evidence.last_known_good_empty = [string]::IsNullOrWhiteSpace([string]$status.last_known_good)
        $evidence.journal_absent = -not [bool]$status.journal_present

        if (-not $status.installed) { $failures.Add('ManagedInstallMissing') }
        if (-not $status.active_valid) { $failures.Add('ActivePayloadInvalidAfterHealthGate') }
        if ($status.journal_present) { $failures.Add('DeploymentJournalLeakedAfterInstall') }

        $secondRejected = $false
        try {
            & $installScript -PackageRoot $package -InstallRoot $installRoot -RetainVersions 2 -HealthTimeoutSeconds 45
        }
        catch {
            $secondRejected = $_.Exception.Message -match 'already installed|Atualizar CloudOS'
        }
        $evidence.second_install_rejected = $secondRejected
        if (-not $secondRejected) { $failures.Add('SecondInstallWasNotRejected') }

        $statusAfterRejection = Get-CloudOSDeploymentStatus -InstallRoot $installRoot
        $evidence.active_unchanged_after_rejection =
            [string]$statusAfterRejection.active_version -eq [string]$status.active_version
        if (-not $evidence.active_unchanged_after_rejection) {
            $failures.Add('SecondInstallChangedActiveVersion')
        }
    }
}
finally {
    try {
        if (Test-Path -LiteralPath $installRoot) {
            $statusBeforeUninstall = Get-CloudOSDeploymentStatus -InstallRoot $installRoot
            if ($statusBeforeUninstall.installed) {
                [void](Invoke-CloudOSUninstall -InstallRoot $installRoot)
            }
        }
    }
    catch {
        $failures.Add('CleanupFailed:' + $_.Exception.GetType().Name + ':' + $_.Exception.Message)
    }

    $evidence.install_root_removed = -not (Test-Path -LiteralPath $installRoot)
    if (-not $evidence.install_root_removed) {
        $failures.Add('InstallRootLeaked')
    }

    $remaining = New-Object System.Collections.Generic.List[string]
    foreach ($name in @('CloudOS', 'CloudOS.Supervisor', 'CloudOS.SystemBroker', 'CloudOS.BrokerProbe')) {
        foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try {
                $path = [string]$process.Path
                if (-not [string]::IsNullOrWhiteSpace($path) -and
                    [IO.Path]::GetFullPath($path).StartsWith(
                        [IO.Path]::GetFullPath($installRoot).TrimEnd('\') + '\',
                        [StringComparison]::OrdinalIgnoreCase)) {
                    $remaining.Add("$($process.ProcessName):$($process.Id)")
                }
            }
            catch {}
        }
    }
    $evidence.remaining_managed_processes = @($remaining)
    if ($remaining.Count -ne 0) {
        $failures.Add('ManagedProcessLeaked:' + ($remaining -join ','))
    }
}

$report = [ordered]@{
    schema = 22
    test = 'CloudOS Transactional Install V22'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    verdict = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    scope = 'First install through V22 Supervisor health gate, duplicate-install rejection, active-state preservation and managed cleanup.'
    evidence = $evidence
    failures = $failures.ToArray()
}

$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8

if ($failures.Count -gt 0) {
    Write-Error "FAIL: Transactional Install V22 smoke failed: $($failures -join ', '). Report: $OutputPath"
    exit 1
}
Write-Host "PASS: Transactional Install V22 smoke passed. Report: $OutputPath"
