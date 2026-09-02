# CloudOS Flutter V23 long-session soak contract.
# This is intentionally static/fast: PR CI must not run the five-hour soak,
# but it must guarantee that the local operator harness remains safe and useful.

$ErrorActionPreference = 'Stop'
$root = (Get-Item "$PSScriptRoot\..\..").FullName
$soakPath = Join-Path $root 'scripts\flutter\run-cloudos-flutter-soak-v23.ps1'

if (-not (Test-Path -LiteralPath $soakPath)) {
    throw "Missing CloudOS Flutter soak harness: $soakPath"
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $soakPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if (@($parseErrors).Count -gt 0) {
    $message = @($parseErrors | ForEach-Object { $_.Message }) -join '; '
    throw "CloudOS Flutter soak harness has PowerShell parse errors: $message"
}

$source = Get-Content -LiteralPath $soakPath -Raw

$required = @(
    '[int]$DurationMinutes = 300',
    '[int]$SampleIntervalSeconds = 60',
    '[switch]$AttachExisting',
    '[switch]$StopLaunchedProcessOnExit',
    'cloudos_flutter_shell.exe',
    'CloudOS.SystemBroker',
    'desktop_session.json',
    'ConvertFrom-Json -ErrorAction Stop',
    'shellWorkingSetMb',
    'shellPrivateMb',
    'shellHandles',
    'shellThreads',
    'brokerRestarts',
    'sessionState',
    'samples.csv',
    'summary.json',
    'live-status.json',
    'events.log',
    'MaxConsecutiveGrowthBreaches',
    'MaxConsecutiveInvalidSessionSamples',
    'MaxConsecutiveBrokerMissingSamples',
    'Write-JsonAtomic',
    "if (`$verdict -eq 'pass') { exit 0 }"
)
foreach ($item in $required) {
    if (-not $source.Contains($item)) {
        throw "CloudOS Flutter soak harness lost required contract: $item"
    }
}

# The default 5h operator run must not silently kill a session that the user is
# still inspecting. Process cleanup is opt-in and only applies to a process the
# harness itself launched.
if ($source -notmatch '\$launchedByHarness\s+-and\s+\$StopLaunchedProcessOnExit') {
    throw 'Soak harness must stop CloudOS only when it launched the process and cleanup was explicitly requested.'
}
if ($source -match '(?m)^\s*Stop-Process\b' -and
    $source -notmatch '\$StopLaunchedProcessOnExit') {
    throw 'Soak harness contains an unconditional process termination path.'
}

# Evidence may record structural session health only. Never add session content,
# paths from restored windows, or the raw JSON to the CSV/live evidence.
foreach ($forbidden in @(
    'sessionRaw',
    'sessionContent',
    'initialWorkingDirectory',
    'initialFilePath',
    'initialPath = $decoded'
)) {
    if ($source.Contains($forbidden)) {
        throw "Soak harness must not emit user/session content into evidence: $forbidden"
    }
}

# CI validates the harness contract only. Five hours belongs to local/manual
# qualification; no workflow should invoke the run script with its defaults.
$workflow = Join-Path $root '.github\workflows\cloudos-flutter-ui.yml'
if (Test-Path -LiteralPath $workflow) {
    $workflowSource = Get-Content -LiteralPath $workflow -Raw
    if ($workflowSource -match 'run-cloudos-flutter-soak-v23\.ps1(?![^\r\n]*-DurationMinutes\s+[1-9])') {
        throw 'PR CI must not start the default five-hour Flutter soak.'
    }
}

Write-Host '[PASS] CloudOS Flutter V23 five-hour soak harness contract is valid.'
