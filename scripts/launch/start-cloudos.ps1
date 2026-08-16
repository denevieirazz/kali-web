param(
    [ValidateSet('Full','WebOnly','Developer','UXValidation','FilesValidation','BrowserValidation','TerminalValidation')]
    [string]$Mode='Full'
)

. (Join-Path $PSScriptRoot 'cloudos-launcher-common.ps1')
. (Join-Path $PSScriptRoot 'cloudos-owned-processes.ps1')
. (Join-Path $PSScriptRoot '..\validate\cloudos-node-dependencies.ps1')

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
    if ($Mode -in @('UXValidation','FilesValidation','BrowserValidation','TerminalValidation')) {
        $env:NODE_ENV = 'test'
    }

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

    if ($Mode -in @('Full','BrowserValidation')) {
        Write-CloudOSLog $session 'Compilando frontend para o Host nativo.'
        Push-Location $script:CloudOSRoot
        try {
            & $pre.npm --prefix frontend run build *>> (Join-Path $session.logDirectory 'bootstrap.log')
            if ($LASTEXITCODE -ne 0) { throw "FRONTEND_BUILD_FAILED:$LASTEXITCODE:log=$(Join-Path $session.logDirectory 'bootstrap.log')" }
        } finally { Pop-Location }

        $hostErr = Join-Path $session.logDirectory 'host.stderr.log'
        New-Item -ItemType File -Force -Path $hostErr | Out-Null
        $hostScript = Join-Path $script:CloudOSRoot 'scripts\run-native-host.ps1'
        $hostArgs = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $hostScript + '"'))
        if ($Mode -eq 'BrowserValidation') { $hostArgs += '-DeveloperMode' }
        $host = Start-CloudOSLoggedProcess $session 'host' $pre.pwsh $hostArgs (Join-Path $session.logDirectory 'host.log') $hostErr @{
            CLOUDOS_LAUNCH_MODE=$Mode; CLOUDOS_RUNTIME_DIR=$session.runtimeDirectory; CLOUDOS_DATA_DIR=$session.dataDirectory
        }
        Start-Sleep -Milliseconds 700
        $host.Refresh()
        if ($host.HasExited) {
            $tail = ((Get-Content -LiteralPath $hostErr -Tail 30 -ErrorAction SilentlyContinue) -join ' | ')
            throw "HOST_EXITED_EARLY:$($host.ExitCode):log=$hostErr:error=$tail"
        }
        Add-Content -LiteralPath (Join-Path $session.logDirectory 'backend.stdout.log') -Value 'Full mode: backend stream is supervised by CloudOS.Host; native host log is authoritative for this stage.'
        Add-Content -LiteralPath (Join-Path $session.logDirectory 'frontend.stdout.log') -Value 'Full mode: frontend is served from the production build by CloudOS.Host.'
    } else {
        $backend = Start-CloudOSLoggedProcess $session 'backend' $pre.node @('backend/src/server.js') (Join-Path $session.logDirectory 'backend.stdout.log') (Join-Path $session.logDirectory 'backend.stderr.log') @{
            CLOUDOS_LAUNCH_MODE=$Mode; CLOUDOS_RUNTIME_DIR=$session.runtimeDirectory; CLOUDOS_DATA_DIR=$session.dataDirectory; CLOUDOS_NATIVE_HOST='0'; PORT='0'; HOST='127.0.0.1'
        }
        $backendManifest = Wait-CloudOSReadinessFile $session $backend 'backend' (Join-Path $session.runtimeDirectory 'backend-port.json') 25
        $env:VITE_CLOUDOS_API_BASE = "http://127.0.0.1:$($backendManifest.backendPort)"
        $frontend = Start-CloudOSLoggedProcess $session 'frontend' $pre.node @('frontend/scripts/dev-server.js') (Join-Path $session.logDirectory 'frontend.stdout.log') (Join-Path $session.logDirectory 'frontend.stderr.log') @{
            CLOUDOS_LAUNCH_MODE=$Mode; CLOUDOS_RUNTIME_DIR=$session.runtimeDirectory; CLOUDOS_NATIVE_HOST='0'
        }
        $frontendManifest = Wait-CloudOSReadinessFile $session $frontend 'frontend' (Join-Path $session.runtimeDirectory 'frontend-port.json') 25
        $url = "http://127.0.0.1:$($frontendManifest.port)"
        Write-CloudOSLog $session "Frontend pronto: $url"
        if ($Mode -notin @('FilesValidation','TerminalValidation')) { Start-Process $url | Out-Null }
    }

    $session.status='running'
    Write-CloudOSJsonAtomic (Join-Path $session.logDirectory 'manifest.json') $session
    Write-CloudOSJsonAtomic $script:SessionStateFile $session
    Write-CloudOSLog $session "Sessão iniciada. Logs: $($session.logDirectory)"
    Write-Host "Para encerrar: .\Parar CloudOS.cmd"
    Write-Host "Para diagnosticar: .\Diagnosticar CloudOS.cmd"
    Write-Host "explorer `"$($session.logDirectory)`""
} catch {
    $message = $_.Exception.Message
    Write-CloudOSLog $session $message 'ERROR'
    Stop-CloudOSRecordedProcesses $session
    Complete-CloudOSSession $session 'failed' 'LAUNCH_FAILED' $message
    Write-Host "explorer `"$($session.logDirectory)`""
    exit 1
}
