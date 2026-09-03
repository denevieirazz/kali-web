[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$path = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_quick_settings_window.cpp'
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Quick Settings System V22 input missing: $path"
}
$text = Get-Content -LiteralPath $path -Raw

foreach ($required in @(
    '#include "native_system_control_backend.h"',
    'NativeSystemControlBackend::QueryAudio()',
    'NativeSystemControlBackend::SetMasterVolume',
    'NativeSystemControlBackend::SetMasterMute',
    'ACLineStatus == 0 || power.ACLineStatus == 1',
    'BatteryFlag != 255',
    'BatteryLifePercent != 255',
    'estado desconhecido',
    'Configuracao do Windows indisponivel',
    'WM_DPICHANGED',
    'GetDpiForWindow'
)) {
    if (-not $text.Contains($required)) {
        throw "Quick Settings System V22 contract missing: $required"
    }
}

foreach ($forbidden in @(
    'DefaultEndpointVolume()',
    'power.ACLineStatus == 1 ? L"conectado" : L"bateria"'
)) {
    if ($text.Contains($forbidden)) {
        throw "Quick Settings System V22 regressed to duplicated or dishonest state handling: $forbidden"
    }
}

Write-Host '[PASS] Quick Settings System V22: audio uses the shared backend, unknown battery/AC telemetry stays unknown, settings launch failures are surfaced and DPI transitions are handled.'
