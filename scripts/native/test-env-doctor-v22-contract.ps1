[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$path = Join-Path $root 'desktop\CloudOS.NativeShell\src\native_env_doctor_window.cpp'
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Env Doctor V22 input missing: $path"
}
$text = Get-Content -LiteralPath $path -Raw

foreach ($required in @(
    'enum class CheckSeverity',
    'CheckSeverity::Ok',
    'CheckSeverity::Warning',
    'CheckSeverity::Info',
    'GetAvailableCoreWebView2BrowserVersionString',
    'cloudos_native_runtime_abi',
    'CreatePseudoConsole',
    'cloudos_native_wsl_is_registered',
    'cloudos_native_wsl_get_configuration',
    'GetAwarenessFromDpiAwarenessContext',
    'DPI_AWARENESS_PER_MONITOR_AWARE',
    'GetDiskFreeSpaceExW',
    'supervisor-state-v22.json',
    'CreateToolhelp32Snapshot',
    'Presenca de processo e evidencia operacional, nao prova de saude.',
    'WM_DPICHANGED'
)) {
    if (-not $text.Contains($required)) {
        throw "Env Doctor V22 contract missing: $required"
    }
}

foreach ($forbidden in @(
    'WSL2 ativo',
    'Kali pronta',
    'processo saudavel',
    'Health PASS' + '"'
)) {
    if ($text.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Env Doctor V22 introduced an unsupported health claim: $forbidden"
    }
}

Write-Host '[PASS] Env Doctor V22: real WebView2/runtime/ConPTY/WSL/DPI/storage/recovery evidence is surfaced with OK/WARNING/INFO semantics and process presence is not misreported as health.'
