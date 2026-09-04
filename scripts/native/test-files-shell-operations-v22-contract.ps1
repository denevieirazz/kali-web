[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$path = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_files_operations.cpp'
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Files Shell Operations V22 input missing: $path"
}
$text = Get-Content -LiteralPath $path -Raw

foreach ($required in @(
    'CLSID_FileOperation',
    'IFileOperation',
    'SetOwnerWindow',
    'SetOperationFlags',
    'SHCreateItemFromParsingName',
    'RenameItem',
    'DeleteItem',
    'PerformOperations',
    'GetAnyOperationsAborted',
    'FOFX_ADDUNDORECORD',
    'FOFX_RECYCLEONDELETE',
    'FOFX_SHOWELEVATIONPROMPT',
    'HRESULT_FROM_WIN32(ERROR_CANCELLED)'
)) {
    if (-not $text.Contains($required)) {
        throw "Files Shell Operations V22 contract missing: $required"
    }
}

foreach ($forbidden in @(
    'SHFileOperationW(',
    'MoveFileW(entry.full_path.c_str(), destination.c_str())',
    'DeleteFileW(entry.full_path.c_str())'
)) {
    if ($text.Contains($forbidden)) {
        throw "Files Shell Operations V22 legacy/destructive regression detected: $forbidden"
    }
}

Write-Host '[PASS] Files Shell Operations V22: fallback rename/delete use IFileOperation with owner, undo/recycle semantics, cancellation detection and elevation-aware Shell behavior.'
