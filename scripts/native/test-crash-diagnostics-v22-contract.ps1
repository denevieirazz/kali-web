[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$statusPath = Join-Path $root 'scripts\native\get-cloudos-recovery-status-v22.ps1'
$werPath = Join-Path $root 'scripts\native\configure-cloudos-wer-v22.ps1'
$packagePath = Join-Path $root 'scripts\native\package-cloudos-native.ps1'
$suitePath = Join-Path $root 'scripts\native\test-native-contract-suite.ps1'

foreach ($path in @($statusPath, $werPath, $packagePath, $suitePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Crash Diagnostics V22 contract input missing: $path"
    }
}

$status = Get-Content -LiteralPath $statusPath -Raw
$wer = Get-Content -LiteralPath $werPath -Raw
$package = Get-Content -LiteralPath $packagePath -Raw
$suite = Get-Content -LiteralPath $suitePath -Raw

foreach ($required in @(
    'supervisor-state-v22.json',
    "component = 'CloudOS.RecoveryStatus'",
    'current_session_runtime',
    'wer_local_dumps',
    'No command lines, window titles, URLs, file contents, credentials or dump contents are read or uploaded.'
)) {
    if (-not $status.Contains($required)) {
        throw "Recovery status V22 contract missing: $required"
    }
}

foreach ($required in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps',
    '%LOCALAPPDATA%\CloudOS\CrashDumps',
    "'CloudOS.exe'",
    "'CloudOS.Supervisor.exe'",
    "'CloudOS.SystemBroker.exe'",
    "'cloudos_flutter_shell.exe'",
    "[ValidateSet('Mini', 'Full')]",
    '[ValidateRange(1, 20)]',
    'requires an elevated PowerShell session',
    'Remove only the CloudOS per-application override',
    'never uploaded by this tool'
)) {
    if (-not $wer.Contains($required)) {
        throw "WER V22 contract missing: $required"
    }
}

function Assert-NoAutomaticWerEnablement {
    param([Parameter(Mandatory = $true)][string]$Path)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$errors)
    if ($errors.Count -ne 0) {
        throw "Cannot safely inspect WER invocation policy because $Path has parse errors: $($errors.Message -join '; ')"
    }

    $commands = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst]
    }, $true))

    foreach ($command in $commands) {
        $text = $command.Extent.Text
        if ($text -match '(?i)configure-cloudos-wer-v22\.ps1' -and
            $text -match '(?i)(?:^|\s)-Enable(?:\s|$)') {
            throw "WER LocalDumps must never be enabled automatically by executable PowerShell code: $text"
        }
    }
}

# Documentation may show the explicit opt-in command. Only executable AST nodes
# are forbidden from enabling WER automatically.
Assert-NoAutomaticWerEnablement -Path $packagePath
Assert-NoAutomaticWerEnablement -Path $suitePath

if (-not $package.Contains("'configure-cloudos-wer-v22.ps1'") -or
    -not $package.Contains("'get-cloudos-recovery-status-v22.ps1'")) {
    throw 'Portable package must ship V22 recovery diagnostics tooling.'
}

if (-not $suite.Contains('test-crash-diagnostics-v22-contract.ps1')) {
    throw 'Central native suite must protect Crash Diagnostics V22.'
}

Write-Host '[PASS] Crash Diagnostics V22 contract: local recovery status + explicit per-app WER LocalDumps tooling; no automatic dump enablement or upload.'
