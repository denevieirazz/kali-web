$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'

$paths = @{
    Taskbar = Join-Path $src 'native_taskbar_appbar_v4.cpp'
    Hover = Join-Path $src 'native_taskbar_hover_preview.cpp'
    Pins = Join-Path $src 'native_shell_pins.cpp'
    Mru = Join-Path $src 'native_start_menu_mru.h'
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

Write-Host 'PASS: Taskbar V4 live geometry, middle-click close, wheel/XButton workspaces, rich DWM preview, self-healing pins and smart Start recommendations are protected.'
