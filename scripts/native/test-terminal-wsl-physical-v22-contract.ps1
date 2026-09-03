[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $root 'scripts\native\run-terminal-wsl-physical-v22.ps1'
$runtimePath = Join-Path $root 'desktop\CloudOS.NativeRuntime\src\cloudos_native_terminal.cpp'
$bridgePath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_flutter_bridge_v20.cpp'
$conptyPath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_conpty_manager.cpp'

foreach ($path in @($scriptPath, $runtimePath, $bridgePath, $conptyPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Terminal/WSL Physical V22 contract input missing: $path"
    }
}

$script = Get-Content -LiteralPath $scriptPath -Raw
$runtime = Get-Content -LiteralPath $runtimePath -Raw
$bridge = Get-Content -LiteralPath $bridgePath -Raw
$conpty = Get-Content -LiteralPath $conptyPath -Raw

foreach ($required in @(
    'CloudOS.NativeRuntime.dll',
    'cloudos_native_terminal_create',
    'cloudos_native_terminal_write',
    'cloudos_native_terminal_read',
    'cloudos_native_terminal_resize',
    'cloudos_native_terminal_get_exit_code',
    'cloudos_native_terminal_terminate',
    'cloudos_native_terminal_release',
    'WriteControlC',
    "'__CLOUDOS_TERM_READY__'",
    "'__SIZE_B__:'",
    "'__CTRL_C__:130'",
    'stty size',
    '--terminate',
    'terminal_process_cleanup',
    'wsl_terminate_observed',
    'release_complete',
    'AllowTerminateDistribution',
    'RequireKali'
)) {
    if (-not $script.Contains($required)) {
        throw "Physical Terminal/WSL V22 qualification missing: $required"
    }
}

foreach ($required in @(
    'CREATE_NEW_PROCESS_GROUP',
    'CREATE_SUSPENDED',
    'JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE',
    'AssignProcessToJobObject',
    'ResumeThread',
    'ResizePseudoConsole',
    'TerminateJobObject'
)) {
    if (-not $runtime.Contains($required)) {
        throw "Native terminal ABI lifecycle guard missing: $required"
    }
}

foreach ($required in @(
    'terminal.createSession',
    'terminal.write',
    'terminal.resize',
    'terminal.signal',
    'terminal.close',
    'CloudOSConPTYManager::Instance()'
)) {
    if (-not $bridge.Contains($required)) {
        throw "Flutter typed terminal bridge missing: $required"
    }
}

foreach ($required in @(
    'CreatePseudoConsole',
    'ResizePseudoConsole',
    'WriteSession(session_id, "\\x03")',
    'CancelSynchronousIo',
    'reader_thread.join()',
    'ShutdownAll()'
)) {
    if (-not $conpty.Contains($required)) {
        throw "Flutter ConPTY lifecycle contract missing: $required"
    }
}

# The physical qualification script is deliberately a fixed test program, not
# a hidden arbitrary-command bridge.
foreach ($forbidden in @(
    '[string]$Command',
    '[string]$CommandLine',
    'Invoke-Expression',
    'iex ',
    'cmd.exe /c',
    'powershell.exe -Command',
    'bash -c $',
    'sh -c $'
)) {
    if ($script.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Physical Terminal/WSL V22 introduced arbitrary command execution surface: $forbidden"
    }
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$errors)
if ($errors.Count -ne 0) {
    throw "Physical Terminal/WSL V22 script has PowerShell parse errors: $($errors.Message -join '; ')"
}

Write-Host '[PASS] Terminal/WSL Physical V22 contract: fixed ConPTY ABI qualification covers streaming, resize, Ctrl+C, bounded exit, distro termination and process cleanup without arbitrary command passthrough.'
