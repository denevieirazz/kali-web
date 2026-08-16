[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $IsWindows) {
    throw 'WINDOWS_PHYSICAL_VALIDATION_REQUIRED'
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'POWERSHELL_7_REQUIRED'
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$expectedBranch = 'stabilization/cloudos-foundation-batch-1'
$expectedBase = '2d3380ba562d23e05947f81cc9581e8fe9bcfdbc'
$commandResults = [System.Collections.Generic.List[object]]::new()
$launcherSessions = [System.Collections.Generic.List[object]]::new()
$runDirectory = $null
$previousEnvironment = $null

function Write-JsonFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $directory = Split-Path -Parent $Path
    if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Resolve-RequiredCommand {
    param([Parameter(Mandatory)][string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { throw "PRECONDITION_MISSING:$Name" }
    return $command.Source
}

Push-Location $root
try {
    $branch = (& git branch --show-current 2>$null).Trim()
    $head = (& git rev-parse HEAD 2>$null).Trim()
    $mergeBase = (& git merge-base HEAD $expectedBase 2>$null).Trim()
    if ($branch -ne $expectedBranch) { throw "WRONG_BRANCH:$branch" }
    if ($mergeBase -ne $expectedBase) { throw "WRONG_BASE:$mergeBase" }
    & git merge-base --is-ancestor $expectedBase HEAD
    if ($LASTEXITCODE -ne 0) { throw 'BASE_NOT_ANCESTOR' }

    $executionId = "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $runDirectory = Join-Path $root "test-results\stabilization-batch-1\$head\$executionId"
    $commandsDirectory = Join-Path $runDirectory 'commands'
    $safetyDirectory = Join-Path $runDirectory 'safety'
    $evidenceDirectory = Join-Path $runDirectory 'evidence'
    $isolatedDataDirectory = Join-Path $runDirectory 'isolated-data'
    New-Item -ItemType Directory -Force -Path $commandsDirectory,$safetyDirectory,$evidenceDirectory,$isolatedDataDirectory | Out-Null

    $previousEnvironment = [ordered]@{
        NODE_ENV = $env:NODE_ENV
        CLOUDOS_DATA_DIR = $env:CLOUDOS_DATA_DIR
        CLOUDOS_TEST_ROOT = $env:CLOUDOS_TEST_ROOT
        DATABASE_PATH = $env:DATABASE_PATH
        CLOUDOS_NATIVE_HOST = $env:CLOUDOS_NATIVE_HOST
    }

    $env:NODE_ENV = 'test'
    $env:CLOUDOS_DATA_DIR = $isolatedDataDirectory
    $env:CLOUDOS_TEST_ROOT = $isolatedDataDirectory
    $env:DATABASE_PATH = Join-Path $isolatedDataDirectory 'cloudos.json'
    $env:CLOUDOS_NATIVE_HOST = '0'

    Write-JsonFile (Join-Path $runDirectory 'git.json') ([ordered]@{
        branch = $branch
        head = $head
        expectedBase = $expectedBase
        mergeBase = $mergeBase
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
    })
    Write-JsonFile (Join-Path $runDirectory 'environment.json') ([ordered]@{
        os = [Environment]::OSVersion.VersionString
        machine = $env:COMPUTERNAME
        powershell = $PSVersionTable.PSVersion.ToString()
        node = (& node --version 2>$null | Select-Object -First 1)
        isolatedDataDirectory = $isolatedDataDirectory
        databasePath = $env:DATABASE_PATH
        realDatabaseUsed = $false
    })
    Write-JsonFile (Join-Path $runDirectory 'manifest.json') ([ordered]@{
        schemaVersion = 1
        batch = 'stabilization-batch-1'
        branch = $branch
        head = $head
        base = $expectedBase
        executionId = $executionId
        startedAt = (Get-Date).ToUniversalTime().ToString('o')
        status = 'running'
        physicalEntryPoint = 'Validar CloudOS.cmd'
        resultDirectory = $runDirectory
    })

    function Invoke-CapturedCommand {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$FilePath,
            [string[]]$Arguments = @()
        )
        $stdoutPath = Join-Path $commandsDirectory "$Name.stdout.log"
        $stderrPath = Join-Path $commandsDirectory "$Name.stderr.log"
        $startedAt = (Get-Date).ToUniversalTime().ToString('o')
        Write-Host "[CloudOS Validate] $Name"

        $info = [System.Diagnostics.ProcessStartInfo]::new()
        $info.FileName = $FilePath
        $info.WorkingDirectory = $root
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        foreach ($argument in $Arguments) { [void]$info.ArgumentList.Add([string]$argument) }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $info
        try {
            if (-not $process.Start()) { throw "COMMAND_START_FAILED:$Name" }
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $stdout = $stdoutTask.GetAwaiter().GetResult()
            $stderr = $stderrTask.GetAwaiter().GetResult()
            Set-Content -LiteralPath $stdoutPath -Value $stdout -Encoding UTF8
            Set-Content -LiteralPath $stderrPath -Value $stderr -Encoding UTF8
            $record = [ordered]@{
                name = $Name
                file = $FilePath
                arguments = @($Arguments)
                exitCode = $process.ExitCode
                startedAt = $startedAt
                finishedAt = (Get-Date).ToUniversalTime().ToString('o')
                stdout = $stdoutPath
                stderr = $stderrPath
            }
            $commandResults.Add($record)
            Write-JsonFile (Join-Path $runDirectory 'commands.json') @($commandResults)
            if ($process.ExitCode -ne 0) {
                $tail = (($stderr -split "`r?`n") | Select-Object -Last 20) -join ' | '
                throw "COMMAND_FAILED:$Name:$($process.ExitCode):$tail"
            }
        } finally {
            $process.Dispose()
        }
    }

    function Save-ProcessSnapshot {
        param([Parameter(Mandatory)][string]$When)
        $items = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CreationDate
        Write-JsonFile (Join-Path $safetyDirectory "processes-$When.json") @($items)
    }

    function Save-WslSnapshot {
        param([Parameter(Mandatory)][string]$When)
        $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
        if (-not $wsl) {
            Set-Content -LiteralPath (Join-Path $safetyDirectory "wsl-$When.txt") -Value 'WSL_NOT_AVAILABLE' -Encoding UTF8
            return
        }
        $lines = @(
            '### wsl.exe --list --verbose'
            (& wsl.exe --list --verbose 2>&1)
            ''
            '### wsl.exe --status'
            (& wsl.exe --status 2>&1)
        )
        Set-Content -LiteralPath (Join-Path $safetyDirectory "wsl-$When.txt") -Value $lines -Encoding UTF8
    }

    function Assert-NoRecordedProcessesRemain {
        param([Parameter(Mandatory)]$Session)
        foreach ($record in @($Session.processes)) {
            $process = Get-Process -Id ([int]$record.pid) -ErrorAction SilentlyContinue
            if (-not $process) { continue }
            try {
                if ($process.StartTime.ToUniversalTime().ToString('o') -eq [string]$record.startedAt) {
                    throw "ORPHAN_SESSION_PROCESS:$($record.component):$($record.pid)"
                }
            } catch [System.InvalidOperationException] {
                continue
            }
        }
    }

    function Invoke-LauncherSmoke {
        param(
            [Parameter(Mandatory)][ValidateSet('WebOnly','Full')][string]$Mode,
            [switch]$ManualCheckpoint
        )
        $currentState = Join-Path $root '.cloudos-runtime\current-session.json'
        if (Test-Path -LiteralPath $currentState) {
            try {
                $current = Get-Content -LiteralPath $currentState -Raw | ConvertFrom-Json
                if ($current.status -in @('starting','running')) {
                    $liveOwned = $false
                    foreach ($record in @($current.processes)) {
                        $process = Get-Process -Id ([int]$record.pid) -ErrorAction SilentlyContinue
                        if (-not $process) { continue }
                        try {
                            if ($process.StartTime.ToUniversalTime().ToString('o') -eq [string]$record.startedAt) {
                                $liveOwned = $true
                                break
                            }
                        } catch { }
                    }
                    if ($liveOwned) { throw "ACTIVE_CLOUDOS_SESSION_DETECTED:$($current.id)" }
                }
            } catch {
                if ($_.Exception.Message -like 'ACTIVE_CLOUDOS_SESSION_DETECTED:*') { throw }
            }
        }

        $pwsh = Resolve-RequiredCommand 'pwsh'
        $session = $null
        $started = $false
        try {
            Invoke-CapturedCommand "launcher-$($Mode.ToLowerInvariant())-start" $pwsh @(
                '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',
                (Join-Path $root 'scripts\launch\start-cloudos.ps1'),'-Mode',$Mode
            )
            $started = $true
            Start-Sleep -Seconds 2
            if (-not (Test-Path -LiteralPath $currentState)) { throw "SESSION_STATE_MISSING:$Mode" }
            $session = Get-Content -LiteralPath $currentState -Raw | ConvertFrom-Json
            if ($session.mode -ne $Mode -or $session.status -ne 'running') {
                throw "SESSION_NOT_RUNNING:$Mode:$($session.status)"
            }
            if ($Mode -eq 'WebOnly') {
                $components = @($session.processes | ForEach-Object { $_.component })
                if ($components -notcontains 'backend' -or $components -notcontains 'frontend') {
                    throw 'WEBONLY_EXPECTED_COMPONENTS_MISSING'
                }
            }
            if ($Mode -eq 'Full') {
                $components = @($session.processes | ForEach-Object { $_.component })
                if ($components -notcontains 'host') { throw 'FULL_HOST_PROCESS_MISSING' }
            }

            $launcherSessions.Add([ordered]@{
                mode = $Mode
                id = $session.id
                logDirectory = $session.logDirectory
                dataDirectory = $session.dataDirectory
                processes = @($session.processes)
            })
            Write-JsonFile (Join-Path $evidenceDirectory 'launcher-sessions.json') @($launcherSessions)

            if ($ManualCheckpoint -and -not $NonInteractive) {
                $checkpoint = @(
                    'CHECKPOINT MANUAL EXTERNO - pressionar ENTER nao significa aprovacao automatica.'
                    'Inspecionar no Full: Browser pelo Menu Iniciar; Terminal abrir/fechar sem afetar outras apps; onboarding/recovery; Files.'
                    'A aprovacao fisica/visual pertence ao Gemini Low, usuario e Copilot principal.'
                )
                Set-Content -LiteralPath (Join-Path $evidenceDirectory 'manual-checkpoint.txt') -Value $checkpoint -Encoding UTF8
                Write-Host ''
                Write-Host '=== CHECKPOINT PARA GEMINI LOW / USUARIO ==='
                $checkpoint | ForEach-Object { Write-Host $_ }
                [void](Read-Host 'Quando terminar a inspecao externa, pressione ENTER para executar teardown e checagem de orfaos')
            }
        } finally {
            if ($started) {
                try {
                    Invoke-CapturedCommand "launcher-$($Mode.ToLowerInvariant())-stop" $pwsh @(
                        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',
                        (Join-Path $root 'scripts\launch\stop-cloudos.ps1')
                    )
                } finally {
                    Start-Sleep -Milliseconds 500
                    if ($session) { Assert-NoRecordedProcessesRemain $session }
                }
            }
        }
    }

    Save-ProcessSnapshot 'before'
    Save-WslSnapshot 'before'

    $pwsh = Resolve-RequiredCommand 'pwsh'
    $npm = Resolve-RequiredCommand 'npm.cmd'
    $npx = Resolve-RequiredCommand 'npx.cmd'
    $dotnet = Resolve-RequiredCommand 'dotnet'

    Invoke-CapturedCommand 'safety-boundary' $pwsh @('-NoLogo','-NoProfile','-File',(Join-Path $root 'scripts\validate\test-stabilization-safety-boundary.ps1'))
    Invoke-CapturedCommand 'launcher-contract' $pwsh @('-NoLogo','-NoProfile','-File',(Join-Path $root 'scripts\validate\test-launcher-contract.ps1'))
    if (-not $SkipInstall) {
        Invoke-CapturedCommand 'npm-ci' $npm @('ci')
        Invoke-CapturedCommand 'playwright-install-chromium' $npx @('playwright','install','chromium')
    }
    Invoke-CapturedCommand 'lint' $npm @('run','lint')
    Invoke-CapturedCommand 'build' $npm @('run','build')
    Invoke-CapturedCommand 'backend-tests' $npm @('test')
    Invoke-CapturedCommand 'e2e-tests' $npm @('run','test:e2e')
    Invoke-CapturedCommand 'frontend-tests' $npm @('run','test:frontend')

    Invoke-CapturedCommand 'host-build' $dotnet @('build','desktop/CloudOS.Host/CloudOS.Host.csproj','-c','Release')
    Invoke-CapturedCommand 'host-tests' $dotnet @('run','--project','desktop/CloudOS.Host.Tests/CloudOS.Host.Tests.csproj','-c','Release')
    Invoke-CapturedCommand 'browser-contract-tests' $dotnet @('run','--project','desktop/CloudOS.Browser.Contracts.Tests/CloudOS.Browser.Contracts.Tests.csproj','-c','Release')
    Invoke-CapturedCommand 'bootstrap-build' $dotnet @('build','desktop/CloudOS.Bootstrap/CloudOS.Bootstrap.csproj','-c','Release')
    Invoke-CapturedCommand 'bootstrap-tests' $dotnet @('run','--project','desktop/CloudOS.Bootstrap.Tests/CloudOS.Bootstrap.Tests.csproj','-c','Release')
    Invoke-CapturedCommand 'browser-testhost-build' $dotnet @('build','desktop/CloudOS.Browser.TestHost/CloudOS.Browser.TestHost.csproj','-c','Release')
    Invoke-CapturedCommand 'wsl-core-build' $dotnet @('build','desktop/CloudOS.WslCore/CloudOS.WslCore.csproj','-c','Release')
    Invoke-CapturedCommand 'wsl-core-tests' $dotnet @('run','--project','desktop/CloudOS.WslCore.Tests/CloudOS.WslCore.Tests.csproj','-c','Release')
    Invoke-CapturedCommand 'wsl-core-probe-build-only' $dotnet @('build','desktop/CloudOS.WslCore.Probe/CloudOS.WslCore.Probe.csproj','-c','Release')

    foreach ($contract in @(
        'scripts/test-native-host-freshness.ps1',
        'scripts/test-wsl-core-foundation-contract.ps1',
        'scripts/test-wsl-core-secure-terminal-contract.ps1',
        'scripts/test-visible-terminal-wsl-core-contract.ps1'
    )) {
        $name = [IO.Path]::GetFileNameWithoutExtension($contract)
        Invoke-CapturedCommand $name $pwsh @('-NoLogo','-NoProfile','-File',(Join-Path $root $contract))
    }

    Invoke-CapturedCommand 'playwright-characterization' $npx @(
        'playwright','test','--grep-invert',
        'Navegador CloudOS — WebView2 real|Navegador CloudOS — lifecycle Windows',
        '--reporter=list'
    )
    Invoke-CapturedCommand 'playwright-browser-lifecycle' $npx @(
        'playwright','test','tests/playwright/native-browser-lifecycle.spec.ts',
        '--output', (Join-Path $runDirectory 'playwright-native-browser-lifecycle'),
        '--reporter=list'
    )
    Invoke-CapturedCommand 'playwright-browser' $npx @(
        'playwright','test','tests/playwright/native-browser.spec.ts',
        '--output', (Join-Path $runDirectory 'playwright-native-browser'),
        '--reporter=list'
    )

    Invoke-LauncherSmoke -Mode 'WebOnly'
    Invoke-LauncherSmoke -Mode 'Full' -ManualCheckpoint

    Save-WslSnapshot 'after'
    Save-ProcessSnapshot 'after'

    $beforeWsl = Get-Content -LiteralPath (Join-Path $safetyDirectory 'wsl-before.txt') -Raw
    $afterWsl = Get-Content -LiteralPath (Join-Path $safetyDirectory 'wsl-after.txt') -Raw
    $wslSnapshotStable = $beforeWsl -eq $afterWsl
    Write-JsonFile (Join-Path $runDirectory 'summary.json') ([ordered]@{
        schemaVersion = 1
        status = 'passed'
        branch = $branch
        head = $head
        base = $expectedBase
        commandCount = $commandResults.Count
        launcherModes = @($launcherSessions | ForEach-Object { $_.mode })
        isolatedDatabase = $env:DATABASE_PATH
        realDatabaseUsed = $false
        wslMutationCommandsExecuted = $false
        wslReadOnlySnapshotStable = $wslSnapshotStable
        physicalAndVisualApproval = 'external-pending'
        finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    })
    Write-JsonFile (Join-Path $runDirectory 'manifest.json') ([ordered]@{
        schemaVersion = 1
        batch = 'stabilization-batch-1'
        branch = $branch
        head = $head
        base = $expectedBase
        executionId = $executionId
        status = 'passed'
        physicalEntryPoint = 'Validar CloudOS.cmd'
        resultDirectory = $runDirectory
        finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    })

    Write-Host ''
    Write-Host 'CLOUDOS_STABILIZATION_BATCH_1_VALIDATION_PASSED'
    Write-Host "RESULTS=$runDirectory"
    Write-Host 'VALIDACAO FISICA/VISUAL: permanece externa e nao e declarada por este script.'
} catch {
    if ($runDirectory -and (Test-Path -LiteralPath $runDirectory)) {
        Write-JsonFile (Join-Path $runDirectory 'summary.json') ([ordered]@{
            schemaVersion = 1
            status = 'failed'
            error = $_.Exception.Message
            physicalAndVisualApproval = 'external-pending'
            finishedAt = (Get-Date).ToUniversalTime().ToString('o')
        })
    }
    throw
} finally {
    if ($previousEnvironment) {
        foreach ($name in $previousEnvironment.Keys) {
            $value = $previousEnvironment[$name]
            if ($null -eq $value) {
                Remove-Item "Env:$name" -ErrorAction SilentlyContinue
            } else {
                [Environment]::SetEnvironmentVariable($name,[string]$value,'Process')
            }
        }
    }
    Pop-Location
}
