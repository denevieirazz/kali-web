param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CloudOSRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:RuntimeStateRoot = Join-Path $script:CloudOSRoot '.cloudos-runtime'
$script:SessionStateFile = Join-Path $script:RuntimeStateRoot 'current-session.json'
$script:AllowedModes = @('Full','WebOnly','Developer','UXValidation','FilesValidation','BrowserValidation','TerminalValidation')
$script:IdentityGranularityTicks = [TimeSpan]::TicksPerMillisecond

function Write-CloudOSJsonAtomic {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $directory = Split-Path -Parent $Path
    if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Set-CloudOSObjectProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Value
    )
    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return
    }
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-CloudOSGitInfo {
    Push-Location $script:CloudOSRoot
    try {
        $branch = (& git branch --show-current 2>$null).Trim()
        $sha = (& git rev-parse HEAD 2>$null).Trim()
        $dirty = @(& git status --porcelain 2>$null).Count -gt 0
        return [ordered]@{ branch=$branch; sha=$sha; dirty=$dirty }
    } finally { Pop-Location }
}

function New-CloudOSSession {
    param([Parameter(Mandatory)][string]$Mode)
    if ($script:AllowedModes -notcontains $Mode) { throw "Modo inválido: $Mode" }
    $git = Get-CloudOSGitInfo
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $id = [guid]::NewGuid().ToString('N').Substring(0,10)
    $sessionDir = Join-Path $script:CloudOSRoot "logs\session-$stamp-$id"
    New-Item -ItemType Directory -Force -Path $sessionDir | Out-Null
    foreach($name in @('launcher.log','backend.stdout.log','backend.stderr.log','frontend.stdout.log','frontend.stderr.log','host.log','host.stderr.log','bootstrap.log','wsl-core.log')) {
        New-Item -ItemType File -Force -Path (Join-Path $sessionDir $name) | Out-Null
    }
    $session = [pscustomobject][ordered]@{
        schemaVersion=2
        id=$id
        mode=$Mode
        startedAt=(Get-Date).ToUniversalTime().ToString('o')
        finishedAt=$null
        root=$script:CloudOSRoot
        logDirectory=$sessionDir
        runtimeDirectory=(Join-Path $sessionDir 'runtime')
        dataDirectory=(Join-Path $sessionDir 'data')
        git=$git
        processes=@()
        status='starting'
        readiness=$null
        teardownResult=$null
        stoppedProcesses=@()
        preservedProcesses=@()
        failures=@()
    }
    New-Item -ItemType Directory -Force -Path $session.runtimeDirectory,$session.dataDirectory | Out-Null
    Write-CloudOSJsonAtomic (Join-Path $sessionDir 'environment.json') ([ordered]@{
        os=[Environment]::OSVersion.VersionString
        machine=$env:COMPUTERNAME
        user=$env:USERNAME
        powershell=$PSVersionTable.PSVersion.ToString()
        mode=$Mode
        timestamp=(Get-Date).ToUniversalTime().ToString('o')
    })
    Write-CloudOSJsonAtomic (Join-Path $sessionDir 'manifest.json') $session
    Write-CloudOSJsonAtomic $script:SessionStateFile $session
    return $session
}

function Write-CloudOSLog {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][string]$Message,[string]$Level='INFO')
    $line = "$(Get-Date -Format o) [$Level] $Message"
    Add-Content -LiteralPath (Join-Path ([string]$Session.logDirectory) 'launcher.log') -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-CommandPathRequired {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)]$Session)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) { Write-CloudOSLog $Session "Pré-requisito ausente: $Name" 'ERROR'; throw "PRECONDITION_MISSING:$Name" }
    return $cmd.Source
}

function Test-WebView2Runtime {
    $roots = @('HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients','HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients','HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients')
    foreach($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        foreach($child in Get-ChildItem $root -ErrorAction SilentlyContinue) {
            $item = Get-ItemProperty $child.PSPath -ErrorAction SilentlyContinue
            if (("$($item.name) $($item.pv)") -match 'WebView2') { return $true }
        }
    }
    $known = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\EdgeWebView\Application'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\EdgeWebView\Application')
    ) | Where-Object { $_ -and (Test-Path $_) }
    return $known.Count -gt 0
}

function Get-CloudOSWsl2Distro {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) { return $null }
    $lines = @(& wsl.exe -l -v 2>$null)
    foreach($line in $lines) {
        $clean = ($line -replace '\x00','').Trim()
        if ($clean -match '^\*?\s*(\S.*?)\s{2,}\S+\s{2,}2\s*$') { return $Matches[1].Trim() }
    }
    return $null
}

function Test-CloudOSPrerequisites {
    param([Parameter(Mandatory)]$Session)
    $mode = $Session.mode
    $required = [ordered]@{}
    $required.node = Get-CommandPathRequired 'node' $Session
    $required.npm = Get-CommandPathRequired 'npm' $Session
    $required.pwsh = Get-CommandPathRequired 'pwsh' $Session
    if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'POWERSHELL_7_REQUIRED' }
    if ($mode -in @('Full','BrowserValidation')) {
        $required.dotnet = Get-CommandPathRequired 'dotnet' $Session
        if (-not (Test-WebView2Runtime)) { throw 'WEBVIEW2_RUNTIME_NOT_DETECTED' }
    }
    if ($mode -in @('FilesValidation','TerminalValidation')) {
        $distro = Get-CloudOSWsl2Distro
        if (-not $distro) { throw 'WSL2_DISTRO_REQUIRED' }
        $required.wslDistro = $distro
        $goCheck = & wsl.exe -d $distro -- sh -lc 'command -v go >/dev/null 2>&1 && go version' 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'WSL_GO_REQUIRED' }
        $required.wslGo = ($goCheck | Select-Object -First 1)
    }
    Write-CloudOSJsonAtomic (Join-Path $Session.logDirectory 'prerequisites.json') $required
    return $required
}

function Get-CloudOSProcessSnapshot {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CreationDate,CommandLine
}

function Save-CloudOSProcessSnapshot {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][ValidateSet('before','after')]$When)
    Write-CloudOSJsonAtomic (Join-Path $Session.logDirectory "processes-$When.json") (Get-CloudOSProcessSnapshot)
}

function ConvertTo-CloudOSSanitizedCommandLine {
    param([AllowNull()][string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return '' }
    $safe = [string]$CommandLine
    $safe = [regex]::Replace($safe,'(?i)(authorization|bearer|jwt|token|password|passwd|secret|recovery[_-]?code|api[_-]?key)(\s*[:=]\s*|\s+)("[^"]*"|''[^'']*''|\S+)','$1=<redacted>')
    if ($safe.Length -gt 4096) { $safe = $safe.Substring(0,4096) + '<truncated>' }
    return $safe
}

function ConvertTo-CloudOSNormalizedCreationTicks {
    param([Parameter(Mandatory)][datetime]$Timestamp)
    $ticks = $Timestamp.ToUniversalTime().Ticks
    $normalized = $ticks - ($ticks % $script:IdentityGranularityTicks)
    return [string]$normalized
}

function Normalize-CloudOSExecutablePath {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try { return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) }
    catch { return $null }
}

function Get-CloudOSProcessIdentity {
    param([Parameter(Mandatory)][int]$ProcessId)
    $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cim) { return [pscustomobject][ordered]@{ exists=$false; pid=$ProcessId } }

    $creation = $null
    try {
        if ($cim.CreationDate -is [datetime]) { $creation = [datetime]$cim.CreationDate }
        elseif ($cim.CreationDate) { $creation = [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$cim.CreationDate) }
    } catch { $creation = $null }
    if (-not $creation) {
        try { $creation = (Get-Process -Id $ProcessId -ErrorAction Stop).StartTime } catch { $creation = $null }
    }

    $executable = Normalize-CloudOSExecutablePath ([string]$cim.ExecutablePath)
    if (-not $executable) {
        try { $executable = Normalize-CloudOSExecutablePath ([string](Get-Process -Id $ProcessId -ErrorAction Stop).Path) } catch { $executable = $null }
    }

    return [pscustomobject][ordered]@{
        exists=$true
        pid=$ProcessId
        parentPid=$(if($null -eq $cim.ParentProcessId){$null}else{[int]$cim.ParentProcessId})
        processName=[string]$cim.Name
        executablePath=$executable
        creationUtcTicks=if($creation){ConvertTo-CloudOSNormalizedCreationTicks $creation}else{$null}
        creationTimeUtc=if($creation){$creation.ToUniversalTime().ToString('o')}else{$null}
        commandLineSanitized=ConvertTo-CloudOSSanitizedCommandLine ([string]$cim.CommandLine)
    }
}

function Get-CloudOSRecordCreationTicks {
    param([Parameter(Mandatory)]$Record)
    if ($Record.PSObject.Properties.Name -contains 'creationUtcTicks' -and $Record.creationUtcTicks) {
        return [string]$Record.creationUtcTicks
    }
    if ($Record.PSObject.Properties.Name -contains 'startedAt' -and $Record.startedAt) {
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse([string]$Record.startedAt,[ref]$parsed)) {
            return ConvertTo-CloudOSNormalizedCreationTicks $parsed
        }
    }
    return $null
}

function Test-CloudOSProcessOwnership {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)]$Record)
    $pidValue = 0
    if (-not [int]::TryParse([string]$Record.pid,[ref]$pidValue) -or $pidValue -le 0) {
        return [pscustomobject][ordered]@{ owned=$false; running=$false; reason='invalid-pid'; pid=$pidValue; identity=$null }
    }
    if (-not $Session.id -or -not $Session.logDirectory) {
        return [pscustomobject][ordered]@{ owned=$false; running=$true; reason='session-identity-incomplete'; pid=$pidValue; identity=$null }
    }
    if (-not ($Record.PSObject.Properties.Name -contains 'sessionId') -or [string]$Record.sessionId -ne [string]$Session.id) {
        return [pscustomobject][ordered]@{ owned=$false; running=$true; reason='session-id-mismatch'; pid=$pidValue; identity=$null }
    }
    if (-not ($Record.PSObject.Properties.Name -contains 'logDirectory') -or [string]$Record.logDirectory -ne [string]$Session.logDirectory) {
        return [pscustomobject][ordered]@{ owned=$false; running=$true; reason='session-logdir-mismatch'; pid=$pidValue; identity=$null }
    }
    $expectedTicks = Get-CloudOSRecordCreationTicks $Record
    $expectedPath = if($Record.PSObject.Properties.Name -contains 'executablePath'){Normalize-CloudOSExecutablePath ([string]$Record.executablePath)}else{$null}
    if (-not $expectedTicks -or -not $expectedPath) {
        return [pscustomobject][ordered]@{ owned=$false; running=$true; reason='record-identity-incomplete'; pid=$pidValue; identity=$null }
    }

    $identity = Get-CloudOSProcessIdentity $pidValue
    if (-not $identity.exists) {
        return [pscustomobject][ordered]@{ owned=$false; running=$false; reason='not-running'; pid=$pidValue; identity=$identity }
    }
    if (-not $identity.creationUtcTicks -or [string]$identity.creationUtcTicks -ne [string]$expectedTicks) {
        return [pscustomobject][ordered]@{ owned=$false; running=$true; reason='creation-time-mismatch'; pid=$pidValue; identity=$identity }
    }
    if (-not $identity.executablePath -or -not [string]::Equals([string]$identity.executablePath,[string]$expectedPath,[StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject][ordered]@{ owned=$false; running=$true; reason='executable-path-mismatch'; pid=$pidValue; identity=$identity }
    }
    return [pscustomobject][ordered]@{ owned=$true; running=$true; reason='owned'; pid=$pidValue; identity=$identity }
}

function Add-CloudOSProcessRecordByPid {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$Component,
        [string]$StdOut='',
        [string]$StdErr=''
    )
    $identity = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        $identity = Get-CloudOSProcessIdentity $ProcessId
        if ($identity.exists -and $identity.creationUtcTicks -and $identity.executablePath) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $identity.exists -or -not $identity.creationUtcTicks -or -not $identity.executablePath) {
        throw "PROCESS_IDENTITY_UNAVAILABLE:${Component}:pid=$ProcessId"
    }

    $existing = @($Session.processes | Where-Object { [int]$_.pid -eq $ProcessId -and [string]$_.component -eq $Component })
    if ($existing.Count -gt 0) { return $existing[0] }
    $record = [pscustomobject][ordered]@{
        component=$Component
        pid=$ProcessId
        parentPid=$identity.parentPid
        sessionId=[string]$Session.id
        logDirectory=[string]$Session.logDirectory
        creationUtcTicks=[string]$identity.creationUtcTicks
        creationTimeUtc=[string]$identity.creationTimeUtc
        startedAt=[string]$identity.creationTimeUtc
        executablePath=[string]$identity.executablePath
        commandLineSanitized=[string]$identity.commandLineSanitized
        processName=[string]$identity.processName
        stdout=$StdOut
        stderr=$StdErr
    }
    Set-CloudOSObjectProperty $Session 'processes' (@($Session.processes) + @($record))
    Write-CloudOSJsonAtomic (Join-Path $Session.logDirectory 'manifest.json') $Session
    Write-CloudOSJsonAtomic $script:SessionStateFile $Session
    return $record
}

function Add-CloudOSProcessRecord {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][System.Diagnostics.Process]$Process,[Parameter(Mandatory)][string]$Component,[string]$StdOut='',[string]$StdErr='')
    return Add-CloudOSProcessRecordByPid -Session $Session -ProcessId $Process.Id -Component $Component -StdOut $StdOut -StdErr $StdErr
}

function Get-CloudOSDetachedBootstrapPath {
    param([Parameter(Mandatory)]$Session)
    $path = Join-Path $Session.runtimeDirectory 'detached-process-bootstrap.cjs'
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    $source = @'
const fs = require('fs');
const { spawn } = require('child_process');
const configPath = process.argv[2];
if (!configPath) { console.error('CONFIG_PATH_REQUIRED'); process.exit(2); }
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const stdoutFd = fs.openSync(config.stdout, 'a');
const stderrFd = fs.openSync(config.stderr, 'a');
let settled = false;
const child = spawn(config.filePath, config.arguments || [], {
  cwd: config.workingDirectory,
  env: { ...process.env, ...(config.environment || {}) },
  detached: true,
  windowsHide: true,
  stdio: ['ignore', stdoutFd, stderrFd]
});
function closeBootstrapDescriptors() {
  for (const fd of [stdoutFd, stderrFd]) { try { fs.closeSync(fd); } catch {} }
}
child.once('error', (error) => {
  if (settled) return;
  settled = true;
  closeBootstrapDescriptors();
  console.error(`CHILD_SPAWN_FAILED:${error.message}`);
  process.exit(3);
});
child.once('spawn', () => {
  if (settled) return;
  settled = true;
  const result = { pid: child.pid, bootstrapPid: process.pid, createdAt: new Date().toISOString() };
  const temp = `${config.resultPath}.${process.pid}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(result, null, 2), 'utf8');
  fs.renameSync(temp, config.resultPath);
  child.unref();
  closeBootstrapDescriptors();
  process.exit(0);
});
setTimeout(() => {
  if (settled) return;
  settled = true;
  closeBootstrapDescriptors();
  console.error('CHILD_SPAWN_TIMEOUT');
  process.exit(4);
}, 10000).unref();
'@
    Set-Content -LiteralPath $path -Value $source -Encoding UTF8
    return $path
}

function Start-CloudOSLoggedProcess {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList=@(),
        [Parameter(Mandatory)][string]$StdOut,
        [Parameter(Mandatory)][string]$StdErr,
        [hashtable]$Environment=@{}
    )
    $nodeBootstrap = (Get-Command node -ErrorAction Stop).Source
    $bootstrapPath = Get-CloudOSDetachedBootstrapPath $Session
    $safeComponent = ($Component -replace '[^A-Za-z0-9_.-]','_')
    $configPath = Join-Path $Session.runtimeDirectory "$safeComponent.detached.json"
    $resultPath = Join-Path $Session.runtimeDirectory "$safeComponent.pid.json"
    $bootstrapStdout = Join-Path $Session.logDirectory "$safeComponent.bootstrap.stdout.log"
    $bootstrapStderr = Join-Path $Session.logDirectory "$safeComponent.bootstrap.stderr.log"
    foreach($path in @($StdOut,$StdErr,$bootstrapStdout,$bootstrapStderr)) { New-Item -ItemType File -Force -Path $path | Out-Null }
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue

    $childEnvironment = [ordered]@{}
    foreach($key in $Environment.Keys) { $childEnvironment[[string]$key] = [string]$Environment[$key] }
    $childEnvironment['CLOUDOS_SESSION_ID'] = [string]$Session.id
    $childEnvironment['CLOUDOS_SESSION_LOG_DIR'] = [string]$Session.logDirectory
    $childEnvironment['CLOUDOS_RUN_ID'] = [string]$Session.id

    Write-CloudOSJsonAtomic $configPath ([ordered]@{
        filePath=$FilePath
        arguments=@($ArgumentList)
        workingDirectory=$script:CloudOSRoot
        environment=$childEnvironment
        stdout=$StdOut
        stderr=$StdErr
        resultPath=$resultPath
        sessionId=[string]$Session.id
        logDirectory=[string]$Session.logDirectory
    })

    $quotedBootstrap = '"' + $bootstrapPath + '"'
    $quotedConfig = '"' + $configPath + '"'
    $bootstrapProcess = Start-Process -FilePath $nodeBootstrap -ArgumentList @($quotedBootstrap,$quotedConfig) -WorkingDirectory $script:CloudOSRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $bootstrapStdout -RedirectStandardError $bootstrapStderr
    try {
        if (-not $bootstrapProcess.WaitForExit(15000)) {
            Stop-Process -Id $bootstrapProcess.Id -Force -ErrorAction SilentlyContinue
            throw "DETACHED_BOOTSTRAP_TIMEOUT:${Component}:log=$bootstrapStderr"
        }
        if ($bootstrapProcess.ExitCode -ne 0) {
            $tail = (Get-Content -LiteralPath $bootstrapStderr -Tail 30 -ErrorAction SilentlyContinue) -join ' | '
            throw "DETACHED_BOOTSTRAP_FAILED:${Component}:exit=$($bootstrapProcess.ExitCode):log=${bootstrapStderr}:error=$tail"
        }
    } finally { $bootstrapProcess.Dispose() }

    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while (-not (Test-Path -LiteralPath $resultPath) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $resultPath)) { throw "DETACHED_CHILD_PID_MISSING:${Component}:$resultPath" }
    $spawnResult = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $pidValue = [int]$spawnResult.pid
    $process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
    if (-not $process) {
        $tail = (Get-Content -LiteralPath $StdErr -Tail 30 -ErrorAction SilentlyContinue) -join ' | '
        throw "DETACHED_CHILD_EXITED_EARLY:${Component}:pid=${pidValue}:log=${StdErr}:error=$tail"
    }
    [void](Add-CloudOSProcessRecord -Session $Session -Process $process -Component $Component -StdOut $StdOut -StdErr $StdErr)
    Write-CloudOSLog $Session "$Component iniciado de forma desacoplada pid=$pidValue stdout=$StdOut stderr=$StdErr."
    return $process
}

function Get-CloudOSComponentErrorLog {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][string]$Component)
    switch -Regex ($Component) {
        '^backend' { return Join-Path $Session.logDirectory 'backend.stderr.log' }
        '^frontend' { return Join-Path $Session.logDirectory 'frontend.stderr.log' }
        '^host' { return Join-Path $Session.logDirectory 'host.stderr.log' }
        default { return Join-Path $Session.logDirectory 'launcher.log' }
    }
}

function Assert-CloudOSProcessAlive {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][System.Diagnostics.Process]$Process,[Parameter(Mandatory)][string]$Component)
    $record = @($Session.processes | Where-Object { [int]$_.pid -eq $Process.Id -and [string]$_.component -eq $Component } | Select-Object -First 1)
    if ($record.Count -eq 0) { throw "PROCESS_RECORD_MISSING:${Component}:pid=$($Process.Id)" }
    $ownership = Test-CloudOSProcessOwnership $Session $record[0]
    if (-not $ownership.running) {
        $log = Get-CloudOSComponentErrorLog $Session $Component
        $tail = (Get-Content -LiteralPath $log -Tail 30 -ErrorAction SilentlyContinue) -join ' | '
        throw "PROCESS_DIED_BEFORE_READINESS component=$Component pid=$($Process.Id) log=$log error=$tail"
    }
    if (-not $ownership.owned) { throw "PROCESS_OWNERSHIP_LOST_BEFORE_READINESS:${Component}:pid=$($Process.Id):reason=$($ownership.reason)" }
}

function Wait-CloudOSReadinessFile {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][System.Diagnostics.Process]$Process,[Parameter(Mandatory)][string]$Component,[Parameter(Mandatory)][string]$Path,[int]$TimeoutSeconds=25)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while([DateTime]::UtcNow -lt $deadline) {
        Assert-CloudOSProcessAlive $Session $Process $Component
        if (Test-Path -LiteralPath $Path) {
            try {
                $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
                if ($manifest) { return $manifest }
            } catch { }
        }
        Start-Sleep -Milliseconds 120
    }
    throw "READINESS_TIMEOUT component=$Component path=$Path log=$($Session.logDirectory)"
}

function Wait-CloudOSHttpReady {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][string]$Uri,
        [int]$TimeoutSeconds=15
    )
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastError=''
    while([DateTime]::UtcNow -lt $deadline) {
        Assert-CloudOSProcessAlive $Session $Process $Component
        try {
            $response=Invoke-WebRequest -Uri $Uri -Method Get -TimeoutSec 2 -SkipHttpErrorCheck
            if ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 400) { return $response }
            $lastError="HTTP $([int]$response.StatusCode)"
        } catch { $lastError=$_.Exception.Message }
        Start-Sleep -Milliseconds 200
    }
    throw "HTTP_READINESS_TIMEOUT component=$Component uri=$Uri error=$(ConvertTo-CloudOSSanitizedCommandLine $lastError)"
}

function Get-CloudOSDescendantCimProcesses {
    param([Parameter(Mandatory)][int]$RootPid)
    $all=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $children=@{}
    foreach($item in $all) {
        $parent=[int]$item.ParentProcessId
        if(-not $children.ContainsKey($parent)){$children[$parent]=[System.Collections.Generic.List[object]]::new()}
        $children[$parent].Add($item)
    }
    $result=[System.Collections.Generic.List[object]]::new()
    $queue=[System.Collections.Generic.Queue[int]]::new();$queue.Enqueue($RootPid)
    while($queue.Count -gt 0){
        $current=$queue.Dequeue()
        if(-not $children.ContainsKey($current)){continue}
        foreach($child in $children[$current]){$result.Add($child);$queue.Enqueue([int]$child.ProcessId)}
    }
    return @($result)
}

function Wait-CloudOSHostRuntime {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][System.Diagnostics.Process]$HostLauncher,[int]$TimeoutSeconds=45)
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while([DateTime]::UtcNow -lt $deadline){
        Assert-CloudOSProcessAlive $Session $HostLauncher 'host'
        foreach($candidate in @(Get-CloudOSDescendantCimProcesses $HostLauncher.Id)){
            $exe=[string]$candidate.ExecutablePath
            $cmd=[string]$candidate.CommandLine
            $looksLikeHost=($exe -match '(?i)CloudOS\.Host\.exe$') -or ($cmd -match '(?i)CloudOS\.Host(?:\.dll|\.csproj)')
            if(-not $looksLikeHost){continue}
            $p=Get-Process -Id ([int]$candidate.ProcessId) -ErrorAction SilentlyContinue
            if(-not $p){continue}
            if($p.MainWindowHandle -eq [IntPtr]::Zero){continue}
            [void](Add-CloudOSProcessRecord -Session $Session -Process $p -Component 'host-runtime' -StdOut (Join-Path $Session.logDirectory 'host.log') -StdErr (Join-Path $Session.logDirectory 'host.stderr.log'))
            return $p
        }
        Start-Sleep -Milliseconds 200
    }
    throw "HOST_UI_READINESS_TIMEOUT:launcherPid=$($HostLauncher.Id):log=$($Session.logDirectory)"
}

function Get-CloudOSOwnedSessionManifest {
    param([Parameter(Mandatory)]$Session)
    if (-not $Session.id) { throw 'SESSION_OWNERSHIP_ID_MISSING' }
    if (-not $Session.logDirectory) { throw 'SESSION_OWNERSHIP_LOG_DIRECTORY_MISSING' }
    $manifestPath = Join-Path ([string]$Session.logDirectory) 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "SESSION_OWNERSHIP_MANIFEST_MISSING:$manifestPath" }
    try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
    catch { throw "SESSION_OWNERSHIP_MANIFEST_INVALID:${manifestPath}:$($_.Exception.Message)" }
    if ([string]$manifest.id -ne [string]$Session.id) { throw "SESSION_OWNERSHIP_MANIFEST_ID_MISMATCH:expected=$($Session.id):actual=$($manifest.id)" }
    if ([string]$manifest.logDirectory -ne [string]$Session.logDirectory) { throw 'SESSION_OWNERSHIP_MANIFEST_LOG_DIRECTORY_MISMATCH' }
    return [ordered]@{ path=$manifestPath; manifest=$manifest }
}

function Register-CloudOSOwnedDescendants {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)]$RootRecord)
    $rootOwnership=Test-CloudOSProcessOwnership $Session $RootRecord
    if(-not $rootOwnership.owned){return @()}
    $added=[System.Collections.Generic.List[object]]::new()
    foreach($item in @(Get-CloudOSDescendantCimProcesses ([int]$RootRecord.pid))){
        $processId=[int]$item.ProcessId
        if(@($Session.processes|Where-Object{[int]$_.pid -eq $processId}).Count -gt 0){continue}
        try{
            $record=Add-CloudOSProcessRecordByPid -Session $Session -ProcessId $processId -Component "descendant:$([string]$item.Name)"
            $added.Add($record)
        }catch{Write-CloudOSLog $Session "Descendente pid=$processId não pôde ser registrado com identidade completa; será preservado. $($_.Exception.Message)" 'WARN'}
    }
    return @($added)
}

function Invoke-CloudOSGracefulStop {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)]$Record,[Parameter(Mandatory)][System.Diagnostics.Process]$Process,[int]$TimeoutMilliseconds=5000)
    $method='graceful-taskkill'
    try{
        $Process.Refresh()
        if($Process.MainWindowHandle -ne [IntPtr]::Zero){
            $method='graceful-close-main-window'
            [void]$Process.CloseMainWindow()
        }else{
            $taskkill=(Get-Command taskkill.exe -ErrorAction SilentlyContinue)
            if($taskkill){
                & $taskkill.Source /PID $Process.Id *>> (Join-Path $Session.logDirectory 'teardown.log')
            }else{
                $method='graceful-unavailable'
            }
        }
    }catch{
        Write-CloudOSLog $Session "Tentativa graciosa falhou component=$($Record.component) pid=$($Record.pid): $($_.Exception.Message)" 'WARN'
    }
    try{if($Process.WaitForExit($TimeoutMilliseconds)){return [ordered]@{exited=$true;method=$method}}}catch{}
    return [ordered]@{exited=$false;method=$method}
}

function Stop-CloudOSRecordedProcesses {
    param([Parameter(Mandatory)]$Session)
    $ownership=Get-CloudOSOwnedSessionManifest $Session
    $manifest=$ownership.manifest

    foreach($rootRecord in @($manifest.processes | Where-Object { -not ([string]$_.component).StartsWith('descendant:') })) {
        [void](Register-CloudOSOwnedDescendants -Session $Session -RootRecord $rootRecord)
    }
    $ownership=Get-CloudOSOwnedSessionManifest $Session
    $manifest=$ownership.manifest

    $stopped=[System.Collections.Generic.List[object]]::new()
    $preserved=[System.Collections.Generic.List[object]]::new()
    $failures=[System.Collections.Generic.List[object]]::new()
    $records=@($manifest.processes | Sort-Object -Property @(
        @{Expression={
            $component=[string]$_.component
            if($component -eq 'host-runtime'){0}
            elseif($component -in @('backend-hosted','backend','frontend')){1}
            elseif($component -eq 'host'){2}
            elseif($component.StartsWith('descendant:')){3}
            else{2}
        }},
        @{Expression={[int]$_.pid};Descending=$true}
    ))

    foreach($record in $records){
        $check=Test-CloudOSProcessOwnership $Session $record
        if(-not $check.running){
            $stopped.Add([ordered]@{component=$record.component;pid=[int]$record.pid;result='already-exited';method='none'})
            continue
        }
        if(-not $check.owned){
            Write-CloudOSLog $Session "Preservando pid=$($record.pid) component=$($record.component) reason=$($check.reason)." 'WARN'
            $preserved.Add([ordered]@{component=$record.component;pid=[int]$record.pid;reason=$check.reason})
            continue
        }
        $process=Get-Process -Id ([int]$record.pid) -ErrorAction SilentlyContinue
        if(-not $process){
            $stopped.Add([ordered]@{component=$record.component;pid=[int]$record.pid;result='already-exited';method='none'})
            continue
        }
        Write-CloudOSLog $Session "Teardown ownership confirmado component=$($record.component) pid=$($record.pid) manifest=$($ownership.path)."
        $gracefulTimeout=if([string]$record.component -eq 'host-runtime'){12000}else{5000}
        $graceful=Invoke-CloudOSGracefulStop -Session $Session -Record $record -Process $process -TimeoutMilliseconds $gracefulTimeout
        if($graceful.exited){
            $stopped.Add([ordered]@{component=$record.component;pid=[int]$record.pid;result='stopped';method=$graceful.method})
            continue
        }

        $recheck=Test-CloudOSProcessOwnership $Session $record
        if(-not $recheck.running){
            $stopped.Add([ordered]@{component=$record.component;pid=[int]$record.pid;result='stopped-after-grace-period';method=$graceful.method})
            continue
        }
        if(-not $recheck.owned){
            Write-CloudOSLog $Session "Fallback forçado recusado para pid=$($record.pid): ownership mudou ($($recheck.reason))." 'WARN'
            $preserved.Add([ordered]@{component=$record.component;pid=[int]$record.pid;reason="force-refused:$($recheck.reason)"})
            continue
        }
        try{
            Stop-Process -Id ([int]$record.pid) -Force -ErrorAction Stop
            $afterForce=Get-Process -Id ([int]$record.pid) -ErrorAction SilentlyContinue
            if($afterForce){
                try{[void]$afterForce.WaitForExit(3000)}catch{}
            }
            $final=Test-CloudOSProcessOwnership $Session $record
            if($final.running -and $final.owned){throw 'OWNED_PROCESS_DID_NOT_EXIT'}
            $stopped.Add([ordered]@{component=$record.component;pid=[int]$record.pid;result='stopped';method='forced-after-ownership-recheck'})
        }catch{
            $failure=[ordered]@{component=$record.component;pid=[int]$record.pid;error=$_.Exception.Message}
            $failures.Add($failure)
            Write-CloudOSLog $Session "SESSION_TEARDOWN_FAILED component=$($record.component) pid=$($record.pid): $($_.Exception.Message)" 'ERROR'
        }
    }

    $result=[pscustomobject][ordered]@{
        status=if($failures.Count -eq 0){'completed'}else{'failed'}
        stoppedProcesses=@($stopped)
        preservedProcesses=@($preserved)
        failures=@($failures)
        finishedAt=(Get-Date).ToUniversalTime().ToString('o')
    }
    Set-CloudOSObjectProperty $Session 'teardownResult' $result
    Set-CloudOSObjectProperty $Session 'stoppedProcesses' @($stopped)
    Set-CloudOSObjectProperty $Session 'preservedProcesses' @($preserved)
    Set-CloudOSObjectProperty $Session 'failures' @($failures)
    Write-CloudOSJsonAtomic (Join-Path $Session.logDirectory 'teardown-result.json') $result
    Write-CloudOSJsonAtomic (Join-Path $Session.logDirectory 'manifest.json') $Session
    Write-CloudOSJsonAtomic $script:SessionStateFile $Session
    return $result
}

function Complete-CloudOSSession {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Status,
        [string]$ErrorCode='',
        [string]$Message='',
        $TeardownResult=$null,
        [bool]$PersistCurrentState=$true,
        [bool]$SkipProcessSnapshot=$false
    )
    Set-CloudOSObjectProperty $Session 'status' $Status
    Set-CloudOSObjectProperty $Session 'finishedAt' ((Get-Date).ToUniversalTime().ToString('o'))
    if($TeardownResult){
        Set-CloudOSObjectProperty $Session 'teardownResult' $TeardownResult
        Set-CloudOSObjectProperty $Session 'stoppedProcesses' @($TeardownResult.stoppedProcesses)
        Set-CloudOSObjectProperty $Session 'preservedProcesses' @($TeardownResult.preservedProcesses)
        Set-CloudOSObjectProperty $Session 'failures' @($TeardownResult.failures)
    }else{
        if(-not ($Session.PSObject.Properties.Name -contains 'teardownResult')){Set-CloudOSObjectProperty $Session 'teardownResult' $null}
        if(-not ($Session.PSObject.Properties.Name -contains 'stoppedProcesses')){Set-CloudOSObjectProperty $Session 'stoppedProcesses' @()}
        if(-not ($Session.PSObject.Properties.Name -contains 'preservedProcesses')){Set-CloudOSObjectProperty $Session 'preservedProcesses' @()}
        if(-not ($Session.PSObject.Properties.Name -contains 'failures')){Set-CloudOSObjectProperty $Session 'failures' @()}
    }
    if(-not $SkipProcessSnapshot){Save-CloudOSProcessSnapshot $Session 'after'}
    $result=[ordered]@{
        schemaVersion=2
        id=$Session.id
        mode=$Session.mode
        status=$Status
        errorCode=$ErrorCode
        message=$Message
        logDirectory=$Session.logDirectory
        git=$Session.git
        finishedAt=$Session.finishedAt
        teardownResult=$Session.teardownResult
        stoppedProcesses=@($Session.stoppedProcesses)
        preservedProcesses=@($Session.preservedProcesses)
        failures=@($Session.failures)
    }
    Write-CloudOSJsonAtomic (Join-Path $Session.logDirectory 'result.json') $result
    Write-CloudOSJsonAtomic (Join-Path $Session.logDirectory 'manifest.json') $Session
    if($PersistCurrentState){Write-CloudOSJsonAtomic $script:SessionStateFile $Session}
    return [pscustomobject]$result
}

function Read-CloudOSCurrentSession {
    if (-not (Test-Path $script:SessionStateFile)) { return $null }
    try { return Get-Content -LiteralPath $script:SessionStateFile -Raw | ConvertFrom-Json } catch { return $null }
}
