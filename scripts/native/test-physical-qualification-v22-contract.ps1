[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runnerPath = Join-Path $root 'scripts\native\run-cloudos-physical-qualification-v22.ps1'
if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    throw "Physical qualification runner missing: $runnerPath"
}
$runner = Get-Content -LiteralPath $runnerPath -Raw

foreach ($required in @(
    'test-native-contract-suite.ps1',
    'build-cloudos-native.cmd',
    'verify-native-build-manifest.ps1',
    'run-native-supervisor-smoke-v22.ps1',
    'run-native-lifecycle-smoke-v10.ps1',
    'package-cloudos-native.ps1',
    'run-native-install-v22-smoke.ps1',
    'run-wsl-runtime-smoke-v22.ps1',
    'run-terminal-wsl-physical-v22.ps1',
    'run-native-soak-v9.ps1',
    'RunDestructiveWslTerminate',
    'RequireKali',
    'pass_automated_scope',
    'manual_required',
    'physical_sleep_resume',
    'physical_lock_unlock',
    'rdp_connect_disconnect',
    'monitor_hotplug_dpi',
    'explorer_safe_mode_login',
    'production_authenticode',
    '72h_soak'
)) {
    if (-not $runner.Contains($required)) {
        throw "Physical Qualification V22 runner missing required gate/evidence: $required"
    }
}

if ($runner -match "verdict\s*=\s*'pass'" -or
    $runner -match 'manual_required\s*=\s*@\(\s*\)' -or
    $runner -match 'production_authenticode.+pass') {
    throw 'Physical qualification must not convert manual hardware/signing gates into an unconditional PASS.'
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $runnerPath,
    [ref]$tokens,
    [ref]$errors)
if ($errors.Count -ne 0) {
    throw "Physical Qualification V22 runner has PowerShell parse errors: $($errors.Message -join '; ')"
}

Write-Host '[PASS] Physical Qualification V22 contract: one-command runner executes every automatable release gate, produces evidence, keeps destructive WSL termination explicit and preserves hardware/session/signing/72h gates as manual-required rather than fake PASS.'
