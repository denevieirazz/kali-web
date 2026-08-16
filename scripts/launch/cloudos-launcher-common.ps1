param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CloudOSRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:RuntimeStateRoot = Join-Path $script:CloudOSRoot '.cloudos-runtime'
$script:SessionStateFile = Join-Path $script:RuntimeStateRoot 'current-session.json'
$script:AllowedModes = @('Full','WebOnly','Developer','UXValidation','FilesValidation','BrowserValidation','TerminalValidation')

function Write-CloudOSJsonAtomic {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $directory = Split-Path -Parent $Path
    if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
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
    foreach($name in @('launcher.log','backend.stdout.log','backend.stderr.log','frontend.stdout.log','frontend.stderr.log','host.log','bootstrap.log','wsl-core.log')) {
        New-Item -ItemType File -Force -Path (Join-Path $sessionDir $name) | Out-Null
    }
    $session = [ordered]@{
        schemaVersion=1; id=$id; mode=$Mode; startedAt=(Get-Date).ToUniversalTime().ToString('o');
        root=$script:CloudOSRoot; logDirectory=$sessionDir; runtimeDirectory=(Join-Path $sessionDir 'runtime');
        dataDirectory=(Join-Path $sessionDir 'data'); git=$git; processes=@(); status='starting';
    }
    New-Item -ItemType Directory -Force -Path $session.runtimeDirectory,$session.dataDirectory | Out-Null
    Write-CloudOSJsonAtomic (Join-Path $sessionDir 'environment.json') ([ordered]@{
        os=[Environment]::OSVersion.VersionString; machine=$env:COMPUTERNAME; user=$env:USERNAME;
        powershell=$PSVersionTable.PSVersion.ToString(); mode=$Mode; timestamp=(Get-Date).ToUniversalTime().ToString('o')
    })
    Write-CloudOSJsonAtomic (Join-Path $sessionDir 'manifest.json') $session
    Write-CloudOSJsonAtomic $script:SessionStateFile $session
    return $session
}

function Write-CloudOSLog {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][string]$Message,[string]$Level='INFO')
    $line = "$(Get-Date -Format o) [$Level] $Message"
    Add-Content -LiteralPath (Join-Path $Session.logDirectory 'launcher.log') -Value $line -Encoding UTF8
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

function Install-CloudOSLocalDependencies {
    param([Parameter(Mandatory)]$Session)
    $marker = Join-Path $script:CloudOSRoot 'node_modules'
    if (Test-Path $marker) { Write-CloudOSLog $Session 'Dependências npm locais já presentes.'; return }
    Write-CloudOSLog $Session 'Preparando dependências npm locais com npm ci na raiz.'
    $out = Join-Path $Session.logDirectory 'bootstrap.log'
    Push-Location $script:CloudOSRoot
    try {
        & npm ci *>> $out
        if ($LASTEXITCODE -ne 0) { throw "NPM_CI_FAILED:$LASTEXITCODE" }
    } finally { Pop-Location }
}

function Get-CloudOSProcessSnapshot {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CreationDate
}

function Save-CloudOSProcessSnapshot {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][ValidateSet('before','after')]$When)
    Write-CloudOSJsonAtomic (Join-Path $Session.logDirectory "processes-$When.json") (Get-CloudOSProcessSnapshot)
}

function Add-CloudOSProcessRecord {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][System.Diagnostics.Process]$Process,[Parameter(Mandatory)][string]$Component)
    $record = [ordered]@{ component=$Component; pid=$Process.Id; startedAt=$Process.StartTime.ToUniversalTime().ToString('o'); processName=$Process.ProcessName }
    $Session.processes = @($Session.processes) + @($record)
    Write-CloudOSJsonAtomic (Join-Path $Session.logDirectory 'manifest.json') $Session
    Write-CloudOSJsonAtomic $script:SessionStateFile $Session
}

function Start-CloudOSLoggedProcess {
    param(
        [Parameter(Mandatory)]$Session,[Parameter(Mandatory)][string]$Component,[Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList=@(),[Parameter(Mandatory)][string]$StdOut,[Parameter(Mandatory)][string]$StdErr,
        [hashtable]$Environment=@{}
    )
    foreach($key in $Environment.Keys) { [Environment]::SetEnvironmentVariable($key,[string]$Environment[$key],'Process') }
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $script:CloudOSRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $StdOut -RedirectStandardError $StdErr
    Add-CloudOSProcessRecord $Session $process $Component
    Write-CloudOSLog $Session "$Component iniciado pid=$($process.Id)."
    return $process
}

function Wait-CloudOSReadinessFile {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][System.Diagnostics.Process]$Process,[Parameter(Mandatory)][string]$Component,[Parameter(Mandatory)][string]$Path,[int]$TimeoutSeconds=25)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            $tailPath = if ($Component -eq 'backend') { Join-Path $Session.logDirectory 'backend.stderr.log' } else { Join-Path $Session.logDirectory 'frontend.stderr.log' }
            $tail = if (Test-Path $tailPath) { (Get-Content $tailPath -Tail 20 -ErrorAction SilentlyContinue) -join ' | ' } else { '' }
            $safe = ($tail -replace '(?i)(secret|token|password|authorization)\s*[:=]\s*\S+','$1=[redacted]')
            throw "PROCESS_DIED_BEFORE_READINESS component=$Component exit=$($Process.ExitCode) log=$tailPath error=$safe"
        }
        if (Test-Path $Path) {
            try {
                $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
                if ($manifest) { return $manifest }
            } catch { }
        }
        Start-Sleep -Milliseconds 120
    }
    throw "READINESS_TIMEOUT component=$Component path=$Path log=$($Session.logDirectory)"
}

function Complete-CloudOSSession {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][string]$Status,[string]$ErrorCode='',[string]$Message='')
    $Session.status = $Status
    $Session.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    Save-CloudOSProcessSnapshot $Session 'after'
    $result = [ordered]@{ schemaVersion=1; id=$Session.id; mode=$Session.mode; status=$Status; errorCode=$ErrorCode; message=$Message; logDirectory=$Session.logDirectory; git=$Session.git; finishedAt=$Session.finishedAt }
    Write-CloudOSJsonAtomic (Join-Path $Session.logDirectory 'result.json') $result
    Write-CloudOSJsonAtomic (Join-Path $Session.logDirectory 'manifest.json') $Session
    Write-CloudOSJsonAtomic $script:SessionStateFile $Session
}

function Read-CloudOSCurrentSession {
    if (-not (Test-Path $script:SessionStateFile)) { return $null }
    try { return Get-Content -LiteralPath $script:SessionStateFile -Raw | ConvertFrom-Json } catch { return $null }
}

function Stop-CloudOSRecordedProcesses {
    param([Parameter(Mandatory)]$Session)
    foreach($record in @($Session.processes) | Sort-Object { $_.pid } -Descending) {
        $process = Get-Process -Id ([int]$record.pid) -ErrorAction SilentlyContinue
        if (-not $process) { continue }
        try {
            $actualStart = $process.StartTime.ToUniversalTime().ToString('o')
            if ($actualStart -ne [string]$record.startedAt) { continue }
            Stop-Process -Id $process.Id -ErrorAction Stop
            if (-not $process.WaitForExit(5000)) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
        } catch { }
    }
}
