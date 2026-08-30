$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'

$paths = @{
    Taskbar = Join-Path $src 'native_taskbar_appbar_v4.cpp'
    Hover = Join-Path $src 'native_taskbar_hover_preview.cpp'
    Pins = Join-Path $src 'native_shell_pins.cpp'
    Start = Join-Path $src 'native_start_menu_window.cpp'
    StartHeader = Join-Path $src 'native_start_menu_window.h'
    Mru = Join-Path $src 'native_start_menu_mru.h'
    Launcher = Join-Path $src 'native_app_launcher_v3.cpp'
    NativeBuild = Join-Path $root 'scripts\native\build-cloudos-native.cmd'
    NativeStart = Join-Path $root 'scripts\native\start-cloudos-native.cmd'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Shell productivity contract file missing [$($entry.Key)]: $($entry.Value)"
    }
}

$content = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

function Require([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) {
            throw "$Name contract missing: $token"
        }
    }
}

function Forbid([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if ($Text.Contains($token)) {
            throw "$Name forbidden regression found: $token"
        }
    }
}

Require 'Taskbar V4 live geometry' $content.Taskbar @(
    'CloudOS.NativeShell.Taskbar.v4',
    'CLOUDOS_WM_TASKBAR_QUERY_HIT',
    'HitTaskWindow',
    'TaskGroup',
    'visible_task_group_count_',
    'task_overflow_rect_'
)

Require 'Taskbar live preview productivity' $content.Hover @(
    'CloudOS.NativeShell.TaskPreview.v2',
    'ResolveWindowIcon',
    'DwmRegisterThumbnail',
    'DwmUpdateThumbnailProperties',
    'WM_MBUTTONUP',
    'WM_MOUSEWHEEL',
    'WM_XBUTTONUP',
    'GET_WHEEL_DELTA_WPARAM',
    'GET_XBUTTON_WPARAM',
    'MoveActiveToWorkspace',
    'SwitchWorkspace',
    'WrappedWorkspace',
    'WebSkin::Danger'
)
Forbid 'Taskbar live preview productivity' $content.Hover @(
    'kPinnedCount = 5'
)

Require 'Persistent pin recovery' $content.Pins @(
    'shell_pins_v1.dat',
    'BackupPath',
    'ReadStoreFile',
    'L".bak"',
    'CopyFileW',
    'MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH',
    'FILE_FLAG_WRITE_THROUGH',
    'Deduplicate'
)

Require 'Smart Start recommendations' $content.Mru @(
    'start_mru.dat',
    'UsageScore',
    'kRecencyWindowDays',
    'kRecencyWeightPerDay',
    'kFrequencyWeight',
    'ReadUsageFile',
    'void Clear()',
    'usage_map_.clear()',
    'L".bak"',
    'CopyFileW',
    'MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH'
)

Require 'Keyboard-first Start Home header contract' $content.StartHeader @(
    'MoveHomeSelection',
    'SelectHomeEdge',
    'ActivateHomeSelection',
    'ShowHomeSelectionContextMenu',
    'keyboard_home_navigation_'
)

Require 'Keyboard-first Start Home implementation' $content.Start @(
    'MoveHomeSelection(int horizontal, int vertical)',
    'SelectHomeEdge(bool last)',
    'ActivateHomeSelection()',
    'ShowHomeSelectionContextMenu()',
    'keyboard_home_navigation_',
    'VK_LEFT',
    'VK_RIGHT',
    'VK_UP',
    'VK_DOWN',
    'VK_HOME',
    'VK_END',
    'VK_RETURN',
    'VK_SPACE',
    'VK_APPS',
    'VK_F10',
    'WM_CHAR',
    'GetKeyState(VK_SHIFT)',
    'GetKeyState(VK_CONTROL)',
    'L"Setas navegam  ·  Enter abre  ·  Shift+F10 menu',
    'L"Redefinir recomendacoes"',
    'StartMenuMRUTracker::Instance().Clear()',
    'WebSkin::Accent'
)
Forbid 'Keyboard-first Start Home implementation' $content.Start @(
    'self->view_mode_ = ViewMode::AllApps;\n                self->RefreshResults();\n            }\n            self->MoveSelection(1)'
)

Require 'Expanded hierarchical quick-access hub' $content.Launcher @(
    'ShowQuickPowerMenu',
    'L"Central de Comandos  ·  106 acoes"',
    'L"CloudOS e desenvolvimento"',
    'L"Terminais"',
    'L"Produtividade"',
    'L"Ferramentas do sistema"',
    'L"Sistema e configuracoes"',
    'L"Energia do Windows"',
    'L"projects"',
    'L"code"',
    'L"powershell"',
    'L"wsl"',
    'L"paint"',
    'L"media"',
    'L"weather"',
    'L"devmgmt.msc"',
    'L"ms-settings:display"',
    'L"ms-settings:sound"',
    'L"ms-settings:network-status"',
    'L"ms-settings:network-wifi"',
    'L"ms-settings:bluetooth"',
    'L"ms-settings:storagesense"',
    'L"ms-settings:clipboard"',
    'L"ms-settings:developers"',
    'L"ms-settings:windowsdefender"',
    'L"ms-settings:windowsupdate"',
    'L"classic.taskmgr"',
    'L"session.restart-cloudos"',
    'L"session.shutdown"'
)

Require 'Native build provenance' $content.NativeBuild @(
    'cloudos-native-manifest.json',
    '.cloudos-build-fingerprint',
    'write-native-build-manifest.ps1',
    'verify-native-build-manifest.ps1',
    'SOURCE_FINGERPRINT',
    'CloudOS.exe vazio',
    'CloudOS.NativeRuntime.dll vazio'
)
Require 'Fingerprint stale binary detection' $content.NativeStart @(
    '.cloudos-build-fingerprint',
    'FINGERPRINT_SCRIPT',
    'CURRENT_FINGERPRINT',
    'BUILT_FINGERPRINT',
    'REBUILD_REASON',
    'o codigo nativo mudou desde o ultimo build',
    'a verificacao de integridade/proveniencia falhou',
    '--force-rebuild',
    '--no-build',
    'taskkill /F /IM CloudOS.exe',
    'build-cloudos-native.cmd'
)

$buildLabel = $content.NativeStart.IndexOf(':BUILD')
$killBeforeBuild = $content.NativeStart.IndexOf('taskkill /F /IM CloudOS.exe', $buildLabel)
$buildCall = $content.NativeStart.IndexOf('build-cloudos-native.cmd', $buildLabel)
if ($buildLabel -lt 0 -or $killBeforeBuild -lt 0 -or $buildCall -lt 0 -or $killBeforeBuild -gt $buildCall) {
    throw 'Native launcher must stop CloudOS.exe before invoking an automatic rebuild.'
}

Write-Host 'PASS: Taskbar V4 productivity, keyboard-first Start Home, resettable smart recommendations, expanded quick-access hub and fingerprint-verified rebuilds are protected.'
