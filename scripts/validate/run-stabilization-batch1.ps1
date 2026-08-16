[CmdletBinding()]
param([switch]$SkipInstall,[switch]$NonInteractive)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if(-not $IsWindows){throw 'WINDOWS_PHYSICAL_VALIDATION_REQUIRED'}
if($PSVersionTable.PSVersion.Major -lt 7){throw 'POWERSHELL_7_REQUIRED'}

$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'cloudos-node-dependencies.ps1')
. (Join-Path $root 'scripts\launch\cloudos-launcher-common.ps1')
. (Join-Path $root 'scripts\launch\cloudos-owned-processes.ps1')

$expectedBranch='stabilization/cloudos-foundation-batch-1'
$expectedBase='2d3380ba562d23e05947f81cc9581e8fe9bcfdbc'
$commandResults=[System.Collections.Generic.List[object]]::new()
$launcherSessions=[System.Collections.Generic.List[object]]::new()
$runDirectory=$null
$previousEnvironment=$null

function Write-JsonFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $dir=Split-Path -Parent $Path
    if($dir){New-Item -ItemType Directory -Force -Path $dir|Out-Null}
    $Value|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $Path -Encoding UTF8
}

function Resolve-RequiredCommand {
    param([Parameter(Mandatory)][string[]]$Names)
    foreach($name in $Names){$cmd=Get-Command $name -ErrorAction SilentlyContinue;if($cmd -and $cmd.Source){return $cmd.Source}}
    throw "PRECONDITION_MISSING:$($Names -join '|')"
}

function Get-IsolatedTestEnvironment {
    param([Parameter(Mandatory)][string]$Scope)
    $dir=Join-Path $isolatedDataDirectory $Scope
    New-Item -ItemType Directory -Force -Path $dir|Out-Null
    return @{NODE_ENV='test';CLOUDOS_DATA_DIR=$dir;CLOUDOS_TEST_ROOT=$dir;DATABASE_PATH=(Join-Path $dir 'cloudos.json');CLOUDOS_NATIVE_HOST='0'}
}

function Invoke-CapturedCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments=@(),
        [hashtable]$Environment=@{},
        [string]$WorkingDirectory=$root
    )
    $stdoutPath=Join-Path $commandsDirectory "$Name.stdout.log"
    $stderrPath=Join-Path $commandsDirectory "$Name.stderr.log"
    Write-Host "[CloudOS Validate] $Name"
    $info=[System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$FilePath
    $info.WorkingDirectory=$WorkingDirectory
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true
    $info.RedirectStandardError=$true
    foreach($arg in $Arguments){[void]$info.ArgumentList.Add([string]$arg)}
    foreach($key in $Environment.Keys){$info.Environment[$key]=[string]$Environment[$key]}
    $process=[System.Diagnostics.Process]::new();$process.StartInfo=$info
    $startedAt=(Get-Date).ToUniversalTime().ToString('o')
    try{
        try{if(-not $process.Start()){throw "COMMAND_START_FAILED:$Name"}}
        catch{
            $message="COMMAND_START_FAILED:${Name}:$($_.Exception.Message)"
            Set-Content -LiteralPath $stderrPath -Value $message -Encoding UTF8
            $commandResults.Add([ordered]@{name=$Name;executable=$FilePath;arguments=$Arguments;workingDirectory=$WorkingDirectory;exitCode=-1;startedAt=$startedAt;finishedAt=(Get-Date).ToUniversalTime().ToString('o');stdout=$stdoutPath;stderr=$stderrPath})
            Write-JsonFile (Join-Path $runDirectory 'commands.json') @($commandResults)
            throw $message
        }
        $outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout=$outTask.GetAwaiter().GetResult();$stderr=$errTask.GetAwaiter().GetResult()
        Set-Content -LiteralPath $stdoutPath -Value $stdout -Encoding UTF8
        Set-Content -LiteralPath $stderrPath -Value $stderr -Encoding UTF8
        $commandResults.Add([ordered]@{name=$Name;executable=$FilePath;arguments=$Arguments;workingDirectory=$WorkingDirectory;exitCode=$process.ExitCode;startedAt=$startedAt;finishedAt=(Get-Date).ToUniversalTime().ToString('o');stdout=$stdoutPath;stderr=$stderrPath})
        Write-JsonFile (Join-Path $runDirectory 'commands.json') @($commandResults)
        if($process.ExitCode -ne 0){
            $tail=(($stderr -split "`r?`n")|Select-Object -Last 30)-join ' | '
            if(-not $tail){$tail=(($stdout -split "`r?`n")|Select-Object -Last 30)-join ' | '}
            throw "COMMAND_FAILED:${Name}:$($process.ExitCode):log=${stderrPath}:error=$tail"
        }
    }finally{$process.Dispose()}
}

function Quote-StartProcessArgument {
    param([Parameter(Mandatory)][string]$Value)
    if($Value -notmatch '[\s"]'){return $Value}
    return '"' + ($Value -replace '([\\]*)"','$1$1\"') + '"'
}

function Invoke-ShortLauncherCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds=120
    )
    $stdoutPath=Join-Path $commandsDirectory "$Name.stdout.log"
    $stderrPath=Join-Path $commandsDirectory "$Name.stderr.log"
    New-Item -ItemType File -Force -Path $stdoutPath,$stderrPath|Out-Null
    $quoted=@($Arguments|ForEach-Object{Quote-StartProcessArgument ([string]$_)})
    $startedAt=(Get-Date).ToUniversalTime().ToString('o')
    Write-Host "[CloudOS Validate] $Name (launcher curto)"
    $process=Start-Process -FilePath $pwsh -ArgumentList $quoted -WorkingDirectory $root -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    try{
        if(-not $process.WaitForExit($TimeoutSeconds*1000)){
            try{Stop-Process -Id $process.Id -Force -ErrorAction Stop}catch{}
            throw "LAUNCHER_SHORT_PROCESS_TIMEOUT:${Name}:pid=$($process.Id):timeout=${TimeoutSeconds}s:log=$stderrPath"
        }
        $exitCode=$process.ExitCode
        $commandResults.Add([ordered]@{name=$Name;executable=$pwsh;arguments=$Arguments;workingDirectory=$root;exitCode=$exitCode;startedAt=$startedAt;finishedAt=(Get-Date).ToUniversalTime().ToString('o');stdout=$stdoutPath;stderr=$stderrPath;launcherShortProcess=$true})
        Write-JsonFile (Join-Path $runDirectory 'commands.json') @($commandResults)
        if($exitCode -ne 0){
            $tail=((Get-Content -LiteralPath $stderrPath -Tail 30 -ErrorAction SilentlyContinue)+(Get-Content -LiteralPath $stdoutPath -Tail 30 -ErrorAction SilentlyContinue))-join ' | '
            throw "LAUNCHER_EXITED_BEFORE_READINESS:${Name}:exit=${exitCode}:log=${stderrPath}:error=$tail"
        }
    }finally{$process.Dispose()}
    return [ordered]@{stdout=$stdoutPath;stderr=$stderrPath}
}

function Save-ProcessSnapshot {
    param([Parameter(Mandatory)][string]$When)
    $items=Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CreationDate,CommandLine
    Write-JsonFile (Join-Path $safetyDirectory "processes-$When.json") @($items)
}

function Save-WslSnapshot {
    param([Parameter(Mandatory)][string]$When)
    $wsl=Get-Command wsl.exe -ErrorAction SilentlyContinue
    if(-not $wsl){Set-Content -LiteralPath (Join-Path $safetyDirectory "wsl-$When.txt") -Value 'WSL_NOT_AVAILABLE' -Encoding UTF8;return}
    @('### wsl.exe --list --verbose',(& wsl.exe --list --verbose 2>&1),'','### wsl.exe --status',(& wsl.exe --status 2>&1))|Set-Content -LiteralPath (Join-Path $safetyDirectory "wsl-$When.txt") -Encoding UTF8
}

function Get-ComponentLogTail {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][string]$Component)
    $names=switch -Regex($Component){'^backend'{@('backend.stderr.log','backend.stdout.log')};'^frontend'{@('frontend.stderr.log','frontend.stdout.log')};'^host-runtime$'{@('host.stderr.log','host.log')};default{@('launcher.log')}}
    foreach($name in $names){$path=Join-Path ([string]$Session.logDirectory) $name;if(Test-Path -LiteralPath $path){$tail=(Get-Content -LiteralPath $path -Tail 30 -ErrorAction SilentlyContinue)-join ' | ';if($tail){return [ordered]@{path=$path;tail=$tail}}}}
    return [ordered]@{path=[string]$Session.logDirectory;tail=''}
}

function Get-SessionRecord {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][string]$Component)
    $record=@($Session.processes|Where-Object{[string]$_.component -eq $Component}|Select-Object -First 1)
    if($record.Count -eq 0){throw "SESSION_COMPONENT_RECORD_MISSING:${Component}:session=$($Session.id)"}
    return $record[0]
}

function Assert-RunnerOwnedProcessAlive {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][string]$Component)
    $record=Get-SessionRecord $Session $Component
    $check=Test-CloudOSProcessOwnership $Session $record
    if(-not $check.running){$log=Get-ComponentLogTail $Session $Component;throw "SESSION_PROCESS_EXITED:${Component}:pid=$($record.pid):log=$($log.path):error=$($log.tail)"}
    if(-not $check.owned){throw "SESSION_PROCESS_OWNERSHIP_LOST:${Component}:pid=$($record.pid):reason=$($check.reason)"}
    return $record
}

function Wait-RunnerHttpReady {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][string]$Component,[Parameter(Mandatory)][string]$Uri,[int]$TimeoutSeconds)
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds);$lastError=''
    while([DateTime]::UtcNow -lt $deadline){
        [void](Assert-RunnerOwnedProcessAlive $Session $Component)
        try{$r=Invoke-WebRequest -Uri $Uri -Method Get -TimeoutSec 2 -SkipHttpErrorCheck;if([int]$r.StatusCode -ge 200 -and [int]$r.StatusCode -lt 400){return}}
        catch{$lastError=$_.Exception.Message}
        Start-Sleep -Milliseconds 200
    }
    throw "RUNNER_COMPONENT_READINESS_TIMEOUT:${Component}:uri=${Uri}:timeout=${TimeoutSeconds}s:error=$(ConvertTo-CloudOSSanitizedCommandLine $lastError)"
}

function Read-RunningSessionForMode {
    param([Parameter(Mandatory)][string]$Mode)
    $state=Join-Path $root '.cloudos-runtime\current-session.json'
    if(-not(Test-Path -LiteralPath $state)){throw "SESSION_STATE_MISSING:$Mode"}
    $session=Get-Content -LiteralPath $state -Raw|ConvertFrom-Json
    if([string]$session.mode -ne $Mode){throw "SESSION_MODE_MISMATCH:expected=${Mode}:actual=$($session.mode)"}
    if([string]$session.status -ne 'running'){throw "SESSION_NOT_RUNNING:${Mode}:$($session.status)"}
    $manifestPath=Join-Path ([string]$session.logDirectory) 'manifest.json'
    if(-not(Test-Path -LiteralPath $manifestPath)){throw "SESSION_MANIFEST_MISSING:${Mode}:$manifestPath"}
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
    if([string]$manifest.id -ne [string]$session.id){throw "SESSION_MANIFEST_ID_MISMATCH:${Mode}:$($session.id):$($manifest.id)"}
    if([string]$manifest.status -ne 'running'){throw "SESSION_MANIFEST_NOT_RUNNING:${Mode}:$($manifest.status)"}
    return $manifest
}

function Wait-RunnerSessionReady {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][ValidateSet('WebOnly','Full')][string]$Mode)
    if(-not $Session.readiness -or [string]$Session.readiness.status -ne 'ready'){throw "SESSION_READINESS_NOT_RECORDED:$Mode"}
    if($Mode -eq 'WebOnly'){
        $backend=Assert-RunnerOwnedProcessAlive $Session 'backend'
        $frontend=Assert-RunnerOwnedProcessAlive $Session 'frontend'
        $backendRuntime=Join-Path ([string]$Session.runtimeDirectory) 'backend-port.json'
        $frontendRuntime=Join-Path ([string]$Session.runtimeDirectory) 'frontend-port.json'
        if(-not(Test-Path -LiteralPath $backendRuntime)){throw "BACKEND_RUNTIME_MISSING:$backendRuntime"}
        if(-not(Test-Path -LiteralPath $frontendRuntime)){throw "FRONTEND_RUNTIME_MISSING:$frontendRuntime"}
        $backendInfo=Get-Content -LiteralPath $backendRuntime -Raw|ConvertFrom-Json
        $frontendInfo=Get-Content -LiteralPath $frontendRuntime -Raw|ConvertFrom-Json
        if([int]$backendInfo.pid -ne [int]$backend.pid){throw 'BACKEND_RUNTIME_PID_MISMATCH'}
        if([int]$frontendInfo.pid -ne [int]$frontend.pid){throw 'FRONTEND_RUNTIME_PID_MISMATCH'}
        Wait-RunnerHttpReady $Session 'backend' "$($backendInfo.apiBase)/api/health" 15
        Wait-RunnerHttpReady $Session 'frontend' "http://127.0.0.1:$($frontendInfo.port)" 15
        return
    }

    $hostRuntime=Assert-RunnerOwnedProcessAlive $Session 'host-runtime'
    $backendHosted=Assert-RunnerOwnedProcessAlive $Session 'backend-hosted'
    $hostProcess=Get-Process -Id ([int]$hostRuntime.pid) -ErrorAction SilentlyContinue
    if(-not $hostProcess -or $hostProcess.MainWindowHandle -eq [IntPtr]::Zero){throw "FULL_SHELL_WINDOW_NOT_READY:pid=$($hostRuntime.pid)"}
    if(-not(Test-Path -LiteralPath ([string]$Session.readiness.frontendIndex) -PathType Leaf)){throw "FULL_FRONTEND_INDEX_NOT_READY:$($Session.readiness.frontendIndex)"}
    if([int]$Session.readiness.backendPid -ne [int]$backendHosted.pid){throw 'FULL_BACKEND_PID_MISMATCH'}
    Wait-RunnerHttpReady $Session 'backend-hosted' "$($Session.readiness.backendApiBase)/api/health" 20
}

function Assert-NoRecordedProcessesRemain {
    param([Parameter(Mandatory)]$Session)
    [void](Assert-NoCloudOSOwnedProcessesRemain $Session)
}

function Test-ExistingActiveSession {
    $state=Join-Path $root '.cloudos-runtime\current-session.json'
    if(-not(Test-Path -LiteralPath $state)){return}
    try{$current=Get-Content -LiteralPath $state -Raw|ConvertFrom-Json}catch{return}
    if([string]$current.status -notin @('starting','running')){return}
    foreach($record in @($current.processes)){
        $check=Test-CloudOSProcessOwnership $current $record
        if($check.running -and $check.owned){throw "ACTIVE_CLOUDOS_SESSION_DETECTED:$($current.id):component=$($record.component):pid=$($record.pid)"}
    }
}

function Invoke-LauncherSmoke {
    param([Parameter(Mandatory)][ValidateSet('WebOnly','Full')][string]$Mode,[switch]$ManualCheckpoint)
    Test-ExistingActiveSession
    $session=$null;$started=$false
    try{
        $args=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'scripts\launch\start-cloudos.ps1'),'-Mode',$Mode,'-NoOpen')
        [void](Invoke-ShortLauncherCommand -Name "launcher-$($Mode.ToLowerInvariant())-start" -Arguments $args -TimeoutSeconds $(if($Mode -eq 'Full'){150}else{90}))
        $started=$true
        $session=Read-RunningSessionForMode $Mode
        Wait-RunnerSessionReady $session $Mode
        $launcherSessions.Add([ordered]@{mode=$Mode;id=$session.id;logDirectory=$session.logDirectory;dataDirectory=$session.dataDirectory;processes=@($session.processes);readiness=$session.readiness})
        Write-JsonFile (Join-Path $evidenceDirectory 'launcher-sessions.json') @($launcherSessions)

        if($ManualCheckpoint){
            $checkpoint=@(
                'CHECKPOINT MANUAL EXTERNO - pressionar ENTER nao significa aprovacao automatica.',
                'O launcher curto já retornou e o runner confirmou readiness/ownership antes deste ponto.',
                'Inspecionar no Full: Browser pelo Menu Iniciar; Terminal abrir/fechar sem afetar outras apps; onboarding/recovery; Files.',
                'A aprovacao fisica/visual pertence ao Gemini Low, usuario e Copilot principal.'
            )
            Set-Content -LiteralPath (Join-Path $evidenceDirectory 'manual-checkpoint.txt') -Value $checkpoint -Encoding UTF8
            Write-Host '';Write-Host '=== CHECKPOINT PARA GEMINI LOW / USUARIO ===';$checkpoint|ForEach-Object{Write-Host $_}
            if(-not $NonInteractive){
                [void](Read-Host 'Quando terminar a inspecao externa, pressione ENTER para executar teardown e checagem de orfaos')
                $session=Read-RunningSessionForMode $Mode
                Wait-RunnerSessionReady $session $Mode
            }else{
                Add-Content -LiteralPath (Join-Path $evidenceDirectory 'manual-checkpoint.txt') -Value 'NONINTERACTIVE_CHECKPOINT_REACHED=true' -Encoding UTF8
            }
        }
    }finally{
        if($started){
            try{
                $stopArgs=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'scripts\launch\stop-cloudos.ps1'))
                [void](Invoke-ShortLauncherCommand -Name "launcher-$($Mode.ToLowerInvariant())-stop" -Arguments $stopArgs -TimeoutSeconds 45)
            }finally{
                Start-Sleep -Milliseconds 400
                if($session){Assert-NoRecordedProcessesRemain $session}
            }
        }
    }
}

Push-Location $root
try{
    $branch=(& git branch --show-current 2>$null).Trim()
    $head=(& git rev-parse HEAD 2>$null).Trim()
    $mergeBase=(& git merge-base HEAD $expectedBase 2>$null).Trim()
    if($branch -ne $expectedBranch){throw "WRONG_BRANCH:$branch"}
    if($mergeBase -ne $expectedBase){throw "WRONG_BASE:$mergeBase"}
    & git merge-base --is-ancestor $expectedBase HEAD
    if($LASTEXITCODE -ne 0){throw 'BASE_NOT_ANCESTOR'}

    $executionId="$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $runDirectory=Join-Path $root "test-results\stabilization-batch-1\$head\$executionId"
    $commandsDirectory=Join-Path $runDirectory 'commands'
    $safetyDirectory=Join-Path $runDirectory 'safety'
    $evidenceDirectory=Join-Path $runDirectory 'evidence'
    $dependencyDirectory=Join-Path $evidenceDirectory 'dependencies'
    $isolatedDataDirectory=Join-Path $runDirectory 'isolated-data'
    New-Item -ItemType Directory -Force -Path $commandsDirectory,$safetyDirectory,$evidenceDirectory,$dependencyDirectory,$isolatedDataDirectory|Out-Null

    $pwshResolution=Resolve-CloudOSPowerShell7;$pwsh=[string]$pwshResolution.path
    $pwshDir=Split-Path -Parent $pwsh
    if($pwshDir -and (@([string]$env:PATH -split [IO.Path]::PathSeparator) -notcontains $pwshDir)){$env:PATH="$pwshDir$([IO.Path]::PathSeparator)$env:PATH"}
    Write-JsonFile (Join-Path $evidenceDirectory 'pwsh-resolution.json') $pwshResolution

    $node=Resolve-RequiredCommand @('node.exe','node')
    $npm=Resolve-RequiredCommand @('npm.cmd','npm')
    $npx=Resolve-RequiredCommand @('npx.cmd','npx')
    $dotnet=Resolve-RequiredCommand @('dotnet.exe','dotnet')
    $previousEnvironment=[ordered]@{NODE_ENV=$env:NODE_ENV;CLOUDOS_DATA_DIR=$env:CLOUDOS_DATA_DIR;CLOUDOS_TEST_ROOT=$env:CLOUDOS_TEST_ROOT;DATABASE_PATH=$env:DATABASE_PATH;CLOUDOS_NATIVE_HOST=$env:CLOUDOS_NATIVE_HOST}
    $baseData=Join-Path $isolatedDataDirectory 'validation';New-Item -ItemType Directory -Force -Path $baseData|Out-Null
    $env:NODE_ENV='test';$env:CLOUDOS_DATA_DIR=$baseData;$env:CLOUDOS_TEST_ROOT=$baseData;$env:DATABASE_PATH=Join-Path $baseData 'cloudos.json';$env:CLOUDOS_NATIVE_HOST='0'

    Write-JsonFile (Join-Path $runDirectory 'git.json') ([ordered]@{branch=$branch;head=$head;expectedBase=$expectedBase;mergeBase=$mergeBase;timestamp=(Get-Date).ToUniversalTime().ToString('o')})
    Write-JsonFile (Join-Path $runDirectory 'environment.json') ([ordered]@{os=[Environment]::OSVersion.VersionString;machine=$env:COMPUTERNAME;powershell=$PSVersionTable.PSVersion.ToString();powershellPath=$pwsh;node=(& $node --version 2>$null|Select-Object -First 1);nodePath=$node;npm=(& $npm --version 2>$null|Select-Object -First 1);npmPath=$npm;npxPath=$npx;dotnet=(& $dotnet --version 2>$null|Select-Object -First 1);dotnetPath=$dotnet;isolatedDataDirectory=$isolatedDataDirectory;databasePath=$env:DATABASE_PATH;realDatabaseUsed=$false})
    Write-JsonFile (Join-Path $runDirectory 'manifest.json') ([ordered]@{schemaVersion=2;batch='stabilization-batch-1';branch=$branch;head=$head;base=$expectedBase;executionId=$executionId;startedAt=(Get-Date).ToUniversalTime().ToString('o');status='running';physicalEntryPoint='Validar CloudOS.cmd';resultDirectory=$runDirectory})

    Save-ProcessSnapshot 'before';Save-WslSnapshot 'before'
    Invoke-CapturedCommand 'safety-boundary' $pwsh @('-NoLogo','-NoProfile','-File',(Join-Path $root 'scripts\validate\test-stabilization-safety-boundary.ps1'))
    Invoke-CapturedCommand 'launcher-contract' $pwsh @('-NoLogo','-NoProfile','-File',(Join-Path $root 'scripts\validate\test-launcher-contract.ps1'))

    $dependencyResult=Ensure-CloudOSNodeDependencies -Root $root -EvidenceDirectory $dependencyDirectory -AllowInstall:(-not $SkipInstall)
    Write-JsonFile (Join-Path $evidenceDirectory 'dependency-summary.json') ([ordered]@{strategy='root-workspaces-single-install';installPerformed=$dependencyResult.installPerformed;evidenceDirectory=$dependencyDirectory;resolved=$dependencyResult.resolved;versions=$dependencyResult.versions})
    if(-not $SkipInstall){Invoke-CapturedCommand 'playwright-install-chromium' $npx @('playwright','install','chromium')}

    Invoke-CapturedCommand 'lint' $npm @('run','lint')
    Invoke-CapturedCommand 'build' $npm @('run','build')
    Invoke-CapturedCommand 'backend-tests' $npm @('test') (Get-IsolatedTestEnvironment 'backend-regression')
    Invoke-CapturedCommand 'e2e-tests' $npm @('run','test:e2e') (Get-IsolatedTestEnvironment 'e2e-regression')
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
    foreach($contract in @('scripts/test-native-host-freshness.ps1','scripts/test-wsl-core-foundation-contract.ps1','scripts/test-wsl-core-secure-terminal-contract.ps1','scripts/test-visible-terminal-wsl-core-contract.ps1')){
        $name=[IO.Path]::GetFileNameWithoutExtension($contract)
        Invoke-CapturedCommand $name $pwsh @('-NoLogo','-NoProfile','-File',(Join-Path $root $contract))
    }
    Invoke-CapturedCommand 'playwright-characterization' $npx @('playwright','test','--grep-invert','Navegador CloudOS — WebView2 real|Navegador CloudOS — lifecycle Windows','--output',(Join-Path $runDirectory 'playwright-characterization'),'--reporter=list')
    Invoke-CapturedCommand 'playwright-browser-lifecycle' $npx @('playwright','test','tests/playwright/native-browser-lifecycle.spec.ts','--output',(Join-Path $runDirectory 'playwright-native-browser-lifecycle'),'--reporter=list')
    Invoke-CapturedCommand 'playwright-browser' $npx @('playwright','test','tests/playwright/native-browser.spec.ts','--output',(Join-Path $runDirectory 'playwright-native-browser'),'--reporter=list')

    Invoke-LauncherSmoke -Mode 'WebOnly'
    Invoke-LauncherSmoke -Mode 'Full' -ManualCheckpoint

    Save-WslSnapshot 'after';Save-ProcessSnapshot 'after'
    $beforeWsl=Get-Content -LiteralPath (Join-Path $safetyDirectory 'wsl-before.txt') -Raw
    $afterWsl=Get-Content -LiteralPath (Join-Path $safetyDirectory 'wsl-after.txt') -Raw
    Write-JsonFile (Join-Path $runDirectory 'summary.json') ([ordered]@{schemaVersion=2;status='passed';branch=$branch;head=$head;base=$expectedBase;commandCount=$commandResults.Count;launcherModes=@($launcherSessions|ForEach-Object{$_.mode});dependencyStrategy='root-workspaces-single-install';dependencyInstallPerformed=$dependencyResult.installPerformed;isolatedDataDirectory=$isolatedDataDirectory;realDatabaseUsed=$false;wslMutationCommandsExecuted=$false;wslReadOnlySnapshotStable=($beforeWsl -eq $afterWsl);physicalAndVisualApproval='external-pending';finishedAt=(Get-Date).ToUniversalTime().ToString('o')})
    Write-JsonFile (Join-Path $runDirectory 'manifest.json') ([ordered]@{schemaVersion=2;batch='stabilization-batch-1';branch=$branch;head=$head;base=$expectedBase;executionId=$executionId;status='passed';physicalEntryPoint='Validar CloudOS.cmd';resultDirectory=$runDirectory;finishedAt=(Get-Date).ToUniversalTime().ToString('o')})
    Write-Host '';Write-Host 'CLOUDOS_STABILIZATION_BATCH_1_VALIDATION_PASSED';Write-Host "RESULTS=$runDirectory";Write-Host 'VALIDACAO FISICA/VISUAL: permanece externa e nao e declarada por este script.'
}catch{
    if($runDirectory -and (Test-Path -LiteralPath $runDirectory)){
        Write-JsonFile (Join-Path $runDirectory 'summary.json') ([ordered]@{schemaVersion=2;status='failed';error=$_.Exception.Message;physicalAndVisualApproval='external-pending';finishedAt=(Get-Date).ToUniversalTime().ToString('o')})
    }
    throw
}finally{
    if($previousEnvironment){foreach($name in $previousEnvironment.Keys){$value=$previousEnvironment[$name];if($null -eq $value){Remove-Item "Env:$name" -ErrorAction SilentlyContinue}else{[Environment]::SetEnvironmentVariable($name,[string]$value,'Process')}}}
    Pop-Location
}