$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$modulePath = Join-Path $PSScriptRoot 'CloudOS.ShellActivation.V14.psm1'
$entryPath = Join-Path $PSScriptRoot 'CloudOS.ShellEntry.V14.ps1'
$smokePath = Join-Path $PSScriptRoot 'run-native-shell-activation-smoke-v14.ps1'
$uninstallPath = Join-Path $PSScriptRoot 'uninstall-cloudos-native-v13.ps1'
$packagePath = Join-Path $PSScriptRoot 'package-cloudos-native.ps1'
$contractSuitePath = Join-Path $PSScriptRoot 'test-native-contract-suite.ps1'
$workflowPath = Join-Path $root '.github\workflows\cloudos-native-full-system.yml'
foreach ($path in @($modulePath, $entryPath, $smokePath, $uninstallPath, $packagePath, $contractSuitePath, $workflowPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "V14 contract prerequisite missing: $path" }
}

$module = Get-Content -LiteralPath $modulePath -Raw
$entry = Get-Content -LiteralPath $entryPath -Raw
$smoke = Get-Content -LiteralPath $smokePath -Raw
$uninstall = Get-Content -LiteralPath $uninstallPath -Raw
$package = Get-Content -LiteralPath $packagePath -Raw
$contractSuite = Get-Content -LiteralPath $contractSuitePath -Raw
$workflow = Get-Content -LiteralPath $workflowPath -Raw

foreach ($required in @(
    "ActivationSchema = 14",
    "DefaultRegistrySubKey = 'Software\Microsoft\Windows NT\CurrentVersion\Winlogon'",
    "TestRegistryPrefix = 'Software\CloudOS\Tests\ShellActivationV14\'",
    'DoNotExpandEnvironmentNames',
    'GetValueKind',
    'previous_value',
    'shell-activation-v14.journal.json',
    'ProbeInterruptAfterRegistryWrite',
    'The interruption probe is forbidden against the production Winlogon key',
    'Refusing to overwrite an external change',
    'drift-detected-no-write',
    'CloudOS.ShellEntry.V14.cmd',
    'Restaurar Explorer.cmd',
    'cmd.exe',
    'explorer.exe'
)) {
    if (-not $module.Contains($required)) { throw "Shell Activation V14 module contract missing: $required" }
}

foreach ($forbidden in @(
    'HKEY_LOCAL_MACHINE',
    'HKLM:',
    'Registry]::LocalMachine',
    'Registry.LocalMachine',
    'reg.exe add HKLM',
    'shutdown.exe',
    'logoff.exe',
    'ExitWindowsEx',
    'InitiateSystemShutdown'
)) {
    if ($module.Contains($forbidden)) { throw "Shell Activation V14 introduced forbidden machine-wide/destructive behavior: $forbidden" }
}

foreach ($required in @(
    'Get-CloudOSDeploymentStatus',
    'Test-CloudOSPayload',
    'CloudOS.Supervisor.exe',
    '--probe-ready-once',
    '--probe-no-explorer',
    'Start-ExplorerFallback'
)) {
    if (-not $entry.Contains($required)) { throw "Stable V14 shell entry contract missing: $required" }
}

foreach ($required in @(
    'shell-activation-v14.json',
    'configured as the per-user logon shell',
    'HKCU Winlogon Shell still references this CloudOS install root',
    'DoNotExpandEnvironmentNames'
)) {
    if (-not $uninstall.Contains($required)) { throw "V13 uninstall/V14 safety interlock missing: $required" }
}

foreach ($required in @(
    'Software\CloudOS\Tests\ShellActivationV14\',
    'production_winlogon_unchanged',
    'absent_prior_restored_as_absent',
    'expand_string_prior_type_restored',
    'interrupted_activation_repaired',
    'invalid_active_payload_rejected',
    'uninstall_blocked_while_active',
    'ProbeInterruptAfterRegistryWrite'
)) {
    if (-not $smoke.Contains($required)) { throw "V14 sandbox smoke contract missing: $required" }
}

foreach ($forbidden in @('SetEnabled($TRUE)', 'WESL_UserSetting', 'HKEY_LOCAL_MACHINE', 'HKLM:')) {
    if ($smoke.Contains($forbidden)) { throw "V14 hosted smoke must not use machine-wide Shell Launcher/Winlogon state: $forbidden" }
}

foreach ($required in @(
    'CloudOS.ShellActivation.V14.psm1',
    'activate-cloudos-shell-v14.ps1',
    'rollback-cloudos-shell-v14.ps1',
    'CloudOS.ShellEntry.V14.ps1',
    'Ativar CloudOS como Shell.cmd',
    'Restaurar Explorer.cmd'
)) {
    if (-not $package.Contains($required)) { throw "Portable V14 package contract missing: $required" }
}

if (-not $contractSuite.Contains('test-shell-activation-v14-contract.ps1')) {
    throw 'Central native contract suite does not include the V14 activation contract.'
}
foreach ($required in @('Smoke Shell Activation V14', 'shell-activation-v14-smoke.json')) {
    if (-not $workflow.Contains($required)) { throw "V14 workflow runtime contract missing: $required" }
}

Write-Host 'PASS: Shell Activation V14 safety/rollback/sandbox contracts are locked.'
