$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'

$paths = @{
    Overview = Join-Path $src 'native_workspace_overview_window.cpp'
    OverviewHeader = Join-Path $src 'native_workspace_overview_window.h'
    Bridge = Join-Path $src 'native_shell_bridge.cpp'
    BridgeHeader = Join-Path $src 'native_shell_bridge.h'
    Main = Join-Path $src 'main_shell_v2.cpp'
    Theme = Join-Path $src 'native_theme.h'
    Launcher = Join-Path $src 'native_app_launcher_v4.cpp'
    Search = Join-Path $src 'native_search_engine.cpp'
    Project = Join-Path $root 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Workspace overview contract path missing [$($entry.Key)]: $($entry.Value)"
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

Require 'Workspace overview header' $content.OverviewHeader @(
    'CloudOSNativeWorkspaceOverviewWindow',
    'WindowRow',
    'RefreshRows',
    'RebuildPreview',
    'MoveSelectedToWorkspace',
    'ToggleFloatingSelected',
    'ShowSelectedContextMenu',
    'HTHUMBNAIL',
    'workspace_cards_',
    'workspace_counts_'
)

Require 'Workspace overview implementation' $content.Overview @(
    'CloudOS.NativeShell.WorkspaceOverview.v1',
    'Visão de Trabalho - CloudOS',
    'Pesquisar janela, PID ou área',
    'AllManagedWindows',
    'ManagedWindowCount',
    'CurrentWorkspace',
    'SwitchWorkspace',
    'MoveActiveToWorkspace',
    'SetWindowFloating',
    'ToggleTiling',
    'DwmRegisterThumbnail',
    'DwmQueryThumbnailSourceSize',
    'DwmUpdateThumbnailProperties',
    'DwmUnregisterThumbnail',
    'LVS_REPORT',
    'LVS_EX_FULLROWSELECT',
    'NM_DBLCLK',
    'NM_RCLICK',
    'VK_DELETE',
    'VK_SPACE',
    'VK_PRIOR',
    'VK_NEXT',
    'VK_APPS',
    'GetKeyState(VK_SHIFT)',
    'GetKeyState(VK_CONTROL)',
    'Ctrl+Alt+O',
    'Shift+1..4 move'
)
Forbid 'Workspace overview native-only surface' $content.Overview @(
    'WebView2',
    'SetParent(',
    '<html',
    'React'
)

Require 'In-process shell bridge header' $content.BridgeHeader @(
    'SetWorkspaceOverviewCallback',
    'SetShowDesktopCallback',
    'OpenWorkspaceOverview',
    'ToggleShowDesktop',
    'Clear() noexcept'
)
Require 'In-process shell bridge implementation' $content.Bridge @(
    'std::mutex',
    'std::scoped_lock',
    'g_workspace_overview_callback',
    'g_show_desktop_callback',
    'callback = g_workspace_overview_callback',
    'callback = g_show_desktop_callback'
)

Require 'Main shell overview integration' $content.Main @(
    '#include "native_shell_bridge.h"',
    '#include "native_workspace_overview_window.h"',
    'kHotWorkspaceOverview',
    'kHotWorkspacePrevious',
    'kHotWorkspaceNext',
    'kHotMoveWorkspacePrevious',
    'kHotMoveWorkspaceNext',
    'kHotShowDesktop',
    'workspace_overview_.Create(instance_, &window_manager_)',
    'SetupShellBridge()',
    'SetWorkspaceOverviewCallback',
    'SetShowDesktopCallback',
    'ToggleShowDesktopCurrentWorkspace',
    'CurrentWorkspaceWindows',
    'SwitchWorkspaceRelative',
    'MoveActiveToRelativeWorkspace',
    '{kHotWorkspaceOverview, modifiers, L''O''}',
    '{kHotWorkspacePrevious, modifiers, VK_PRIOR}',
    '{kHotWorkspaceNext, modifiers, VK_NEXT}',
    '{kHotMoveWorkspacePrevious, move_modifiers, VK_PRIOR}',
    '{kHotMoveWorkspaceNext, move_modifiers, VK_NEXT}',
    '{kHotShowDesktop, modifiers, L''D''}',
    'NativeShellBridge::Clear()',
    'workspace_overview_.Destroy()'
)

Require 'Start catalog entry' $content.Theme @(
    'std::array<AppItem, 23>',
    '{L"workspaces", L"Visão de Trabalho"',
    'Gerenciar as 4 áreas, janelas, tiling e previews DWM'
)

Require 'Launcher bridge integration' $content.Launcher @(
    '#include "native_shell_bridge.h"',
    'id == L"workspace"',
    'id == L"overview"',
    'id == L"task-view"',
    'return L"workspaces"',
    'id == L"workspaces"',
    'NativeShellBridge::OpenWorkspaceOverview()',
    'kWorkspaces = 1141',
    'kShowDesktop = 1142',
    'L"Visão de Trabalho  ·  Ctrl+Alt+O"',
    'L"Mostrar Área de Trabalho  ·  Ctrl+Alt+D"',
    'NativeShellBridge::ToggleShowDesktop()'
)

Require 'Start search aliases' $content.Search @(
    'L"workspace"',
    'L"workspaces"',
    'L"overview"',
    'L"task view"',
    'L"mission control"',
    'L"desktop virtual"',
    'return id == L"workspaces"'
)

Require 'MSVC compile graph' $content.Project @(
    'src\native_shell_bridge.h',
    'src\native_workspace_overview_window.h',
    'src\native_shell_bridge.cpp',
    'src\native_workspace_overview_window.cpp',
    'src\native_app_launcher_v4.cpp'
)
Forbid 'MSVC compile graph' $content.Project @(
    '<ClCompile Include="src\native_app_launcher_v3.cpp"'
)

Write-Host 'PASS: native Workspace Overview, DWM previews, global workspace controls, Start/launcher discovery and in-process shell bridge contracts are protected.'
