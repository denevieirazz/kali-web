param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)

$ErrorActionPreference = 'Stop'
$rootPath = (Resolve-Path -LiteralPath $Root).Path
$modulePath = Join-Path $rootPath 'scripts\native\CloudOS.Deployment.V13.psm1'
$packagePath = Join-Path $rootPath 'scripts\native\package-cloudos-native.ps1'
$contractSuitePath = Join-Path $rootPath 'scripts\native\test-native-contract-suite.ps1'
$workflowPath = Join-Path $rootPath '.github\workflows\cloudos-native-full-system.yml'

foreach ($path in @($modulePath, $packagePath, $contractSuitePath, $workflowPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "V13 contract input missing: $path" }
}

$module = Get-Content -LiteralPath $modulePath -Raw
foreach ($required in @(
    'schema = $script:DeploymentSchema',
    "last_known_good = $null",
    'deployment-v13.journal.json',
    'FileShare]::None',
    'Test-CloudOSPayload',
    'CloudOS.Supervisor.exe',
    '--self-test',
    'Assert-CloudOSManagedInstallRoot',
    'Source validation occurs before any active-state mutation.',
    'Invoke-CloudOSRollback',
    'Invoke-CloudOSRepair'
)) {
    if (-not $module.Contains($required)) { throw "V13 deployment safety contract missing: $required" }
}

foreach ($forbidden in @(
    'Winlogon',
    'HKLM:',
    'HKEY_LOCAL_MACHINE',
    'Set-ItemProperty',
    'New-ItemProperty',
    'Remove-ItemProperty',
    'reg.exe add',
    'RegSetValue'
)) {
    if ($module.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "V13 deployment must not modify Windows shell/registry state: $forbidden"
    }
}

Import-Module -Name $modulePath -Force
foreach ($command in @(
    'Invoke-CloudOSDeployment',
    'Invoke-CloudOSRollback',
    'Invoke-CloudOSRepair',
    'Invoke-CloudOSUninstall',
    'Get-CloudOSDeploymentStatus'
)) {
    if ($null -eq (Get-Command $command -ErrorAction SilentlyContinue)) { throw "V13 exported command missing: $command" }
}

$package = Get-Content -LiteralPath $packagePath -Raw
foreach ($name in @(
    'CloudOS.Deployment.V13.psm1',
    'install-cloudos-native-v13.ps1',
    'update-cloudos-native-v13.ps1',
    'rollback-cloudos-native-v13.ps1',
    'repair-cloudos-native-v13.ps1',
    'uninstall-cloudos-native-v13.ps1',
    'Instalar CloudOS.cmd',
    'Atualizar CloudOS.cmd',
    'Rollback CloudOS.cmd'
)) {
    if (-not $package.Contains($name)) { throw "Portable package does not expose V13 deployment capability: $name" }
}

$contractSuite = Get-Content -LiteralPath $contractSuitePath -Raw
if (-not $contractSuite.Contains('test-transactional-deployment-v13-contract.ps1')) {
    throw 'Central native contract suite does not include the V13 deployment contract.'
}

$workflow = Get-Content -LiteralPath $workflowPath -Raw
foreach ($required in @('run-native-deployment-smoke-v13.ps1', 'deployment-v13-smoke.json')) {
    if (-not $workflow.Contains($required)) { throw "Full-System CI does not protect V13 deployment runtime behavior: $required" }
}

Write-Host 'PASS: Transactional Deployment V13 contract is enforced (per-user filesystem deployment only; no Winlogon/registry activation).'
