$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$src = Join-Path $root 'desktop\CloudOS.NativeShell\src'
$watchdog = Get-Content -LiteralPath (Join-Path $src 'native_watchdog.cpp') -Raw
$actions = Get-Content -LiteralPath (Join-Path $src 'native_shell_actions.cpp') -Raw
$project = Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj') -Raw

function Require([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) {
            throw "$Name contract missing: $token"
        }
    }
}

Require 'Watchdog intentional-exit policy' $watchdog @(
    'ShouldRestartAfterExit',
    'kNtStatusFailureMask = 0x80000000u',
    'kStatusControlCExit = 0xC000013Au',
    'exit_code == 0',
    'exit_code == kStatusControlCExit',
    '(exit_code & kNtStatusFailureMask) != 0',
    'if (!ShouldRestartAfterExit(exit_code))'
)

Require 'Explicit shell exit remains graceful' $actions @(
    'case ShellActionKind::ExitCloudOS:',
    'PostQuitMessage(0);',
    'case ShellActionKind::RestartCloudOS:',
    'return RestartCloudOS(owner);'
)

Require 'Files V5 selected-source bridge is linked' $project @(
    'src\native_file_operations_window.cpp',
    'src\native_file_operations_files_v5.cpp'
)

Write-Host 'PASS: lifecycle contract protects intentional CloudOS exit from watchdog respawn and keeps the Files V5 OpenWithSources bridge in the compiled graph.'
