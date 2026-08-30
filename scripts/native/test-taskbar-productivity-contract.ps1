$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'

$paths = @{
    Taskbar = Join-Path $src 'native_taskbar_appbar_v4.cpp'
    Hover = Join-Path $src 'native_taskbar_hover_preview.cpp'
    Pins = Join-Path $src 'native_shell_pins.cpp'
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
    'L".bak"',
    'CopyFileW',
    'MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH'
)

Require 'Hierarchical quick-access hub' $content.Launcher @(
    'ShowQuickPowerMenu',
    'L"Central de Comandos  ·  106 acoes"',
    'L"Terminais"',
    'L"Ferramentas"',
    'L"Sistema e configuracoes"',
    'L"Energia do Windows"',
    'L"powershell"',
    'L"wsl"',
    'L"run"',
    'L"drive"',
    'L"ms-settings:network-wifi"',
    'L"ms-settings:windowsupdate"',
    'L"classic.taskmgr"',
    'L"session.restart-cloudos"',
    'L"session.shutdown"'
)

Require 'Native build revision stamp' $content.NativeBuild @(
    'BUILD_HEAD',
    '.cloudos-build-head',
    'git.exe -C',
    'rev-parse HEAD',
    'CloudOS.exe vazio',
    'CloudOS.NativeRuntime.dll vazio'
)
Require 'Stale binary detection' $content.NativeStart @(
    '.cloudos-build-head',
    'CURRENT_HEAD',
    'BUILT_HEAD',
    'REBUILD_REASON',
    'rev-parse HEAD',
    'status --porcelain',
    'o codigo Git mudou desde o ultimo build',
    'existem alteracoes locais no codigo nativo/scripts',
    'build-cloudos-native.cmd'
)

Write-Host 'PASS: Taskbar V4 live geometry, power-user mouse controls, rich DWM preview, self-healing pins, smart Start recommendations, quick-access hub and stale-binary protection are protected.'
