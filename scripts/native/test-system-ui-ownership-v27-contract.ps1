[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Assert-FileContains {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string[]]$Needles,
        [string]$Description = ''
    )

    $fullPath = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "File missing for contract ($Description): $RelativePath"
    }

    $content = Get-Content -LiteralPath $fullPath -Raw
    foreach ($needle in $Needles) {
        if (-not $content.Contains($needle)) {
            throw "Contract check failed in $RelativePath ($Description). Expected to contain: '$needle'"
        }
    }
}

function Assert-FileNotContains {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string[]]$Needles,
        [string]$Description = ''
    )

    $fullPath = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "File missing for contract ($Description): $RelativePath"
    }

    $content = Get-Content -LiteralPath $fullPath -Raw
    foreach ($needle in $Needles) {
        if ($content.Contains($needle)) {
            throw "Contract check failed in $RelativePath ($Description). Forbidden content found: '$needle'"
        }
    }
}

Write-Host "Verifying System UI Ownership V27 Contract..." -ForegroundColor Cyan

# 1. First-Party Settings Ownership (12 Sections + Display 15s Rollback)
Assert-FileContains -RelativePath 'desktop\CloudOS.FlutterShell\lib\features\settings\presentation\settings_window.dart' -Needles @(
    'enum SettingsSection',
    'display(',
    'sound(',
    'power(',
    'storage(',
    'performance(',
    'network(',
    'bluetooth(',
    'personalization(',
    'wsl(',
    'recovery(',
    'diagnostics(',
    'about(',
    '_showRevertConfirmationDialog',
    '_revertCountdown',
    'restoreDisplayMode',
    'Revertendo automaticamente'
) -Description 'SettingsWindow 12 Sections and 15s Display Confirmation'

# 2. Open With Dialog (CloudOS First-Party + Windows/WSL App Association)
Assert-FileContains -RelativePath 'desktop\CloudOS.FlutterShell\lib\features\files\presentation\widgets\cloudos_open_with_dialog.dart' -Needles @(
    'class CloudOSOpenWithDialog',
    'Abrir com o CloudOS',
    'CloudOS Notes',
    'Sempre usar este aplicativo'
) -Description 'First-Party CloudOS Open With Dialog'

# 3. Task Manager with Live System Metrics
Assert-FileContains -RelativePath 'desktop\CloudOS.FlutterShell\lib\features\task_manager\presentation\task_manager_window.dart' -Needles @(
    'class TaskManagerWindow',
    'getHardwareMetrics',
    'Memória RAM',
    'Subsistema Linux (WSL)',
    'Ações de Gerenciamento'
) -Description 'TaskManagerWindow Live Hardware & Process Supervision'

# 4. Zero-Leakage Shell Routing in Flutter
Assert-FileContains -RelativePath 'desktop\CloudOS.FlutterShell\lib\shell\cloudos_shell.dart' -Needles @(
    '_openSettingsSection',
    '_openQuickSettingsRoute',
    'SettingsSection.display',
    'SettingsSection.network',
    'SettingsSection.bluetooth'
) -Description 'Flutter Shell System UI Routing'

# 5. Broker Fail-Closed Protection Against Explorer & MS-Settings Leakage
Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\app_service_v21.cpp' -Needles @(
    'CloudOS Files is a first-party Flutter surface and must be opened by the CloudOS shell',
    'CloudOS Settings is a first-party Flutter surface and must be opened by the CloudOS shell',
    'CloudOS Calculator is a first-party Flutter surface and must be opened by the CloudOS shell'
) -Description 'Broker Fail-Closed Protection on Shell Surfaces'

Assert-FileNotContains -RelativePath 'desktop\CloudOS.SystemBroker\src\app_service_v21.cpp' -Needles @(
    'ShellExecuteW(nullptr, L"open", route.uri',
    'control.exe'
) -Description 'Broker Forbidden Leakage to external settings UI and control.exe'

Write-Host "Contract System UI Ownership V27 PASSED!" -ForegroundColor Green
