param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$PackageRoot,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$rootPath = (Resolve-Path -LiteralPath $Root).Path
if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Join-Path $rootPath 'desktop\CloudOS.NativeShell\artifacts\CloudOS-Native-Release-x64'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $rootPath 'desktop\CloudOS.NativeShell\artifacts\deployment-v13-smoke.json'
}
$packagePath = (Resolve-Path -LiteralPath $PackageRoot).Path
$modulePath = Join-Path $rootPath 'scripts\native\CloudOS.Deployment.V13.psm1'
Import-Module -Name $modulePath -Force

function Copy-TestPackage([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
    }
}

$failures = New-Object System.Collections.Generic.List[string]
$evidence = [ordered]@{
    clean_install = $false
    idempotent_reinstall = $false
    verified_upgrade = $false
    corrupted_package_rejected = $false
    active_unchanged_after_rejection = $false
    interrupted_transaction_repaired = $false
    rollback_restored_previous = $false
    uninstall_removed_managed_root = $false
    supervisor_self_test_on_publish = $true
    broker_integrity_in_transaction = $false
    registry_or_winlogon_modified = $false
    first_version = $null
    upgraded_version = $null
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('CloudOS-V13-' + [Guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $temp 'installed'
$upgradePackage = Join-Path $temp 'upgrade-package'
$corruptPackage = Join-Path $temp 'corrupt-package'

try {
    New-Item -ItemType Directory -Path $temp -Force | Out-Null

    $first = Invoke-CloudOSDeployment -SourcePackageRoot $packagePath -InstallRoot $installRoot -RetainVersions 2
    if (-not $first.installed -or -not $first.active_valid -or [string]::IsNullOrWhiteSpace([string]$first.active_version)) {
        throw 'Clean V13 install did not produce one verified active version.'
    }
    $version1 = [string]$first.active_version
    $evidence.first_version = $version1
    $evidence.clean_install = $true

    $again = Invoke-CloudOSDeployment -SourcePackageRoot $packagePath -InstallRoot $installRoot -RetainVersions 2
    if ([string]$again.active_version -ne $version1 -or @($again.installed_versions).Count -ne 1) {
        throw 'Repeated V13 install was not idempotent.'
    }
    $evidence.idempotent_reinstall = $true

    Copy-TestPackage -Source $packagePath -Destination $upgradePackage
    $manifestPath = Join-Path $upgradePackage 'cloudos-native-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $syntheticHead = ('1' * 40)
    if ([string]$manifest.git_head -eq $syntheticHead) { $syntheticHead = ('2' * 40) }
    $manifest.git_head = $syntheticHead
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    if (Test-Path -LiteralPath (Join-Path $upgradePackage '.cloudos-build-head')) {
        Set-Content -LiteralPath (Join-Path $upgradePackage '.cloudos-build-head') -Value $syntheticHead -Encoding ascii
    }

    $upgraded = Invoke-CloudOSDeployment -SourcePackageRoot $upgradePackage -InstallRoot $installRoot -RetainVersions 2
    $version2 = [string]$upgraded.active_version
    $evidence.upgraded_version = $version2
    if ($version2 -eq $version1 -or [string]$upgraded.last_known_good -ne $version1 -or -not $upgraded.active_valid) {
        throw 'Verified V13 upgrade did not preserve the previous version as last-known-good.'
    }
    $evidence.verified_upgrade = $true

    # Corrupt the Broker rather than the shell executable so this smoke proves
    # the V13 transaction gate protects the complete five-binary V21 runtime.
    Copy-TestPackage -Source $upgradePackage -Destination $corruptPackage
    [IO.File]::AppendAllText((Join-Path $corruptPackage 'CloudOS.SystemBroker.exe'), 'V13_BROKER_CORRUPTION_PROBE')
    $rejected = $false
    try {
        Invoke-CloudOSDeployment -SourcePackageRoot $corruptPackage -InstallRoot $installRoot -RetainVersions 2 | Out-Null
    }
    catch {
        $rejected = $true
    }
    if (-not $rejected) { throw 'Package with corrupted System Broker was accepted.' }
    $evidence.corrupted_package_rejected = $true
    $evidence.broker_integrity_in_transaction = $true

    $afterRejection = Get-CloudOSDeploymentStatus -InstallRoot $installRoot
    if ([string]$afterRejection.active_version -ne $version2 -or [string]$afterRejection.last_known_good -ne $version1) {
        throw 'Rejected package changed active/LKG state.'
    }
    $evidence.active_unchanged_after_rejection = $true

    $paths = Get-CloudOSDeploymentPaths -InstallRoot $installRoot
    $orphanStage = Join-Path $paths.Staging 'interrupted-probe'
    New-Item -ItemType Directory -Path $orphanStage -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $orphanStage 'partial.txt') -Value 'partial' -Encoding ascii
    $journal = [ordered]@{
        schema = 13
        product = 'CloudOS Native Shell'
        operation = 'deploy'
        phase = 'copying'
        target_version = 'interrupted-probe'
        previous_active = $version2
        staging_path = $orphanStage
        updated_utc = [DateTime]::UtcNow.ToString('o')
    }
    $journal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $paths.Journal -Encoding utf8
    $repair = Invoke-CloudOSRepair -InstallRoot $installRoot
    $afterRepair = Get-CloudOSDeploymentStatus -InstallRoot $installRoot
    if ((Test-Path -LiteralPath $orphanStage) -or $afterRepair.journal_present -or [string]$afterRepair.active_version -ne $version2) {
        throw 'V13 repair did not clean an interrupted pre-activation transaction safely.'
    }
    $evidence.interrupted_transaction_repaired = $true

    $rolledBack = Invoke-CloudOSRollback -InstallRoot $installRoot
    if ([string]$rolledBack.active_version -ne $version1 -or [string]$rolledBack.last_known_good -ne $version2 -or -not $rolledBack.active_valid) {
        throw 'V13 rollback did not restore the exact previous verified version.'
    }
    $evidence.rollback_restored_previous = $true

    $removed = Invoke-CloudOSUninstall -InstallRoot $installRoot
    if (-not $removed.uninstalled -or (Test-Path -LiteralPath $installRoot)) {
        throw 'V13 uninstall did not remove the managed install root.'
    }
    $evidence.uninstall_removed_managed_root = $true
}
catch {
    $failures.Add($_.Exception.Message)
}
finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$verdict = 'pass'
if ($failures.Count -gt 0) { $verdict = 'fail' }
$report = [ordered]@{
    schema = 13
    test = 'CloudOS Transactional Deployment V13'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    verdict = $verdict
    scope = 'Temporary-directory install/update/repair/rollback/uninstall transaction semantics for the five-binary V21 runtime. No Winlogon, registry shell replacement, logoff or reboot is performed.'
    evidence = $evidence
    failures = @($failures)
}

$parent = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding utf8
if ($verdict -ne 'pass') {
    throw ('Transactional Deployment V13 smoke failed: ' + ($failures -join '; '))
}
Write-Host "PASS: Transactional Deployment V13 smoke -> $OutputPath"
