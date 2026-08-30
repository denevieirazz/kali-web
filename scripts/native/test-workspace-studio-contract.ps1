$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'
$paths = @{
    ModelHeader = Join-Path $src 'native_workspace_studio_model.h'
    Model = Join-Path $src 'native_workspace_studio_model.cpp'
    AutomationHeader = Join-Path $src 'native_workspace_automation.h'
    Automation = Join-Path $src 'native_workspace_automation.cpp'
    ServiceHeader = Join-Path $src 'native_workspace_studio_service.h'
    Service = Join-Path $src 'native_workspace_studio_service.cpp'
    WindowHeader = Join-Path $src 'native_workspace_studio_window.h'
    Window = Join-Path $src 'native_workspace_studio_window.cpp'
    ManagerHeader = Join-Path $src 'native_window_manager.h'
    ManagerBridge = Join-Path $src 'native_window_manager_workspace_studio.cpp'
    DesktopMenu = Join-Path $src 'native_desktop_context_menu.cpp'
    Project = Join-Path $root 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Workspace Studio contract file missing [$($entry.Key)]: $($entry.Value)"
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

Require 'Persistent workspace model' ($content.ModelHeader + "`n" + $content.Model) @(
    'WorkspaceProfile',
    'WorkspaceRule',
    'WorkspaceLaunchEntry',
    'WorkspaceSnapshot',
    'WorkspaceLayoutWindow',
    'WorkspaceLayoutPreset',
    'Grid = 3',
    'WorkspaceMatchField',
    'WorkspaceMatchMode',
    'workspace_studio_v2.dat',
    'FOLDERID_LocalAppData',
    'MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH',
    'CopyFileW',
    'L".bak"',
    'kVersion = 2',
    'kMaximumCollection'
)

Require 'Rule and focus automation' ($content.AutomationHeader + "`n" + $content.Automation) @(
    'WorkspaceWindowIdentity',
    'WorkspaceFocusRecord',
    'QueryFullProcessImageNameW',
    'GetClassNameW',
    'GetWindowTextW',
    'WorkspaceMatchField::ProcessName',
    'WorkspaceMatchField::WindowTitle',
    'WorkspaceMatchField::WindowClass',
    'WorkspaceMatchMode::Wildcard',
    'WildcardMatch',
    'processed_windows_',
    'MoveWindowToWorkspace',
    'SetWindowFloating',
    'FocusHistoryItem',
    'ClearFocusHistory'
)

Require 'Layout snapshots and presets' $content.Automation @(
    'NormalizeBounds',
    'DenormalizeBounds',
    'MonitorDeviceName',
    'NativeMonitorManager::Enumerate',
    'monitor.work',
    'GetWindowPlacement',
    'WorkspaceLayoutPreset::MasterStack',
    'WorkspaceLayoutPreset::Columns',
    'WorkspaceLayoutPreset::Focus',
    'std::sqrt',
    'std::ceil',
    'NativeWorkspaceLayoutEngine::Capture',
    'NativeWorkspaceLayoutEngine::Restore',
    'NativeWorkspaceLayoutEngine::ApplyPreset'
)

Require 'Workspace transitions' ($content.AutomationHeader + "`n" + $content.Automation) @(
    'HandleWorkspaceTransition',
    'NativeWallpaperManager::Apply',
    'LaunchWorkspaceEntries',
    'NativeAppLauncher::LaunchById',
    'profile.auto_launch',
    'profile.apply_wallpaper',
    'profile.auto_tile',
    'startup_launched_',
    '!startup_launched_'
)

Require 'Resident service' ($content.ServiceHeader + "`n" + $content.Service) @(
    'NativeWorkspaceStudioService',
    'RegisterManager',
    'HWND_MESSAGE',
    'kEngineIntervalMs = 850',
    'RegisterHotKey',
    'MOD_CONTROL',
    'MOD_ALT',
    'MOD_SHIFT',
    'MOD_NOREPEAT',
    'kHotOpenStudio',
    'kHotQuickSnapshot',
    'kHotRestoreSnapshot',
    'kHotReapplyRules',
    'CaptureQuickSnapshot',
    'RestoreLatestSnapshot',
    'ApplyCurrentProfile',
    'automation_.Tick'
)

Require 'Five-page native Studio header' $content.WindowHeader @(
    'enum class Page',
    'Profiles = 0',
    'Rules = 1',
    'Layouts = 2',
    'Startup = 3',
    'Activity = 4',
    'SaveProfile',
    'AddRule',
    'CaptureLayout',
    'AddStartupEntry',
    'FocusHistorySelection'
)
Require 'Five-page native Studio implementation' $content.Window @(
    'CloudOS.NativeShell.WorkspaceStudio.v2',
    'Workspace Studio - CloudOS',
    'L"Perfis"',
    'L"Regras"',
    'L"Layouts"',
    'L"Inicialização"',
    'L"Atividade"',
    'L"Salvar perfil"',
    'L"Adicionar regra"',
    'L"Capturar estado atual"',
    'L"Executar área agora"',
    'L"Focar selecionada"',
    'ApplyWebWindowMaterial',
    'HandleListViewCustomDraw',
    'GetOpenFileNameW'
)
Forbid 'Studio native-only UI' $content.Window @(
    'WebView2',
    '<html',
    'React',
    'SetParent('
)

Require 'Desktop discovery' $content.DesktopMenu @(
    '#include "native_workspace_studio_service.h"',
    'kWorkspaceStudio = 9113',
    'L"Workspace Studio..."',
    'NativeWorkspaceStudioService::Open(instance, owner)'
)

Require 'Window manager workspace API' ($content.ManagerHeader + "`n" + $content.ManagerBridge) @(
    'CloudOSNativeWindowManager();',
    'SetTilingEnabled(bool enabled)',
    'MoveWindowToWorkspace(HWND window, int workspace)',
    'NativeWorkspaceStudioService::RegisterManager(this)',
    'MarkWorkspaceHidden',
    'ShowWindow(window, SW_HIDE)',
    'TileCurrentWorkspace',
    'UpdateBorders'
)

Require 'MSVC compile graph' $content.Project @(
    'src\native_workspace_studio_model.h',
    'src\native_workspace_studio_model.cpp',
    'src\native_workspace_automation.h',
    'src\native_workspace_automation.cpp',
    'src\native_workspace_studio_service.h',
    'src\native_workspace_studio_service.cpp',
    'src\native_workspace_studio_window.h',
    'src\native_workspace_studio_window.cpp',
    'src\native_window_manager_workspace_studio.cpp',
    'native_workspace_automation_compile.h'
)

Write-Host 'PASS: Workspace Studio V2 contracts passed - persistent profiles, window rules, monitor-normalized layouts/grid, startup-once presets, focus history, resident engine, global hotkeys, desktop discovery and five native pages are protected.'
