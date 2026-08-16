$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Read-RepoText {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "SAFETY_FILE_MISSING:$RelativePath" }
    return Get-Content -LiteralPath $path -Raw
}

function Assert-Contains {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Code
    )
    if ($Text -notmatch $Pattern) { throw $Code }
}

$common = Read-RepoText 'scripts/launch/cloudos-launcher-common.ps1'
$start = Read-RepoText 'scripts/launch/start-cloudos.ps1'
$config = Read-RepoText 'backend/src/config/index.js'
$entry = Read-RepoText 'Validar CloudOS.cmd'
$runner = Read-RepoText 'scripts/validate/run-stabilization-batch1.ps1'

$runnerPath = Join-Path $root 'scripts/validate/run-stabilization-batch1.ps1'
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($runnerPath,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw "PHYSICAL_RUNNER_PARSE_FAILED:$($parseErrors[0].Message)" }

Assert-Contains $entry 'run-stabilization-batch1\.ps1' 'VALIDATION_ENTRYPOINT_TARGET_MISSING'
Assert-Contains $runner 'stabilization-batch-1' 'CANONICAL_RESULTS_AREA_MISSING'
Assert-Contains $runner 'CLOUDOS_DATA_DIR' 'ISOLATED_DATA_ENV_MISSING'
Assert-Contains $runner 'CLOUDOS_TEST_ROOT' 'ISOLATED_TEST_ROOT_MISSING'
Assert-Contains $runner 'DATABASE_PATH' 'ISOLATED_DATABASE_ENV_MISSING'

Assert-Contains $common 'dataDirectory=\(Join-Path \$sessionDir ''data''\)' 'SESSION_DATA_DIRECTORY_MISSING'
Assert-Contains $start '\$env:CLOUDOS_DATA_DIR\s*=\s*\$session\.dataDirectory' 'LAUNCHER_DATA_ISOLATION_MISSING'
Assert-Contains $config 'process\.env\.CLOUDOS_DATA_DIR' 'BACKEND_DATA_OVERRIDE_MISSING'
Assert-Contains $config "databasePath:\s*path\.resolve\(process\.env\.DATABASE_PATH\s*\|\|\s*path\.join\(dataDir,\s*'cloudos\.json'\)\)" 'DATABASE_PATH_NOT_ROOTED_IN_DATA_DIR'

foreach ($marker in @(
    'launcher.log',
    'backend.stdout.log',
    'backend.stderr.log',
    'frontend.stdout.log',
    'frontend.stderr.log',
    'host.log',
    'bootstrap.log',
    'result.json'
)) {
    Assert-Contains ($common + $start) ([regex]::Escape($marker)) "PERSISTENT_LOG_CONTRACT_MISSING:$marker"
}
Assert-Contains $common 'processes-\$When\.json' 'PERSISTENT_PROCESS_SNAPSHOT_CONTRACT_MISSING'

Assert-Contains $common 'StartTime' 'PROCESS_IDENTITY_START_TIME_GATE_MISSING'
Assert-Contains $common 'Stop-Process\s+-Id' 'RECORDED_PID_TEARDOWN_MISSING'
if ($common -match '(?i)Stop-Process\s+-Name\s+(node|dotnet|pwsh|powershell)') {
    throw 'BROAD_PROCESS_KILL_FORBIDDEN'
}

Assert-Contains $start '\$env:CLOUDOS_NATIVE_HOST\s*=\s*if\s*\(\$Mode\s+-in\s+@\(''Full'',''BrowserValidation''\)\)' 'FULL_NATIVE_HOST_CAPABILITY_MISSING'
Assert-Contains $start '\$Mode\s+-in\s+@\(''Full'',''BrowserValidation''\)' 'FULL_HOST_MODE_MISSING'
Assert-Contains $start 'run-native-host\.ps1' 'FULL_NATIVE_HOST_BOOTSTRAP_MISSING'
Assert-Contains $start "CLOUDOS_NATIVE_HOST='0'" 'WEBONLY_NATIVE_HOST_DISABLE_MISSING'

$requiredRegressionFiles = @(
    'frontend/test/terminalVisualLifecycle.test.js',
    'frontend/test/terminalSessionVisualContract.test.js',
    'frontend/test/visibleTerminalComponentContract.test.js',
    'frontend/test/browserCapabilityUx.test.js',
    'frontend/test/browserLauncherState.test.js',
    'frontend/test/filesRealTransactionalContract.test.js',
    'frontend/test/filesUnifiedProviders.test.js',
    'frontend/test/filesVisualUx.test.js',
    'frontend/test/onboardingResponsiveContract.test.js',
    'frontend/test/onboardingStabilizationContract.test.js',
    'backend/test/files-real-transactional.test.js',
    'backend/test/onboarding-recovery-ux.test.js',
    'scripts/test-native-browser-host-smoke.ps1'
)
foreach ($relative in $requiredRegressionFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative))) {
        throw "REGRESSION_FILE_MISSING:$relative"
    }
}

$validationSources = @(
    $entry,
    $runner,
    (Read-RepoText 'scripts/validate/test-launcher-contract.ps1'),
    (Get-Content -LiteralPath $MyInvocation.MyCommand.Path -Raw)
) -join "`n"

$forbiddenGit = '(?im)\bgit(?:\.exe)?\s+(?:reset\b|rebase\b|merge\b|clean\s+[^\r\n]*-f|checkout\s+[^\r\n]*-f|push\s+[^\r\n]*(?:--force(?:-with-lease)?|-f\b))'
if ($validationSources -match $forbiddenGit) { throw 'DESTRUCTIVE_GIT_COMMAND_FORBIDDEN' }

$forbiddenWsl = '(?im)\bwsl(?:\.exe)?\s+(?:--install\b|--unregister\b|--shutdown\b|--set-default\b|--set-default-version\b|--set-version\b|--update\b|--import\b|--export\b)'
if ($validationSources -match $forbiddenWsl) { throw 'WSL_MUTATION_COMMAND_FORBIDDEN' }

if ($runner -match '(?i)(Remove-Item|Clear-Content|Set-Content).*(?:data\\cloudos|backend\\data|cloudos\.json)') {
    throw 'REAL_DATABASE_MUTATION_PATTERN_FORBIDDEN'
}

Write-Host 'STABILIZATION_SAFETY_BOUNDARY_OK'
