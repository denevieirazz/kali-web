[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$src = Join-Path $Root 'desktop\CloudOS.NativeShell\src'
$paths = @{
    Maintenance = Join-Path $src 'native_package_maintenance_v17.h'
    AppsHeader = Join-Path $src 'native_apps_window.h'
    Apps = Join-Path $src 'native_apps_window.cpp'
    Document = Join-Path $Root 'docs\native\PACKAGE_MAINTENANCE_V17.md'
    CodeMap = Join-Path $Root 'docs\native\CODEMAP.md'
    Agents = Join-Path $Root 'AGENTS.md'
    Validation = Join-Path $Root 'docs\native\VALIDATION.md'
    Roadmap = Join-Path $Root 'docs\native\DESKTOP_SYSTEM_ROADMAP.md'
    Suite = Join-Path $PSScriptRoot 'test-native-contract-suite.ps1'
    Smoke = Join-Path $PSScriptRoot 'run-native-package-maintenance-smoke-v17.ps1'
    Workflow = Join-Path $Root '.github\workflows\cloudos-native-full-system.yml'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Package Maintenance V17 file missing [$($entry.Key)]: $($entry.Value)"
    }
}

$content = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

function Require {
    param([string]$Name, [string]$Text, [string[]]$Tokens)
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) { throw "$Name contract missing: $token" }
    }
}

function Forbid {
    param([string]$Name, [string]$Text, [string[]]$Tokens)
    foreach ($token in $Tokens) {
        if ($Text.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "$Name forbidden regression found: $token"
        }
    }
}

function Body {
    param([string]$Text, [string]$Signature)
    $start = $Text.IndexOf($Signature)
    if ($start -lt 0) { throw "V17 contract function missing: $Signature" }
    $start = $Text.IndexOf('{', $start)
    if ($start -lt 0) { throw "V17 contract function body missing: $Signature" }
    $depth = 1
    $end = $start + 1
    while ($depth -gt 0 -and $end -lt $Text.Length) {
        if ($Text[$end] -eq '{') { $depth++ }
        elseif ($Text[$end] -eq '}') { $depth-- }
        $end++
    }
    if ($depth -ne 0) { throw "V17 contract unbalanced function: $Signature" }
    return $Text.Substring($start, $end - $start)
}

Require 'Package maintenance boundary' $content.Maintenance @(
    'NativePackageMaintenanceV17',
    'CanUpgrade',
    'BuildWindowsUpgradeCommand',
    ' upgrade --name ',
    '--exact --accept-package-agreements --accept-source-agreements',
    'BuildLinuxUpgradeCommand',
    'flatpak update ',
    'sudo snap refresh ',
    'sudo apt install --only-upgrade -- ',
    'dpkg-query -S --',
    'SafeLinuxToken',
    'KnownLinuxManager',
    'QuoteWindowsArgument'
)
Forbid 'Package maintenance stays explicit and scoped' $content.Maintenance @(
    'upgrade --all',
    'apt upgrade',
    'dist-upgrade',
    'full-upgrade',
    'autoremove',
    'RegSetValue',
    'RegCreateKey',
    'RegDeleteKey',
    'CreateServiceW',
    'ShellExecuteW(',
    'CreateProcessW('
)

Require 'Apps V17 maintenance surface' ($content.AppsHeader + "`n" + $content.Apps) @(
    '#include "native_package_maintenance_v17.h"',
    'update_button_',
    'L"Atualizar app"',
    'void CloudOSNativeAppsWindow::UpdateSelection()',
    'NativePackageMaintenanceV17::CanUpgrade',
    'NativePackageMaintenanceV17::BuildWindowsUpgradeCommand',
    'NativePackageMaintenanceV17::BuildLinuxUpgradeCommand',
    'existing->kind = AppKind::InstalledWindows;',
    'MB_YESNO',
    'CloudOSNativeTerminalWindow::Open',
    'L"Recarregar"'
)

$loadCatalog = Body -Text $content.Apps -Signature 'void CloudOSNativeAppsWindow::LoadCatalog()'
Forbid 'Catalog discovery must not mutate package state' $loadCatalog @(
    'BuildWindowsUpgradeCommand',
    'BuildLinuxUpgradeCommand',
    'CloudOSNativeTerminalWindow::Open',
    'upgrade --name',
    'sudo apt install --only-upgrade'
)

Require 'V17 documentation' $content.Document @(
    'WinGet',
    'apt',
    'Snap',
    'Flatpak',
    'Terminal',
    'confirmação',
    'Hosted CI',
    'não atualiza pacotes reais'
)
Require 'V17 code map' $content.CodeMap @('native_package_maintenance_v17.h', 'Package Maintenance V17')
Require 'V17 agent boundary' $content.Agents @('native_package_maintenance_v17.h', 'V17')
Require 'V17 validation matrix' $content.Validation @('V17 — Package Maintenance', 'run-native-package-maintenance-smoke-v17.ps1')
Require 'V17 roadmap' $content.Roadmap @('| V16 |', '| V17 |')

Require 'Non-mutating V17 smoke' $content.Smoke @(
    "test = 'CloudOS Package Maintenance V17'",
    'mutating_package_operation_executed = $false',
    'production_winlogon_unchanged',
    'No package upgrade was executed.'
)
Require 'Central contract suite contains V17' $content.Suite @('test-package-maintenance-v17-contract.ps1')
Require 'Full-System CI protects V17' $content.Workflow @(
    'Contract Package Maintenance V17',
    'test-package-maintenance-v17-contract.ps1',
    'Smoke Package Maintenance V17',
    'run-native-package-maintenance-smoke-v17.ps1',
    'package-maintenance-v17-smoke.json'
)

Write-Host 'PASS: Package Maintenance V17 contracts passed - explicit WinGet/apt/Snap/Flatpak upgrade flows, safe package identity handling, user confirmation and non-mutating hosted validation are protected.'
