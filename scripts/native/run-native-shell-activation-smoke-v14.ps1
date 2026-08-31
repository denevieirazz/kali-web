param(
    [string]$PackageRoot = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'desktop\CloudOS.NativeShell\artifacts\CloudOS-Native-Release-x64'),
    [string]$OutputPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'desktop\CloudOS.NativeShell\artifacts\shell-activation-v14-smoke.json')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$package = (Resolve-Path -LiteralPath $PackageRoot).Path
$deploymentModule = Join-Path $package 'CloudOS.Deployment.V13.psm1'
$activationModule = Join-Path $package 'CloudOS.ShellActivation.V14.psm1'
foreach ($path in @($deploymentModule, $activationModule)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "V14 smoke prerequisite missing: $path" }
}
Import-Module -Name $deploymentModule -Force
Import-Module -Name $activationModule -Force

$defaultSubKey = 'Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
$testSubKey = 'Software\CloudOS\Tests\ShellActivationV14\' + [Guid]::NewGuid().ToString('N')
$installRoot = Join-Path ([IO.Path]::GetTempPath()) ('CloudOS-ShellActivation-V14-' + [Guid]::NewGuid().ToString('N'))

function Get-RegistrySnapshot {
    param([Parameter(Mandatory = $true)][string]$SubKey)
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SubKey, $false)
    if ($null -eq $key) { return [ordered]@{ present = $false; kind = $null; data = $null } }
    try {
        $names = @($key.GetValueNames())
        $found = @($names | Where-Object { $_.Equals('Shell', [StringComparison]::OrdinalIgnoreCase) })
        if ($found.Count -eq 0) { return [ordered]@{ present = $false; kind = $null; data = $null } }
        $kind = $key.GetValueKind('Shell').ToString()
        $value = $key.GetValue('Shell', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($value -is [Array]) { $value = @($value) }
        return [ordered]@{ present = $true; kind = $kind; data = $value }
    }
    finally { $key.Dispose() }
}

function Set-TestShellValue {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Microsoft.Win32.RegistryValueKind]$Kind = [Microsoft.Win32.RegistryValueKind]::String
    )
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($testSubKey, $true)
    try { $key.SetValue('Shell', $Value, $Kind) }
    finally { $key.Dispose() }
}

function Remove-TestKey {
    try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($testSubKey, $false) }
    catch { }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Snapshot-Equal {
    param($Left, $Right)
    return (($Left | ConvertTo-Json -Depth 6 -Compress) -ceq ($Right | ConvertTo-Json -Depth 6 -Compress))
}

$evidence = [ordered]@{
    clean_deployment_verified = $false
    absent_prior_restored_as_absent = $false
    explorer_prior_restored_exactly = $false
    expand_string_prior_type_restored = $false
    idempotent_activation = $false
    stable_shell_entry_ready_probe = $false
    interrupted_activation_repaired = $false
    invalid_active_payload_rejected = $false
    uninstall_blocked_while_active = $false
    uninstall_succeeded_after_shell_rollback = $false
    production_winlogon_unchanged = $false
    production_registry_subkey = $defaultSubKey
    sandbox_registry_subkey = $testSubKey
}
$failures = New-Object System.Collections.Generic.List[string]
$productionBefore = Get-RegistrySnapshot -SubKey $defaultSubKey

try {
    Remove-TestKey
    if (Test-Path -LiteralPath $installRoot) { Remove-Item -LiteralPath $installRoot -Recurse -Force }

    $deployment = Invoke-CloudOSDeployment -SourcePackageRoot $package -InstallRoot $installRoot
    Assert-True -Condition ($deployment.installed -and $deployment.active_valid) -Message 'V14 smoke could not create a verified V13 deployment.'
    $evidence.clean_deployment_verified = $true

    $activation = Invoke-CloudOSShellActivation -InstallRoot $installRoot -RegistrySubKey $testSubKey -AllowTestRegistryOverride
    Assert-True -Condition ($activation.activated -and $activation.registry_matches) -Message 'V14 activation did not own the sandbox Shell value.'

    $entry = Join-Path $installRoot 'shell-v14\CloudOS.ShellEntry.V14.ps1'
    Assert-True -Condition (Test-Path -LiteralPath $entry -PathType Leaf) -Message 'Stable V14 shell entry script was not installed.'
    $probe = Start-Process -FilePath 'pwsh.exe' -ArgumentList @(
        '-NoLogo', '-NoProfile', '-File', $entry, '-InstallRoot', $installRoot, '-ProbeReadyOnce'
    ) -PassThru -Wait -WindowStyle Hidden
    Assert-True -Condition ($probe.ExitCode -eq 0) -Message "Stable V14 shell entry readiness probe failed with exit code $($probe.ExitCode)."
    $evidence.stable_shell_entry_ready_probe = $true

    $activation2 = Invoke-CloudOSShellActivation -InstallRoot $installRoot -RegistrySubKey $testSubKey -AllowTestRegistryOverride
    Assert-True -Condition ($activation2.activated -and $activation2.registry_matches) -Message 'Repeated V14 activation was not idempotent.'
    $evidence.idempotent_activation = $true

    [void](Invoke-CloudOSShellRollback -InstallRoot $installRoot -RegistrySubKey $testSubKey -AllowTestRegistryOverride)
    $afterAbsentRollback = Get-RegistrySnapshot -SubKey $testSubKey
    Assert-True -Condition (-not [bool]$afterAbsentRollback.present) -Message 'V14 rollback did not restore an originally absent Shell value as absent.'
    $evidence.absent_prior_restored_as_absent = $true

    Set-TestShellValue -Value 'explorer.exe' -Kind ([Microsoft.Win32.RegistryValueKind]::String)
    $explorerBefore = Get-RegistrySnapshot -SubKey $testSubKey
    [void](Invoke-CloudOSShellActivation -InstallRoot $installRoot -RegistrySubKey $testSubKey -AllowTestRegistryOverride)
    [void](Invoke-CloudOSShellRollback -InstallRoot $installRoot -RegistrySubKey $testSubKey -AllowTestRegistryOverride)
    $explorerAfter = Get-RegistrySnapshot -SubKey $testSubKey
    Assert-True -Condition (Snapshot-Equal -Left $explorerBefore -Right $explorerAfter) -Message 'V14 rollback did not restore explorer.exe exactly.'
    $evidence.explorer_prior_restored_exactly = $true

    Set-TestShellValue -Value '%SystemRoot%\explorer.exe /custom-prior' -Kind ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    $expandBefore = Get-RegistrySnapshot -SubKey $testSubKey
    [void](Invoke-CloudOSShellActivation -InstallRoot $installRoot -RegistrySubKey $testSubKey -AllowTestRegistryOverride)
    [void](Invoke-CloudOSShellRollback -InstallRoot $installRoot -RegistrySubKey $testSubKey -AllowTestRegistryOverride)
    $expandAfter = Get-RegistrySnapshot -SubKey $testSubKey
    Assert-True -Condition (Snapshot-Equal -Left $expandBefore -Right $expandAfter) -Message 'V14 rollback did not restore REG_EXPAND_SZ data/type exactly.'
    $evidence.expand_string_prior_type_restored = $true

    Set-TestShellValue -Value 'explorer.exe /before-interrupt' -Kind ([Microsoft.Win32.RegistryValueKind]::String)
    $interruptBefore = Get-RegistrySnapshot -SubKey $testSubKey
    $interrupted = $false
    try {
        [void](Invoke-CloudOSShellActivation -InstallRoot $installRoot -RegistrySubKey $testSubKey -AllowTestRegistryOverride -ProbeInterruptAfterRegistryWrite)
    }
    catch {
        if ($_.Exception.Message -like '*deterministic interruption probe*') { $interrupted = $true }
        else { throw }
    }
    Assert-True -Condition $interrupted -Message 'V14 interruption probe did not interrupt after registry write.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $installRoot 'state\shell-activation-v14.journal.json')) -Message 'V14 interruption probe did not leave the recovery journal.'
    $repair = Invoke-CloudOSShellRepair -InstallRoot $installRoot -AllowTestRegistryOverride
    $interruptAfter = Get-RegistrySnapshot -SubKey $testSubKey
    Assert-True -Condition ($repair.repaired -and (Snapshot-Equal -Left $interruptBefore -Right $interruptAfter)) -Message 'V14 repair did not restore the exact pre-transaction Shell value.'
    $evidence.interrupted_activation_repaired = $true

    $deploymentStatus = Get-CloudOSDeploymentStatus -InstallRoot $installRoot
    $paths = Get-CloudOSDeploymentPaths -InstallRoot $installRoot
    $activeSupervisor = Join-Path (Join-Path $paths.Versions ([string]$deploymentStatus.active_version)) 'CloudOS.Supervisor.exe'
    $heldSupervisor = $activeSupervisor + '.v14-smoke-held'
    Move-Item -LiteralPath $activeSupervisor -Destination $heldSupervisor
    try {
        $rejected = $false
        try {
            [void](Invoke-CloudOSShellActivation -InstallRoot $installRoot -RegistrySubKey $testSubKey -AllowTestRegistryOverride)
        }
        catch { $rejected = $true }
        Assert-True -Condition $rejected -Message 'V14 activation accepted a deployment whose active Supervisor was missing.'
        $evidence.invalid_active_payload_rejected = $true
    }
    finally {
        Move-Item -LiteralPath $heldSupervisor -Destination $activeSupervisor -Force
    }

    [void](Invoke-CloudOSShellActivation -InstallRoot $installRoot -RegistrySubKey $testSubKey -AllowTestRegistryOverride)
    $blocked = $false
    $uninstallScript = Join-Path $package 'uninstall-cloudos-native-v13.ps1'
    try {
        & $uninstallScript -InstallRoot $installRoot
    }
    catch {
        if ($_.Exception.Message -like '*configured as the per-user logon shell*') { $blocked = $true }
        else { throw }
    }
    Assert-True -Condition $blocked -Message 'V13 uninstall was not blocked while V14 activation was active.'
    $evidence.uninstall_blocked_while_active = $true

    [void](Invoke-CloudOSShellRollback -InstallRoot $installRoot -RegistrySubKey $testSubKey -AllowTestRegistryOverride)
    & $uninstallScript -InstallRoot $installRoot
    Assert-True -Condition (-not (Test-Path -LiteralPath $installRoot)) -Message 'V13 uninstall did not remove the managed root after V14 rollback.'
    $evidence.uninstall_succeeded_after_shell_rollback = $true

    $productionAfter = Get-RegistrySnapshot -SubKey $defaultSubKey
    Assert-True -Condition (Snapshot-Equal -Left $productionBefore -Right $productionAfter) -Message 'Hosted V14 smoke unexpectedly changed the real HKCU Winlogon Shell value.'
    $evidence.production_winlogon_unchanged = $true
}
catch {
    $failures.Add($_.Exception.Message)
}
finally {
    try {
        if (Test-Path -LiteralPath $installRoot) {
            $statePath = Join-Path $installRoot 'state\shell-activation-v14.json'
            if (Test-Path -LiteralPath $statePath) {
                try { [void](Invoke-CloudOSShellRollback -InstallRoot $installRoot -RegistrySubKey $testSubKey -AllowTestRegistryOverride -ForceRestoreSnapshot) } catch { }
            }
            try { Remove-Item -LiteralPath $installRoot -Recurse -Force } catch { }
        }
    }
    catch { }
    Remove-TestKey
}

$report = [ordered]@{
    schema = 14
    test = 'CloudOS Shell Activation V14'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    verdict = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    scope = 'HKCU sandbox-registry activation/rollback transaction semantics plus real installed shell-entry readiness probe. The production Winlogon key, HKLM, logoff and reboot are not modified by this hosted CI smoke.'
    evidence = $evidence
    failures = @($failures)
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding utf8

if ($failures.Count -ne 0) {
    throw "Shell Activation V14 smoke failed: $($failures -join '; ')"
}
Write-Host "PASS: Shell Activation V14 sandbox smoke ($OutputPath)"
