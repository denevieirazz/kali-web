[CmdletBinding()]
param(
    [ValidateSet('Full','WebOnly','Developer','UXValidation','FilesValidation','BrowserValidation','TerminalValidation')]
    [string]$Mode='Full',
    [switch]$NoOpen
)

. (Join-Path $PSScriptRoot 'cloudos-launcher-common.ps1')
. (Join-Path $PSScriptRoot 'cloudos-owned-processes.ps1')
. (Join-Path $PSScriptRoot '..\validate\cloudos-node-dependencies.ps1')

$script:FullLaunchStepCount = 11
$script:CurrentLaunchStep = 0
$script:CurrentLaunchPercent = 0
$script:CurrentLaunchStage = 'starting'
$script:CurrentLaunchMessage = 'Preparando o launcher.'
$script:CurrentLaunchTimeoutSeconds = 0
$script:CurrentLaunchLogPath = ''
$script:CurrentLaunchStageStartedAt = [DateTime]::UtcNow

function Get-CloudOSFileUri {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try { return ([Uri]([IO.Path]::GetFullPath($Path))).AbsoluteUri }
    catch { return $null }
}

function Write-CloudOSLaunchProgressRecord {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][ValidateSet('running','completed','failed')][string]$Status,
        [AllowNull()][string]$ErrorCode=$null
    )
    $elapsed = [Math]::Max(0,[int]([DateTime]::UtcNow - $script:CurrentLaunchStageStartedAt).TotalSeconds)
    $record = [ordered]@{
        schemaVersion = 1
        status = $Status
        mode = [string]$Session.mode
        step = $script:CurrentLaunchStep
        totalSteps = $script:FullLaunchStepCount
        percent = $script:CurrentLaunchPercent
        stage = $script:CurrentLaunchStage
        message = $script:CurrentLaunchMessage
        stageStartedAt = $script:CurrentLaunchStageStartedAt.ToString('o')
        stageElapsedSeconds = $elapsed
        timeoutSeconds = $script:CurrentLaunchTimeoutSeconds
        logPath = $(if($script:CurrentLaunchLogPath){[string]$script:CurrentLaunchLogPath}else{$null})
        logUri = $(Get-CloudOSFileUri $script:CurrentLaunchLogPath)
        sessionLogDirectory = [string]$Session.logDirectory
        sessionLogUri = $(Get-CloudOSFileUri $Session.logDirectory)
        errorCode = $ErrorCode
        updatedAt = [DateTime]::UtcNow.ToString('o')
    }
    Write-CloudOSJsonAtomic (Join-Path $Session.logDirectory 'launch-progress.json') $record
    return $record
}

function Write-CloudOSLaunchStage {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][int]$Step,
        [Parameter(Mandatory)][int]$Percent,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$Message,
        [int]$TimeoutSeconds=0,
        [AllowNull()][string]$LogPath=$null
    )
    $script:CurrentLaunchStep = $Step
    $script:CurrentLaunchPercent = $Percent
    $script:CurrentLaunchStage = $Stage
    $script:CurrentLaunchMessage = $Message
    $script:CurrentLaunchTimeoutSeconds = $TimeoutSeconds
    $script:CurrentLaunchLogPath = if($LogPath){$LogPath}else{Join-Path $Session.logDirectory 'launcher.log'}
    $script:CurrentLaunchStageStartedAt = [DateTime]::UtcNow
    [void](Write-CloudOSLaunchProgressRecord -Session $Session -Status 'running')
    $timeoutText = if($TimeoutSeconds -gt 0){" timeout=${TimeoutSeconds}s"}else{''}
    Write-CloudOSLog $Session "[Full $Step/$($script:FullLaunchStepCount) ${Percent}%] $Message$timeoutText"
    $uri = Get-CloudOSFileUri $script:CurrentLaunchLogPath
    if($uri){ Write-Host "  Log: $uri" }
}

function Write-CloudOSLaunchHeartbeat {
    param([Parameter(Mandatory)]$Session,[AllowNull()][string]$Detail=$null)
    $record = Write-CloudOSLaunchProgressRecord -Session $Session -Status 'running'
    $remainingText = ''
    if($script:CurrentLaunchTimeoutSeconds -gt 0){
        $remaining = [Math]::Max(0,$script:CurrentLaunchTimeoutSeconds - [int]$record.stageElapsedSeconds)
        $remainingText = " timeoutRestante=${remaining}s"
    }
    $detailText = if($Detail){" $Detail"}else{''}
    Write-CloudOSLog $Session "[$($script:CurrentLaunchStage)] em andamento elapsed=$($record.stageElapsedSeconds)s$remainingText.$detailText"
}

function ConvertTo-CloudOSPowerShellLiteral {
    param([AllowNull()][string]$Value)
    if($null -eq $Value){ return "''" }
    return "'" + $Value.Replace("'","''") + "'"
}

function Flush-CloudOSVisibleProcessLog {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BootstrapLog,
        [Parameter(Mandatory)][int]$Seen,
        [switch]$ErrorStream
    )
    if(-not(Test-Path -LiteralPath $Path)){ return $Seen }
    $lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    if($lines.Count -le $Seen){ return $lines.Count }
    for($index=$Seen; $index -lt $lines.Count; $index++){
        $line = [string]$lines[$index]
        $stream = if($ErrorStream){'stderr'}else{'stdout'}
        $formatted = "$(Get-Date -Format o) [$Component][$stream] $line"
        Add-Content -LiteralPath $BootstrapLog -Value $formatted -Encoding UTF8
        if($line){ Write-Host "  [$Component] $line" }
    }
    return $lines.Count
}

function Invoke-CloudOSVisibleProcess {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments=@(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$PwshPath,
        [Parameter(Mandatory)][string]$BootstrapLog,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][string]$TimeoutCode,
        [Parameter(Mandatory)][string]$FailureCode
    )
    $safeName = $Name -replace '[^A-Za-z0-9_.-]','_'
    $stdoutPath = Join-Path $Session.logDirectory "$safeName.stdout.log"
    $stderrPath = Join-Path $Session.logDirectory "$safeName.stderr.log"
    $runnerPath = Join-Path $Session.runtimeDirectory "$safeName.runner.ps1"
    foreach($path in @($stdoutPath,$stderrPath)){ New-Item -ItemType File -Force -Path $path | Out-Null }

    $argumentLiterals = @($Arguments | ForEach-Object { ConvertTo-CloudOSPowerShellLiteral ([string]$_) })
    $runnerContent = @"
`$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $(ConvertTo-CloudOSPowerShellLiteral $WorkingDirectory)
`$executable = $(ConvertTo-CloudOSPowerShellLiteral $FilePath)
`$arguments = @($($argumentLiterals -join ', '))
& `$executable @arguments
`$code = if (`$null -eq `$LASTEXITCODE) { 0 } else { [int]`$LASTEXITCODE }
exit `$code
"@
    Set-Content -LiteralPath $runnerPath -Value $runnerContent -Encoding UTF8

    $quotedRunner = '"' + $runnerPath + '"'
    $process = Start-Process -FilePath $PwshPath -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$quotedRunner) -WorkingDirectory $WorkingDirectory -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $started = [DateTime]::UtcNow
    $deadline = $started.AddSeconds($TimeoutSeconds)
    $nextHeartbeat = $started.AddSeconds(5)
    $stdoutSeen = 0
    $stderrSeen = 0
    try {
        while(-not $process.HasExited){
            $stdoutSeen = Flush-CloudOSVisibleProcessLog -Session $Session -Component $Name -Path $stdoutPath -BootstrapLog $BootstrapLog -Seen $stdoutSeen
            $stderrSeen = Flush-CloudOSVisibleProcessLog -Session $Session -Component $Name -Path $stderrPath -BootstrapLog $BootstrapLog -Seen $stderrSeen -ErrorStream
            $now = [DateTime]::UtcNow
            if($now -ge $deadline){
                try{$process.Kill($true)}catch{}
                try{$process.WaitForExit(5000)}catch{}
                $stdoutSeen = Flush-CloudOSVisibleProcessLog -Session $Session -Component $Name -Path $stdoutPath -BootstrapLog $BootstrapLog -Seen $stdoutSeen
                $stderrSeen = Flush-CloudOSVisibleProcessLog -Session $Session -Component $Name -Path $stderrPath -BootstrapLog $BootstrapLog -Seen $stderrSeen -ErrorStream
                throw "${TimeoutCode}:timeout=${TimeoutSeconds}:log=$BootstrapLog"
            }
            if($now -ge $nextHeartbeat){
                Write-CloudOSLaunchHeartbeat -Session $Session -Detail "processo=$Name pid=$($process.Id)"
                $nextHeartbeat = $now.AddSeconds(5)
            }
            Start-Sleep -Milliseconds 200
            $process.Refresh()
        }
        $process.WaitForExit()
        $stdoutSeen = Flush-CloudOSVisibleProcessLog -Session $Session -Component $Name -Path $stdoutPath -BootstrapLog $BootstrapLog -Seen $stdoutSeen
        $stderrSeen = Flush-CloudOSVisibleProcessLog -Session $Session -Component $Name -Path $stderrPath -BootstrapLog $BootstrapLog -Seen $stderrSeen -ErrorStream
        if($process.ExitCode -ne 0){ throw "${FailureCode}:exit=$($process.ExitCode):log=$BootstrapLog" }
        Write-CloudOSLog $Session "$Name concluído em $([int]([DateTime]::UtcNow - $started).TotalSeconds)s."
        return [pscustomobject][ordered]@{exitCode=$process.ExitCode;stdout=$stdoutPath;stderr=$stderrPath;elapsedSeconds=[int](([DateTime]::UtcNow-$started).TotalSeconds)}
    } finally {
        $process.Dispose()
    }
}

function Get-NativeHostRuntimeLogPath {
    if(-not $env:LOCALAPPDATA){ return $null }
    return Join-Path $env:LOCALAPPDATA "CloudOS\logs\host-$([DateTime]::UtcNow.ToString('yyyyMMdd')).log"
}

function Wait-NativeHostWindow {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][System.Diagnostics.Process]$HostRuntime,
        [int]$TimeoutSeconds=45
    )
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $nextHeartbeat=[DateTime]::UtcNow.AddSeconds(5)
    while([DateTime]::UtcNow -lt $deadline){
        Assert-CloudOSProcessAlive $Session $HostRuntime 'host-runtime'
        $HostRuntime.Refresh()
        if($HostRuntime.MainWindowHandle -ne [IntPtr]::Zero){return $HostRuntime}
        if([DateTime]::UtcNow -ge $nextHeartbeat){
            Write-CloudOSLaunchHeartbeat -Session $Session -Detail "hostPid=$($HostRuntime.Id) aguardando janela nativa"
            $nextHeartbeat=[DateTime]::UtcNow.AddSeconds(5)
        }
        Start-Sleep -Milliseconds 150
    }
    throw "HOST_UI_READINESS_TIMEOUT:hostPid=$($HostRuntime.Id):log=$($Session.logDirectory)"
}

function Wait-NativeHostBackendRuntime {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][System.Diagnostics.Process]$HostRuntime,
        [int]$TimeoutSeconds=45
    )
    $runtimeRoot=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'CloudOS\runtime'
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $nextHeartbeat=[DateTime]::UtcNow.AddSeconds(5)
    while([DateTime]::UtcNow -lt $deadline){
        Assert-CloudOSProcessAlive $Session $HostRuntime 'host-runtime'
        if(Test-Path -LiteralPath $runtimeRoot){
            foreach($file in @(Get-ChildItem -LiteralPath $runtimeRoot -Filter 'backend-port.json' -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)){
                try{
                    $runtime=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                    if([int]$runtime.parentPid -eq $HostRuntime.Id -and $runtime.nativeHost -eq $true){
                        return [pscustomobject][ordered]@{path=$file.FullName;manifest=$runtime}
                    }
                }catch{}
            }
        }
        if([DateTime]::UtcNow -ge $nextHeartbeat){
            Write-CloudOSLaunchHeartbeat -Session $Session -Detail "hostPid=$($HostRuntime.Id) aguardando manifesto do backend"
            $nextHeartbeat=[DateTime]::UtcNow.AddSeconds(5)
        }
        Start-Sleep -Milliseconds 150
    }
    throw "NATIVE_HOST_BACKEND_READINESS_TIMEOUT:hostPid=$($HostRuntime.Id):runtimeRoot=$runtimeRoot"
}

function Wait-CloudOSHttpReadyVisible {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][string]$Uri,
        [int]$TimeoutSeconds=20
    )
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $nextHeartbeat=[DateTime]::UtcNow.AddSeconds(5)
    $lastError=''
    while([DateTime]::UtcNow -lt $deadline){
        Assert-CloudOSProcessAlive $Session $Process $Component
        try{
            $response=Invoke-WebRequest -Uri $Uri -Method Get -TimeoutSec 2 -SkipHttpErrorCheck
            if([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 400){return $response}
            $lastError="HTTP $([int]$response.StatusCode)"
        }catch{$lastError=$_.Exception.Message}
        if([DateTime]::UtcNow -ge $nextHeartbeat){
            Write-CloudOSLaunchHeartbeat -Session $Session -Detail "componente=$Component aguardando health"
            $nextHeartbeat=[DateTime]::UtcNow.AddSeconds(5)
        }
        Start-Sleep -Milliseconds 200
    }
    throw "HTTP_READINESS_TIMEOUT component=$Component uri=$Uri error=$(ConvertTo-CloudOSSanitizedCommandLine $lastError)"
}

function New-NativeHostBootstrapPipe {
    param([Parameter(Mandatory)]$Session)
    $pipeName = "cloudos-launch-$($Session.id)-$([guid]::NewGuid().ToString('N').Substring(0,10))"
    $server = [System.IO.Pipes.NamedPipeServerStream]::new(
        $pipeName,
        [System.IO.Pipes.PipeDirection]::In,
        1,
        [System.IO.Pipes.PipeTransmissionMode]::Byte,
        [System.IO.Pipes.PipeOptions]::Asynchronous)
    return [pscustomobject][ordered]@{name=$pipeName;server=$server}
}

function Wait-NativeHostShellReady {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][System.Diagnostics.Process]$HostRuntime,
        [Parameter(Mandatory)][System.IO.Pipes.NamedPipeServerStream]$Pipe,
        [int]$TimeoutSeconds=60
    )
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $nextHeartbeat=[DateTime]::UtcNow.AddSeconds(5)
    $connectTask=$Pipe.WaitForConnectionAsync()
    while(-not $connectTask.IsCompleted){
        Assert-CloudOSProcessAlive $Session $HostRuntime 'host-runtime'
        $now=[DateTime]::UtcNow
        if($now -ge $deadline){ throw "NATIVE_HOST_SHELL_READINESS_TIMEOUT:phase=connect:hostPid=$($HostRuntime.Id):log=$($Session.logDirectory)" }
        if($now -ge $nextHeartbeat){
            Write-CloudOSLaunchHeartbeat -Session $Session -Detail "hostPid=$($HostRuntime.Id) aguardando WebView2 + bridge.handshake"
            $nextHeartbeat=$now.AddSeconds(5)
        }
        Start-Sleep -Milliseconds 150
    }
    $connectTask.GetAwaiter().GetResult()

    $reader=[System.IO.StreamReader]::new($Pipe,[Text.Encoding]::UTF8,$true,1024,$true)
    try{
        $readTask=$reader.ReadToEndAsync()
        $readDeadline=[DateTime]::UtcNow.AddSeconds(5)
        while(-not $readTask.IsCompleted){
            Assert-CloudOSProcessAlive $Session $HostRuntime 'host-runtime'
            if([DateTime]::UtcNow -ge $readDeadline){ throw "NATIVE_HOST_SHELL_READINESS_TIMEOUT:phase=payload:hostPid=$($HostRuntime.Id):log=$($Session.logDirectory)" }
            Start-Sleep -Milliseconds 100
        }
        $payload=$readTask.GetAwaiter().GetResult()
    }finally{$reader.Dispose()}

    try{$ready=$payload | ConvertFrom-Json}catch{throw "NATIVE_HOST_SHELL_READINESS_INVALID_JSON:hostPid=$($HostRuntime.Id)"}
    if([int]$ready.protocol -ne 1 -or [string]$ready.event -ne 'ready' -or [int]$ready.pid -ne $HostRuntime.Id){
        throw "NATIVE_HOST_SHELL_READINESS_INVALID_PAYLOAD:hostPid=$($HostRuntime.Id)"
    }
    return $ready
}

function Get-CloudOSFriendlyLaunchFailure {
    param([Parameter(Mandatory)][string]$Message)
    switch -Regex ($Message) {
        '^FRONTEND_BUILD_TIMEOUT' { return 'O build do frontend excedeu o tempo limite. Consulte bootstrap.log e frontend-build.stderr.log.' }
        '^FRONTEND_BUILD_FAILED' { return 'O frontend não compilou. Consulte bootstrap.log e frontend-build.stderr.log.' }
        '^HOST_RESTORE_TIMEOUT' { return 'O restore do Host nativo excedeu o tempo limite. Verifique rede/NuGet e host-restore.stderr.log.' }
        '^HOST_RESTORE_FAILED' { return 'O restore do Host nativo falhou. Consulte host-restore.stderr.log.' }
        '^HOST_BUILD_TIMEOUT' { return 'O build do Host nativo excedeu o tempo limite. Consulte host-build.stderr.log.' }
        '^HOST_BUILD_FAILED' { return 'O Host nativo não compilou. Consulte host-build.stderr.log.' }
        '^HOST_UI_READINESS_TIMEOUT' { return 'O processo Host iniciou, mas a janela nativa não apareceu dentro do tempo limite.' }
        '^NATIVE_HOST_BACKEND_READINESS_TIMEOUT' { return 'A janela do Host abriu, mas o backend supervisionado não publicou seu manifesto a tempo.' }
        '^HTTP_READINESS_TIMEOUT' { return 'O backend foi iniciado, mas não respondeu saudável dentro do tempo limite.' }
        '^NATIVE_HOST_SHELL_READINESS_TIMEOUT' { return 'Host e backend iniciaram, mas o WebView2/shell não concluiu o handshake dentro do tempo limite.' }
        '^WEBVIEW2_RUNTIME_NOT_DETECTED' { return 'O Microsoft Edge WebView2 Runtime não foi detectado.' }
        default { return 'O CloudOS não conseguiu concluir a inicialização. O código técnico e os logs indicam a etapa exata.' }
    }
}

$existingSession = Read-CloudOSCurrentSession
if ($existingSession -and $existingSession.status -eq 'running') {
    $healthy = $false
    $hostPid = 0
    if ($existingSession.readiness -and $existingSession.readiness.hostRuntimePid) {
        $hostPid = [int]$existingSession.readiness.hostRuntimePid
    }
    if ($hostPid -gt 0) {
        $hostRecord = @($existingSession.processes | Where-Object { [int]$_.pid -eq $hostPid -and [string]$_.component -eq 'host-runtime' }) | Select-Object -First 1
        if ($hostRecord) {
            $ownership = Test-CloudOSProcessOwnership $existingSession $hostRecord
            if ($ownership.owned -and $ownership.running) {
                $apiBase = [string]$existingSession.readiness.backendApiBase
                if ($apiBase) {
                    try {
                        $res = Invoke-WebRequest -Uri "$apiBase/api/health" -TimeoutSec 2 -SkipHttpErrorCheck -ErrorAction Stop
                        if ([int]$res.StatusCode -ge 200 -and [int]$res.StatusCode -lt 400) {
                            $healthy = $true
                        }
                    } catch {}
                }
            }
        }
    }

    if ($healthy) {
        Write-Host "CloudOS já está em execução (sessão $($existingSession.id)). Ativando janela existente..."
        $hostExe = Join-Path $script:CloudOSRoot 'desktop\CloudOS.Host\bin\Release\net8.0-windows10.0.19041.0\CloudOS.Host.exe'
        if (Test-Path -LiteralPath $hostExe) {
            try {
                $signalProc = Start-Process -FilePath $hostExe -ArgumentList @('--root', $script:CloudOSRoot) -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
                if ($signalProc) { [void]$signalProc.WaitForExit(5000) }
            } catch {}
        }
        $launchResult = [pscustomobject][ordered]@{
            schemaVersion = 2
            status = 'already_running'
            sessionId = [string]$existingSession.id
            mode = [string]$existingSession.mode
            manifest = (Join-Path $existingSession.logDirectory 'manifest.json')
            logDirectory = [string]$existingSession.logDirectory
            readiness = $existingSession.readiness
            launcherPid = $PID
            returnedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
        Write-Output ($launchResult | ConvertTo-Json -Depth 8 -Compress)
        exit 0
    } else {
        try {
            [void](Stop-CloudOSRecordedProcesses $existingSession)
        } catch {}
    }
}

$session = New-CloudOSSession -Mode $Mode
Save-CloudOSProcessSnapshot $session 'before'

try {
    Write-CloudOSLog $session "CloudOS Stabilization Batch 1 iniciando em modo $Mode."

    if($Mode -in @('Full','BrowserValidation')){
        Write-CloudOSLaunchStage -Session $session -Step 1 -Percent 5 -Stage 'prerequisites' -Message 'Validando Node, npm, .NET, PowerShell 7 e WebView2.' -LogPath (Join-Path $session.logDirectory 'launcher.log')
    }

    $pwshResolution = Resolve-CloudOSPowerShell7
    $pwshDirectory = Split-Path -Parent ([string]$pwshResolution.path)
    $pathEntries = @([string]$env:PATH -split [IO.Path]::PathSeparator)
    if ($pwshDirectory -and ($pathEntries -notcontains $pwshDirectory)) {
        $env:PATH = "$pwshDirectory$([IO.Path]::PathSeparator)$env:PATH"
    }

    $pre = Test-CloudOSPrerequisites $session
    $dependencyEvidence = Join-Path $session.logDirectory 'dependencies'
    if($Mode -in @('Full','BrowserValidation')){
        Write-CloudOSLaunchStage -Session $session -Step 2 -Percent 12 -Stage 'node-dependencies' -Message 'Verificando dependências Node do workspace.' -LogPath $dependencyEvidence
    }
    $dependencyState = Ensure-CloudOSNodeDependencies -Root $script:CloudOSRoot -EvidenceDirectory $dependencyEvidence -AllowInstall
    Write-CloudOSLog $session "Dependencias Node verificadas strategy=root-workspaces-single-install installPerformed=$($dependencyState.installPerformed)."

    $env:CLOUDOS_LAUNCH_MODE = $Mode
    $env:CLOUDOS_RUNTIME_DIR = $session.runtimeDirectory
    $env:CLOUDOS_DATA_DIR = $session.dataDirectory
    $env:CLOUDOS_NATIVE_HOST = if ($Mode -in @('Full','BrowserValidation')) { '1' } else { '0' }
    $env:CLOUDOS_SESSION_ID = [string]$session.id
    $env:CLOUDOS_SESSION_LOG_DIR = [string]$session.logDirectory
    if ($Mode -in @('UXValidation','FilesValidation','BrowserValidation','TerminalValidation')) { $env:NODE_ENV = 'test' }

    if ($Mode -eq 'FilesValidation') {
        $env:CLOUDOS_WSL_CORE_FOUNDATION='1'
        $env:CLOUDOS_WSL_CORE_FILES='1'
        $env:CLOUDOS_WSL_CORE_TERMINAL='0'
        $env:CLOUDOS_WSL_DISTRO=[string]$pre.wslDistro
    } elseif ($Mode -eq 'TerminalValidation') {
        $env:CLOUDOS_WSL_CORE_FOUNDATION='1'
        $env:CLOUDOS_WSL_CORE_TERMINAL='1'
        $env:CLOUDOS_WSL_CORE_FILES='0'
        $env:CLOUDOS_WSL_DISTRO=[string]$pre.wslDistro
    } else {
        $env:CLOUDOS_WSL_CORE_FILES='0'
        if ($Mode -in @('WebOnly','UXValidation','BrowserValidation')) { $env:CLOUDOS_WSL_CORE_TERMINAL='0' }
    }

    $readiness=$null
    if ($Mode -in @('Full','BrowserValidation')) {
        $bootstrapLog=Join-Path $session.logDirectory 'bootstrap.log'
        $hostProject=Join-Path $script:CloudOSRoot 'desktop\CloudOS.Host\CloudOS.Host.csproj'

        Write-CloudOSLaunchStage -Session $session -Step 3 -Percent 22 -Stage 'frontend-build' -Message 'Compilando o frontend de produção.' -TimeoutSeconds 300 -LogPath $bootstrapLog
        [void](Invoke-CloudOSVisibleProcess -Session $session -Name 'frontend-build' -FilePath $pre.npm -Arguments @('--prefix','frontend','run','build') -WorkingDirectory $script:CloudOSRoot -PwshPath $pre.pwsh -BootstrapLog $bootstrapLog -TimeoutSeconds 300 -TimeoutCode 'FRONTEND_BUILD_TIMEOUT' -FailureCode 'FRONTEND_BUILD_FAILED')

        Write-CloudOSLaunchStage -Session $session -Step 4 -Percent 36 -Stage 'host-restore' -Message 'Restaurando dependências .NET do Host nativo.' -TimeoutSeconds 300 -LogPath $bootstrapLog
        [void](Invoke-CloudOSVisibleProcess -Session $session -Name 'host-restore' -FilePath $pre.dotnet -Arguments @('restore',$hostProject,'--nologo') -WorkingDirectory $script:CloudOSRoot -PwshPath $pre.pwsh -BootstrapLog $bootstrapLog -TimeoutSeconds 300 -TimeoutCode 'HOST_RESTORE_TIMEOUT' -FailureCode 'HOST_RESTORE_FAILED')

        Write-CloudOSLaunchStage -Session $session -Step 5 -Percent 50 -Stage 'host-build' -Message 'Compilando o Host nativo sem novo restore.' -TimeoutSeconds 300 -LogPath $bootstrapLog
        [void](Invoke-CloudOSVisibleProcess -Session $session -Name 'host-build' -FilePath $pre.dotnet -Arguments @('build',$hostProject,'-c','Release','--no-restore','--nologo','--verbosity','minimal') -WorkingDirectory $script:CloudOSRoot -PwshPath $pre.pwsh -BootstrapLog $bootstrapLog -TimeoutSeconds 300 -TimeoutCode 'HOST_BUILD_TIMEOUT' -FailureCode 'HOST_BUILD_FAILED')

        $hostExe=Join-Path $script:CloudOSRoot 'desktop\CloudOS.Host\bin\Release\net8.0-windows10.0.19041.0\CloudOS.Host.exe'
        if(-not(Test-Path -LiteralPath $hostExe -PathType Leaf)){throw "HOST_EXECUTABLE_MISSING_AFTER_BUILD:$hostExe"}
        $hostOut = Join-Path $session.logDirectory 'host.log'
        $hostErr = Join-Path $session.logDirectory 'host.stderr.log'
        $hostRuntimeLog = Get-NativeHostRuntimeLogPath
        $bootstrapPipe = New-NativeHostBootstrapPipe -Session $session
        try{
            Write-CloudOSLaunchStage -Session $session -Step 6 -Percent 60 -Stage 'host-start' -Message 'Iniciando o processo Host nativo.' -TimeoutSeconds 15 -LogPath $hostErr
            $hostArgs = @('--root',$script:CloudOSRoot,'--bootstrap-pipe',$bootstrapPipe.name)
            if ($Mode -eq 'BrowserValidation') { $hostArgs += '--developer-mode' }
            $hostRuntime = Start-CloudOSLoggedProcess $session 'host-runtime' $hostExe $hostArgs $hostOut $hostErr @{
                CLOUDOS_LAUNCH_MODE=$Mode
                CLOUDOS_RUNTIME_DIR=$session.runtimeDirectory
                CLOUDOS_DATA_DIR=$session.dataDirectory
                CLOUDOS_SESSION_ID=$session.id
                CLOUDOS_SESSION_LOG_DIR=$session.logDirectory
            }

            Write-CloudOSLaunchStage -Session $session -Step 7 -Percent 68 -Stage 'host-window' -Message 'Aguardando a janela nativa do Host.' -TimeoutSeconds 45 -LogPath $hostErr
            [void](Wait-NativeHostWindow -Session $session -HostRuntime $hostRuntime -TimeoutSeconds 45)

            Write-CloudOSLaunchStage -Session $session -Step 8 -Percent 76 -Stage 'host-backend' -Message 'Aguardando o backend supervisionado pelo Host.' -TimeoutSeconds 45 -LogPath $(if($hostRuntimeLog){$hostRuntimeLog}else{$hostErr})
            $nativeRuntime=Wait-NativeHostBackendRuntime -Session $session -HostRuntime $hostRuntime -TimeoutSeconds 45
            $backendPid=[int]$nativeRuntime.manifest.pid
            $backendProcess=Get-Process -Id $backendPid -ErrorAction SilentlyContinue
            if(-not $backendProcess){throw "NATIVE_HOST_BACKEND_EXITED_BEFORE_READINESS:pid=$backendPid"}
            [void](Add-CloudOSProcessRecord -Session $session -Process $backendProcess -Component 'backend-hosted')
            $apiBase=[string]$nativeRuntime.manifest.apiBase

            Write-CloudOSLaunchStage -Session $session -Step 9 -Percent 84 -Stage 'backend-health' -Message 'Confirmando a saúde HTTP do backend.' -TimeoutSeconds 20 -LogPath $(if($hostRuntimeLog){$hostRuntimeLog}else{$hostErr})
            [void](Wait-CloudOSHttpReadyVisible -Session $session -Process $backendProcess -Component 'backend-hosted' -Uri "$apiBase/api/health" -TimeoutSeconds 20)

            Write-CloudOSLaunchStage -Session $session -Step 10 -Percent 92 -Stage 'webview-shell' -Message 'Aguardando WebView2 carregar o shell e concluir o bridge.handshake.' -TimeoutSeconds 60 -LogPath $(if($hostRuntimeLog){$hostRuntimeLog}else{$hostErr})
            $shellReady=Wait-NativeHostShellReady -Session $session -HostRuntime $hostRuntime -Pipe $bootstrapPipe.server -TimeoutSeconds 60

            $frontendIndex=Join-Path $script:CloudOSRoot 'frontend\dist\index.html'
            if(-not(Test-Path -LiteralPath $frontendIndex -PathType Leaf)){throw "FULL_FRONTEND_DIST_MISSING:$frontendIndex"}
            $readiness=[pscustomobject][ordered]@{
                status='ready'
                mode=$Mode
                readyAt=(Get-Date).ToUniversalTime().ToString('o')
                hostLauncherPid=$null
                hostRuntimePid=$hostRuntime.Id
                shellWindowReady=$true
                shellHandshakeReady=$true
                shellHandshakeProtocol=[int]$shellReady.protocol
                frontendIndex=$frontendIndex
                backendPid=$backendPid
                backendApiBase=$apiBase
                backendRuntimeManifest=$nativeRuntime.path
            }
            Add-Content -LiteralPath (Join-Path $session.logDirectory 'backend.stdout.log') -Value "Full mode backend supervised by CloudOS.Host; runtime pid=$backendPid api=$apiBase."
            Add-Content -LiteralPath (Join-Path $session.logDirectory 'frontend.stdout.log') -Value "Full mode frontend served from production build after WebView2 shell handshake readiness."
        }finally{
            if($bootstrapPipe -and $bootstrapPipe.server){$bootstrapPipe.server.Dispose()}
        }
    } else {
        $backend = Start-CloudOSLoggedProcess $session 'backend' $pre.node @('backend/src/server.js') (Join-Path $session.logDirectory 'backend.stdout.log') (Join-Path $session.logDirectory 'backend.stderr.log') @{
            CLOUDOS_LAUNCH_MODE=$Mode
            CLOUDOS_RUNTIME_DIR=$session.runtimeDirectory
            CLOUDOS_DATA_DIR=$session.dataDirectory
            CLOUDOS_NATIVE_HOST='0'
            PORT='0'
            HOST='127.0.0.1'
        }
        $backendManifest = Wait-CloudOSReadinessFile $session $backend 'backend' (Join-Path $session.runtimeDirectory 'backend-port.json') 25
        if([int]$backendManifest.pid -ne $backend.Id){throw "BACKEND_READINESS_PID_MISMATCH:expected=$($backend.Id):actual=$($backendManifest.pid)"}
        $backendApi=[string]$backendManifest.apiBase
        [void](Wait-CloudOSHttpReady -Session $session -Process $backend -Component 'backend' -Uri "$backendApi/api/health" -TimeoutSeconds 15)

        $env:VITE_CLOUDOS_API_BASE = $backendApi
        $frontend = Start-CloudOSLoggedProcess $session 'frontend' $pre.node @('frontend/scripts/dev-server.js') (Join-Path $session.logDirectory 'frontend.stdout.log') (Join-Path $session.logDirectory 'frontend.stderr.log') @{
            CLOUDOS_LAUNCH_MODE=$Mode
            CLOUDOS_RUNTIME_DIR=$session.runtimeDirectory
            CLOUDOS_NATIVE_HOST='0'
            VITE_CLOUDOS_API_BASE=$backendApi
        }
        $frontendManifest = Wait-CloudOSReadinessFile $session $frontend 'frontend' (Join-Path $session.runtimeDirectory 'frontend-port.json') 25
        if([int]$frontendManifest.pid -ne $frontend.Id){throw "FRONTEND_READINESS_PID_MISMATCH:expected=$($frontend.Id):actual=$($frontendManifest.pid)"}
        $url = "http://127.0.0.1:$($frontendManifest.port)"
        [void](Wait-CloudOSHttpReady -Session $session -Process $frontend -Component 'frontend' -Uri $url -TimeoutSeconds 15)
        Write-CloudOSLog $session "Frontend pronto e saudável: $url"
        $readiness=[pscustomobject][ordered]@{
            status='ready'
            mode=$Mode
            readyAt=(Get-Date).ToUniversalTime().ToString('o')
            backendPid=$backend.Id
            backendApiBase=$backendApi
            backendRuntimeManifest=(Join-Path $session.runtimeDirectory 'backend-port.json')
            frontendPid=$frontend.Id
            frontendUrl=$url
            frontendRuntimeManifest=(Join-Path $session.runtimeDirectory 'frontend-port.json')
        }
        if (-not $NoOpen -and $Mode -notin @('FilesValidation','TerminalValidation')) { Start-Process $url | Out-Null }
    }

    Set-CloudOSObjectProperty $session 'readiness' $readiness
    Set-CloudOSObjectProperty $session 'status' 'running'
    Write-CloudOSJsonAtomic (Join-Path $session.logDirectory 'manifest.json') $session
    Write-CloudOSJsonAtomic $script:SessionStateFile $session
    $launchResult=[pscustomobject][ordered]@{
        schemaVersion=2
        status='running'
        sessionId=[string]$session.id
        mode=$Mode
        manifest=(Join-Path $session.logDirectory 'manifest.json')
        logDirectory=[string]$session.logDirectory
        readiness=$readiness
        launcherPid=$PID
        returnedAt=(Get-Date).ToUniversalTime().ToString('o')
    }
    Write-CloudOSJsonAtomic (Join-Path $session.logDirectory 'launch-result.json') $launchResult
    if($Mode -in @('Full','BrowserValidation')){
        Write-CloudOSLaunchStage -Session $session -Step 11 -Percent 100 -Stage 'ready' -Message 'CloudOS Full pronto: Host, backend e WebView2/shell confirmados.' -LogPath (Join-Path $session.logDirectory 'launcher.log')
        $script:CurrentLaunchStageStartedAt=[DateTime]::UtcNow
        [void](Write-CloudOSLaunchProgressRecord -Session $session -Status 'completed')
    }
    Write-CloudOSLog $session "Sessão pronta; launcher retornará sem aguardar os serviços persistentes. Logs: $($session.logDirectory)"
    $sessionLogUri=Get-CloudOSFileUri $session.logDirectory
    if($sessionLogUri){Write-Host "Logs desta sessão: $sessionLogUri"}
    Write-Host "Para encerrar: .\Parar CloudOS.cmd"
    Write-Host "Para diagnosticar: .\Diagnosticar CloudOS.cmd"
    Write-Output ($launchResult | ConvertTo-Json -Depth 8 -Compress)
    $global:LASTEXITCODE=0
    exit 0
} catch {
    $message = $_.Exception.Message
    Write-CloudOSLog $session $message 'ERROR'
    if($Mode -in @('Full','BrowserValidation')){
        $script:CurrentLaunchMessage = Get-CloudOSFriendlyLaunchFailure $message
        [void](Write-CloudOSLaunchProgressRecord -Session $session -Status 'failed' -ErrorCode $message.Split(':')[0])
    }
    $teardown=$null
    try{$teardown=Stop-CloudOSRecordedProcesses $session}catch{Write-CloudOSLog $session "Teardown após falha também falhou: $($_.Exception.Message)" 'ERROR'}
    [void](Complete-CloudOSSession -Session $session -Status 'failed' -ErrorCode 'LAUNCH_FAILED' -Message $message -TeardownResult $teardown -PersistCurrentState:$true)
    Write-Host ''
    Write-Host 'CloudOS não iniciou.'
    if($Mode -in @('Full','BrowserValidation')){
        Write-Host "Etapa final: $($script:CurrentLaunchStage) ($($script:CurrentLaunchStep)/$($script:FullLaunchStepCount))."
        Write-Host "Mensagem: $(Get-CloudOSFriendlyLaunchFailure $message)"
    }
    Write-Host "Código técnico: $message"
    $sessionLogUri=Get-CloudOSFileUri $session.logDirectory
    if($sessionLogUri){Write-Host "Logs desta sessão: $sessionLogUri"}
    Write-Host "Abrir pasta de logs: explorer.exe `"$($session.logDirectory)`""
    exit 1
}
