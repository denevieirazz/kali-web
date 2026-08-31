[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$src = Join-Path $Root 'desktop\CloudOS.NativeShell\src'
$paths = @{
    IntegrationHeader = Join-Path $src 'native_integration_v16.h'
    Launchers = Join-Path $src 'native_integration_v16_launchers.h'
    Desktop = Join-Path $src 'native_desktop_model_v12.h'
    StartHeader = Join-Path $src 'native_start_index.h'
    Start = Join-Path $src 'native_start_index.cpp'
    StartMenu = Join-Path $src 'native_start_menu_window.cpp'
    Document = Join-Path $Root 'docs\native\UNIFIED_START_SEARCH_V17.md'
    Roadmap = Join-Path $Root 'docs\native\DESKTOP_SYSTEM_ROADMAP.md'
    CodeMap = Join-Path $Root 'docs\native\CODEMAP.md'
    Agents = Join-Path $Root 'AGENTS.md'
    Validation = Join-Path $Root 'docs\native\VALIDATION.md'
    Suite = Join-Path $PSScriptRoot 'test-native-contract-suite.ps1'
    Smoke = Join-Path $PSScriptRoot 'run-native-unified-start-search-smoke-v17.ps1'
    Workflow = Join-Path $Root '.github\workflows\cloudos-native-full-system.yml'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Unified Start/Search V17 file missing [$($entry.Key)]: $($entry.Value)"
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

Require 'V17 keeps V16 as integration authority' $content.IntegrationHeader @(
    'LinuxApplicationsDirectory',
    'EnsureLinuxLauncherShortcut'
)

Require 'V17 shared managed Linux launcher' $content.Launchers @(
    'NativeIntegrationV16::LinuxApplicationsDirectory',
    'NativeIntegrationV16::EnsureLinuxLauncherShortcut',
    'IntegrationV16',
    'LinuxShortcuts',
    'IShellLinkW',
    'IPersistFile',
    'gtk-launch',
    'static std::mutex shortcut_mutex'
)

Require 'V17 unified Start index' ($content.StartHeader + "`n" + $content.Start) @(
    'NativeStartIndexKind::LinuxApp',
    '#include "native_integration_v16_launchers.h"',
    'NativeIntegrationV16::EnumerateLinuxGuiApps()',
    'NativeIntegrationV16::EnsureLinuxLauncherShortcut(app)',
    'entry.title = app.name + L" · Linux"',
    'entry.subtitle = L"WSL · " + app.distro',
    'ScanLinuxApps(next);',
    'entry.kind == NativeStartIndexKind::LinuxApp'
)
Forbid 'V17 Start consumes integration boundary rather than duplicating WSL commands' $content.Start @(
    'wsl.exe',
    'gtk-launch',
    'FindFirstChangeNotificationW',
    'SetTimer('
)

Require 'V17 event-driven Desktop and Start refresh' $content.Desktop @(
    'reload_desktop',
    'refresh_start_index',
    'NativeIntegrationV16::LinuxApplicationsDirectory(distro)',
    'NativeStartIndex::Instance().RefreshAsync();',
    'NativeIntegrationV16::EnsureLinuxLauncherShortcut(app)',
    'FindFirstChangeNotificationW',
    'FindNextChangeNotification'
)
Forbid 'V17 Desktop no longer owns Linux launcher construction' $content.Desktop @(
    'IShellLinkW',
    'IPersistFile',
    'gtk-launch',
    'SetTimer(',
    'Sleep(1000)',
    'Sleep(2000)'
)

Require 'V17 Start UI describes unified indexed results' $content.StartMenu @(
    'Windows + Linux'
)

Require 'V17 documentation' $content.Document @(
    'NativeIntegrationV16',
    'NativeStartIndex',
    'LinuxShortcuts',
    'event-driven',
    'WSLg',
    'hosted CI',
    'não instala',
    'não altera Winlogon'
)
Require 'V17 roadmap' $content.Roadmap @('V16', 'V17', 'a995ea59d95ddf4c72d7cbc6a08e746edf26e7c3')
Require 'V17 code map' $content.CodeMap @('Unified Start/Search V17', 'native_integration_v16_launchers.h', 'test-unified-start-search-v17-contract.ps1')
Require 'V17 agent guide' $content.Agents @('UNIFIED_START_SEARCH_V17.md', 'native_integration_v16_launchers.h', 'Start/Search')
Require 'V17 validation matrix' $content.Validation @('V16 — Unified Integration', 'V17 — Unified Start/Search', 'run-native-unified-start-search-smoke-v17.ps1')

Require 'V17 hosted smoke is non-mutating' $content.Smoke @(
    "test = 'CloudOS Unified Start Search V17'",
    'production_winlogon_unchanged',
    'mutating_package_operation_executed = $false',
    'supervisor_self_test_exit_code'
)
Require 'Central contract suite contains V17' $content.Suite @('test-unified-start-search-v17-contract.ps1')
Require 'Full-System CI protects V17' $content.Workflow @(
    'Contract Unified Start/Search V17',
    'test-unified-start-search-v17-contract.ps1',
    'Smoke Unified Start/Search V17',
    'run-native-unified-start-search-smoke-v17.ps1',
    'unified-start-search-v17-smoke.json'
)

Write-Host 'PASS: Unified Start/Search V17 protects one Windows+Linux discovery authority, shared Linux launch adapters, app-first Start search and event-driven refresh without polling.'
