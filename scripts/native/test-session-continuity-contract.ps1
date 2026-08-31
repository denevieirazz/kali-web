$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'
$paths = @{
    ModelHeader = Join-Path $src 'native_session_continuity_model.h'
    Model = Join-Path $src 'native_session_continuity_model.cpp'
    ServiceHeader = Join-Path $src 'native_session_continuity_service.h'
    Service = Join-Path $src 'native_session_continuity_service.cpp'
    WindowHeader = Join-Path $src 'native_session_continuity_window.h'
    Window = Join-Path $src 'native_session_continuity_window.cpp'
    LabelsHeader = Join-Path $src 'native_workspace_labels.h'
    Labels = Join-Path $src 'native_workspace_labels.cpp'
    ManagerBridge = Join-Path $src 'native_window_manager_workspace_studio.cpp'
    DesktopMenu = Join-Path $src 'native_desktop_context_menu.cpp'
    Project = Join-Path $root 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Continuity V3 contract file missing [$($entry.Key)]: $($entry.Value)"
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

Require 'Continuity persistent ledger' ($content.ModelHeader + "`n" + $content.Model) @(
    'ContinuityPreferences',
    'ContinuityWindowState',
    'ContinuityCheckpoint',
    'ContinuityJournalEvent',
    'continuity_v3.dat',
    'kVersion = 3u',
    'MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH',
    'L".tmp"',
    'L".bak"',
    'CopyFileW',
    'FlushFileBuffers',
    'retention_per_workspace',
    'kMaximumCheckpoints',
    'kMaximumEvents',
    'RepairCounters',
    'LoadedFromBackup'
)

Require 'Checkpoint geometry engine' $content.Service @(
    'NormalizeBounds',
    'DenormalizeBounds',
    'NativeMonitorManager::Enumerate',
    'MonitorDevice',
    'MonitorWorkByDevice',
    'NativeWorkspaceAutomationEngine::IdentifyWindow',
    'MatchScore',
    'RestoreWindowState',
    'WorkspaceSignature',
    'HandleAutoCheckpoint',
    'CaptureCheckpoint',
    'RestoreCheckpoint'
)

Require 'Resident continuity daemon' ($content.ServiceHeader + "`n" + $content.Service) @(
    'NativeSessionContinuityService',
    'RegisterManager',
    'HWND_MESSAGE',
    'kEngineIntervalMs = 5000u',
    'RegisterHotKey',
    'MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT',
    'kHotOpenCenter',
    'kHotCheckpoint',
    'kHotRestoreLatest',
    'continuity_v3.live',
    'previous_unclean_',
    'HandleInitialResume',
    'HandleWorkspaceChange',
    'HandleFocusChange'
)

Require 'Crash-safe conservative restore' $content.Service @(
    'restore_after_unclean',
    'restore_last_workspace',
    'SessionRecovered',
    'CheckpointRestored',
    'CheckpointFailed',
    'used.contains',
    'best_score < 4'
)
Forbid 'Continuity must not relaunch external processes' $content.Service @(
    'ShellExecuteW',
    'CreateProcessW',
    'WinExec(',
    'system(',
    'SetParent('
)

Require 'Four-page native Continuity Center header' $content.WindowHeader @(
    'Session = 0',
    'Checkpoints = 1',
    'Journal = 2',
    'Preferences = 3',
    'SavePreferences',
    'RestoreSelectedCheckpoint',
    'CaptureCurrentCheckpoint',
    'FocusSelectedWindow'
)
Require 'Four-page native Continuity Center implementation' $content.Window @(
    'CloudOS.NativeShell.SessionContinuity.Center.v3',
    'Central de Continuidade - CloudOS',
    'L"Sessão"',
    'L"Checkpoints"',
    'L"Journal"',
    'L"Preferências"',
    'L"Salvar agora"',
    'L"Restaurar selecionado"',
    'L"Capturar estado atual"',
    'L"Ativar Session Continuity"',
    'ApplyWebWindowMaterial',
    'LVS_EX_DOUBLEBUFFER'
)
Forbid 'Continuity Center is native-only' $content.Window @(
    'WebView2',
    '<html',
    'React',
    'SetParent('
)

Require 'Workspace identity labels' ($content.LabelsHeader + "`n" + $content.Labels) @(
    'NativeWorkspaceLabels',
    'NativeWorkspaceStudioService::Instance().Store().Profiles()',
    'NumberedName',
    'CompactName',
    'StatusText'
)

Require 'Window manager registration' $content.ManagerBridge @(
    'NativeWorkspaceStudioService::RegisterManager(this)',
    'NativeSessionContinuityService::RegisterManager(this)'
)

Require 'Desktop discovery' $content.DesktopMenu @(
    'kContinuityCenter = 9114',
    'L"Central de Continuidade..."',
    'NativeSessionContinuityService::Open(instance, owner)'
)

Require 'MSVC continuity compile graph' $content.Project @(
    'src\native_session_continuity_model.h',
    'src\native_session_continuity_service.h',
    'src\native_session_continuity_window.h',
    'src\native_workspace_labels.h',
    'src\native_session_continuity_model.cpp',
    'src\native_session_continuity_service.cpp',
    'src\native_session_continuity_window.cpp',
    'src\native_workspace_labels.cpp'
)

Write-Host 'PASS: Session Continuity V3 contracts passed - atomic ledger, per-workspace checkpoints, monitor-normalized geometry, crash marker, conservative restore, journal, four-page native center, global hotkeys and workspace identity labels are protected.'
