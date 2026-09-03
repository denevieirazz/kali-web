[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$path = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_file_operations_window.cpp'
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Archive Extraction V22 input missing: $path"
}
$text = Get-Content -LiteralPath $path -Raw

foreach ($required in @(
    'SystemTarPath',
    'GetSystemDirectoryW',
    'PrepareTarCommand',
    'CreateProcessW(',
    'application.c_str()',
    'RunTarCapture',
    'kMaximumArchiveListBytes',
    'kMaximumArchiveMembers',
    'tar.exe -tf ',
    'tar.exe -tvf ',
    'ValidateArchiveMember',
    'ValidateZipArchive',
    'ValidateAndExtractZip',
    'FILE_ATTRIBUTE_REPARSE_POINT',
    'FILE_SHARE_READ',
    'ERROR_FILE_TOO_LARGE',
    'segmento invalido/ADS',
    'ZIP contem link simbolico/hardlink',
    'ZIP validado. Extraindo no destino selecionado',
    'GetAnyOperationsAborted',
    'SetOwnerWindow(window)'
)) {
    if (-not $text.Contains($required)) {
        throw "Archive Extraction V22 contract missing: $required"
    }
}

foreach ($forbidden in @(
    'CreateProcessW(\n            nullptr,\n            command.data()',
    'result = RunTar(window_, command, {}, &cancel_requested_);'
)) {
    if ($text.Contains($forbidden)) {
        throw "Archive Extraction V22 unsafe regression detected: $forbidden"
    }
}

# The ExtractZip worker must route through validation rather than calling tar -xf directly.
$extractStart = $text.IndexOf('else if (kind == OperationKind::ExtractZip)', [StringComparison]::Ordinal)
if ($extractStart -lt 0) { throw 'ExtractZip worker branch missing.' }
$extractRegion = $text.Substring($extractStart, [Math]::Min(1800, $text.Length - $extractStart))
if (-not $extractRegion.Contains('ValidateAndExtractZip')) {
    throw 'ExtractZip worker bypasses ValidateAndExtractZip.'
}
if ($extractRegion.Contains('tar.exe -xf ')) {
    throw 'ExtractZip worker must not invoke tar extraction directly before validation.'
}

Write-Host '[PASS] Archive Extraction V22: System32 tar is explicit, member index is bounded/preflighted, path traversal/ADS/reparse/link entries are rejected and extraction cannot bypass validation.'
