[CmdletBinding()]
param(
    [ValidateSet('Full','WebOnly','Developer','UXValidation','FilesValidation','BrowserValidation','TerminalValidation')]
    [string]$Mode='Full',
    [switch]$NoOpen
)

. (Join-Path $PSScriptRoot 'cloudos-launcher-common.ps1')
. (Join-Path $PSScriptRoot 'cloudos-owned-processes.ps1')
. (Join-Path $PSScriptRoot '..\validate\cloudos-node-dependencies.ps1')

function Wait-NativeHostBackendRuntime {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][System.Diagnostics.Process]$HostRuntime,
        [int]$TimeoutSeconds=30
    )
    $runtimeRoot=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'CloudOS\runtime'
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
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
        Start-Sleep -Milliseconds 150
    }
    throw "NATIVE_HOST_BACKEND_READINESS_TIMEOUT:hostPid=$($HostRuntime.Id):runtimeRoot=$runtimeRoot"
}

$session = New-CloudOSSession -Mode $Mode
Save-CloudOSProcessSnapshot $session 'before'

try {
    Write-CloudOSLog $session "CloudOS Stabilization Batch 1 iniciando em modo $Mode."

    $pwshResolution = Resolve-CloudOSPowerShell7
    $pwshDirectory = Split-Path -Parent ([string]$pwshResolution.path)
    $pathEntries = @([string]$env:PATH -split [IO.Path]::PathSeparator)
    if ($pwshDirectory -and ($pathEntries -notcontains $pwshDirectory)) {
        $env:PATH = "$pwshDirectory$([IO.Path]::PathSeparator)$env:PATH"
    }

    $pre = Test-CloudOSPrerequisites $session
    $dependencyEvidence = Join-Path $session.logDirectory 'dependencies'
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
        Write-CloudOSLog $session 'Compilando frontend para o Host nativo.'
        Push-Location $script:CloudOSRoot
        try {
            & $pre.npm --prefix frontend run build *>> (Join-Path $session.logDirectory 'bootstrap.log')
            if ($LASTEXITCODE -ne 0) { throw "FRONTEND_BUILD_FAILED:${LASTEXITCODE}:log=$(Join-Path $session.logDirectory 'bootstrap.log')" }
        } finally { Pop-Location }

        $hostOut = Join-Path $session.logDirectory 'host.log'
        $hostErr = Join-Path $session.logDirectory 'host.stderr.log'
        $hostScript = Join-Path $script:CloudOSRoot 'scripts\run-native-host.ps1'
        $hostArgs = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$hostScript)
        if ($Mode -eq 'BrowserValidation') { $hostArgs += '-DeveloperMode' }
        $host = Start-CloudOSLoggedProcess $session 'host' $pre.pwsh $hostArgs $hostOut $hostErr @{
            CLOUDOS_LAUNCH_MODE=$Mode
            CLOUDOS_RUNTIME_DIR=$session.runtimeDirectory
            CLOUDOS_DATA_DIR=$session.dataDirectory
            CLOUDOS_SESSION_ID=$session.id
            CLOUDOS_SESSION_LOG_DIR=$session.logDirectory
        }
        $hostRuntime=Wait-CloudOSHostRuntime -Session $session -HostLauncher $host -TimeoutSeconds 45
        $nativeRuntime=Wait-NativeHostBackendRuntime -Session $session -HostRuntime $hostRuntime -TimeoutSeconds 30
        $backendPid=[int]$nativeRuntime.manifest.pid
        $backendProcess=Get-Process -Id $backendPid -ErrorAction SilentlyContinue
        if(-not $backendProcess){throw "NATIVE_HOST_BACKEND_EXITED_BEFORE_READINESS:pid=$backendPid"}
        [void](Add-CloudOSProcessRecord -Session $session -Process $backendProcess -Component 'backend-hosted')
        $apiBase=[string]$nativeRuntime.manifest.apiBase
        [void](Wait-CloudOSHttpReady -Session $session -Process $backendProcess -Component 'backend-hosted' -Uri "$apiBase/api/health" -TimeoutSeconds 15)
        $frontendIndex=Join-Path $script:CloudOSRoot 'frontend\dist\index.html'
        if(-not(Test-Path -LiteralPath $frontendIndex -PathType Leaf)){throw "FULL_FRONTEND_DIST_MISSING:$frontendIndex"}
        $readiness=[pscustomobject][ordered]@{
            status='ready'
            mode=$Mode
            readyAt=(Get-Date).ToUniversalTime().ToString('o')
            hostLauncherPid=$host.Id
            hostRuntimePid=$hostRuntime.Id
            shellWindowReady=$true
            frontendIndex=$frontendIndex
            backendPid=$backendPid
            backendApiBase=$apiBase
            backendRuntimeManifest=$nativeRuntime.path
        }
        Add-Content -LiteralPath (Join-Path $session.logDirectory 'backend.stdout.log') -Value "Full mode backend supervised by CloudOS.Host; runtime pid=$backendPid api=$apiBase."
        Add-Content -LiteralPath (Join-Path $session.logDirectory 'frontend.stdout.log') -Value "Full mode frontend served from production build after native shell window readiness."
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
    Write-CloudOSLog $session "Sessão pronta; launcher retornará sem aguardar os serviços persistentes. Logs: $($session.logDirectory)"
    Write-Host "Para encerrar: .\Parar CloudOS.cmd"
    Write-Host "Para diagnosticar: .\Diagnosticar CloudOS.cmd"
    Write-Output ($launchResult | ConvertTo-Json -Depth 8 -Compress)
} catch {
    $message = $_.Exception.Message
    Write-CloudOSLog $session $message 'ERROR'
    $teardown=$null
    try{$teardown=Stop-CloudOSRecordedProcesses $session}catch{Write-CloudOSLog $session "Teardown após falha também falhou: $($_.Exception.Message)" 'ERROR'}
    [void](Complete-CloudOSSession -Session $session -Status 'failed' -ErrorCode 'LAUNCH_FAILED' -Message $message -TeardownResult $teardown -PersistCurrentState:$true)
    Write-Host "explorer `"$($session.logDirectory)`""
    exit 1
}
