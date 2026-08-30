$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'

$paths = @{
    Project = Join-Path $root 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
    Launcher = Join-Path $src 'native_app_launcher_v3.cpp'
    Header = Join-Path $src 'native_files_window.h'
    Window = Join-Path $src 'native_files_window_v5.cpp'
    Navigation = Join-Path $src 'native_files_navigation_v5.cpp'
    Support = Join-Path $src 'native_files_support_v5.cpp'
    Operations = Join-Path $src 'native_files_operations.cpp'
    OperationWindow = Join-Path $src 'native_file_operations_window.cpp'
    State = Join-Path $src 'native_files_state.cpp'
    StateHeader = Join-Path $src 'native_files_state.h'
    Search = Join-Path $src 'native_files_search_window.cpp'
    SearchHeader = Join-Path $src 'native_files_search_window.h'
    Preview = Join-Path $src 'native_file_preview.cpp'
    PreviewHeader = Join-Path $src 'native_file_preview.h'
    ShellView = Join-Path $src 'native_shell_view_host.cpp'
    ShellViewHeader = Join-Path $src 'native_shell_view_host.h'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Files V5 contract file missing [$($entry.Key)]: $($entry.Value)"
    }
}

$content = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}
$content.State = $content.StateHeader + "`n" + $content.State
$content.Search = $content.SearchHeader + "`n" + $content.Search
$content.Preview = $content.PreviewHeader + "`n" + $content.Preview
$content.ShellView = $content.ShellViewHeader + "`n" + $content.ShellView

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

Require 'Files V5 compiled graph' $content.Project @(
    'src\native_files_window_v5.cpp',
    'src\native_files_navigation_v5.cpp',
    'src\native_files_support_v5.cpp',
    'src\native_files_operations.cpp',
    'src\native_files_style.cpp',
    'src\native_files_state.cpp',
    'src\native_files_search_window.cpp',
    'src\native_file_preview.cpp',
    'src\native_shell_view_host.cpp',
    'windowscodecs.lib'
)
Forbid 'Files V5 compiled graph' $content.Project @(
    '<ClCompile Include="src\native_files_window.cpp"',
    '<ClCompile Include="src\native_files_navigation.cpp"',
    '<ClCompile Include="src\native_files_support.cpp"'
)

Require 'First-party launcher' $content.Launcher @(
    '#include "native_files_window.h"',
    'else if (id == L"files")',
    'CloudOSNativeFilesWindow::Open(instance);',
    'CloudOSNativeFilesWindow::Open(instance, root);',
    'CloudOSNativeFilesWindow::Open(instance, system_volume);'
)
Forbid 'First-party launcher' $content.Launcher @(
    'L"explorer.exe"',
    'SetParent('
)

Require 'Files V5 window model' ($content.Header + "`n" + $content.Window) @(
    'struct TabState final',
    'std::vector<std::wstring> back;',
    'std::vector<std::wstring> forward;',
    'NativeFilesPersistedState persisted_state_',
    'NativeFilePreviewPane preview_',
    'WC_TABCONTROLW',
    'kNewTabId',
    'kCloseTabId',
    'kFavoriteId',
    'kSearchEditId',
    'kPreviewId',
    'CloudOS.Native.Files.v5',
    'Tabs  •  Quick Access  •  Windows Shell  •  Drive  •  WSL'
)

Require 'Tabbed navigation' $content.Navigation @(
    'NativeFilesStateStore::Load()',
    'NativeFilesStateStore::Save',
    'NativeFilesStateStore::MaximumTabs',
    'kMaximumHistoryEntries = 64',
    'void CloudOSNativeFilesWindow::NewTab()',
    'void CloudOSNativeFilesWindow::CloseActiveTab()',
    'void CloudOSNativeFilesWindow::SelectTab',
    'void CloudOSNativeFilesWindow::NavigateBack()',
    'void CloudOSNativeFilesWindow::NavigateForward()',
    'suppressed_history_target_',
    'CommitNavigatedPath',
    'ToggleFavorite',
    'TogglePreview',
    'OpenSearch',
    'SelectedPaths() const'
)

Require 'Persistent Files state' $content.State @(
    "'C', 'L', 'D', 'F', 'I', 'L', 'E', '5'",
    'FOLDERID_LocalAppData',
    'L"FilesV5"',
    'L"state.dat"',
    'L".tmp"',
    'MOVEFILE_REPLACE_EXISTING',
    'MOVEFILE_WRITE_THROUGH',
    'FlushFileBuffers',
    'MaximumTabs = 24',
    'MaximumFavorites = 64',
    'MaximumPathCharacters = 8192'
)

Require 'Bounded native search' $content.Search @(
    'std::thread worker_',
    'std::atomic_bool cancel_requested_',
    'MaximumResults = 500',
    'MaximumDepth = 24',
    'MaximumQueryCharacters = 512',
    'FindFirstFileExW',
    'FILE_ATTRIBUTE_REPARSE_POINT',
    'directory_entry && !reparse',
    'PostMessageW',
    'Pesquisa cancelada',
    'limite de 500 atingido'
)

Require 'First-party preview' $content.Preview @(
    'IWICImagingFactory',
    'IWICBitmapDecoder',
    'IWICBitmapScaler',
    'IWICFormatConverter',
    'kMaximumTextBytes = 64u * 1024u',
    'kMaximumTextCharacters = 12000',
    'kMaximumImageDimension = 1200',
    'WICDecodeMetadataCacheOnDemand',
    'GUID_WICPixelFormat32bppBGRA',
    'SelectPreviewFont'
)
Forbid 'First-party preview' $content.Preview @('ShellExecuteW')

Require 'Windows Shell provider boundary' $content.ShellView @(
    'CLSID_ExplorerBrowser',
    'IExplorerBrowser',
    'IFolderView2',
    'SelectedPaths() const',
    'GetSelection',
    'IShellItemArray',
    'SIGDN_FILESYSPATH',
    'SIGDN_DESKTOPABSOLUTEPARSING',
    'kMaximumSelection = 256'
)

Require 'CloudOS content interactions' $content.Support @(
    'ShowContentContextMenu',
    'if (content_mode_ == ContentMode::Shell) return;',
    'Adicionar ao Quick Access',
    'Remover do Quick Access',
    'Copiar / mover / ZIP / extrair',
    'TCN_SELCHANGE',
    'kPreviewTimerId',
    'PersistV5State()',
    'preview_.Destroy()',
    'shell_view_.Destroy()'
)

Require 'Existing file operations preserved' $content.OperationWindow @(
    'IFileOperationProgressSink',
    'CLSID_FileOperation',
    'CopyItem',
    'MoveItem',
    'PerformOperations',
    'tar.exe -a -c -f',
    'tar.exe -xf'
)
Require 'Existing Files operations preserved' $content.Operations @(
    'CreateNewFolder',
    'BeginRename',
    'CommitRename',
    'DeleteSelection',
    'NativeCloudOSDrive::Trash'
)

Write-Host 'PASS: Files & Storage V5 contracts passed - first-party launcher, tabbed state, Quick Access, bounded search, WIC/text preview, Shell selection boundary and native file operations are protected.'
