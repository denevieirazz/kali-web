param(
    [switch]$NoLaunch,
    [switch]$NoAutoStart,
    [int]$KeepVersions = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw 'WINDOWS_PREVIEW_REQUIRED' }
if ($KeepVersions -lt 2) { $KeepVersions = 2 }

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Get-CloudOSRepoRoot
$config = Get-CloudOSProductConfig
$paths = Get-CloudOSArtifactPaths
$sha = Get-CloudOSGitSha

function Invoke-CloudOSProductStep {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$ScriptName
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "PRODUCT_STEP_MISSING:$ScriptName"
    }

    Write-Host ""
    Write-Host "[CloudOS] $Label"
    & $scriptPath -AllowDetached
}

Write-Host '[CloudOS] Preparando uma instalação preview autocontida para teste local.'
Write-Host '[CloudOS] O fluxo reutiliza o build/package oficial e não altera WSL, Registro ou partições.'

Invoke-CloudOSProductStep '1/3 Preparando dependências...' 'prepare-cloudos.ps1'
Invoke-CloudOSProductStep '2/3 Compilando artefatos...' 'build-cloudos.ps1'
Invoke-CloudOSProductStep '3/3 Empacotando distribuição...' 'package-cloudos.ps1'

$portableRoot = Join-Path $paths.Portable 'CloudOS-Portable'
$portableBootstrap = Join-Path $portableRoot 'app\CloudOS.Bootstrap.exe'
$portableHost = Join-Path $portableRoot 'app\app\host\CloudOS.Host.exe'
$portableNode = Join-Path $portableRoot 'runtime\node.exe'
if (-not (Test-Path -LiteralPath $portableBootstrap -PathType Leaf)) { throw "PREVIEW_BOOTSTRAP_MISSING:$portableBootstrap" }
if (-not (Test-Path -LiteralPath $portableHost -PathType Leaf)) { throw "PREVIEW_HOST_MISSING:$portableHost" }
if (-not (Test-Path -LiteralPath $portableNode -PathType Leaf)) { throw "PREVIEW_NODE_MISSING:$portableNode" }

$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($localAppData)) { throw 'LOCALAPPDATA_UNAVAILABLE' }

$previewRoot = Join-Path $localAppData 'CloudOS\Preview'
$versionsRoot = Join-Path $previewRoot 'versions'
$dataRoot = Join-Path $previewRoot 'data'
New-Item -ItemType Directory -Force -Path $previewRoot,$versionsRoot,$dataRoot | Out-Null

$startScript = Join-Path $previewRoot 'Start-CloudOS.ps1'
$stopScript = Join-Path $previewRoot 'Stop-CloudOS.ps1'
$rollbackScript = Join-Path $previewRoot 'Rollback-CloudOS.ps1'
$currentFile = Join-Path $previewRoot 'current.txt'
$previousFile = Join-Path $previewRoot 'previous.txt'

@'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$currentFile = Join-Path $PSScriptRoot 'current.txt'
if (-not (Test-Path -LiteralPath $currentFile -PathType Leaf)) { throw 'CLOUDOS_PREVIEW_CURRENT_MISSING' }
$current = (Get-Content -LiteralPath $currentFile -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($current)) { throw 'CLOUDOS_PREVIEW_CURRENT_EMPTY' }
$versionRoot = Join-Path (Join-Path $PSScriptRoot 'versions') $current
$bootstrap = Join-Path $versionRoot 'app\CloudOS.Bootstrap.exe'
$host = Join-Path $versionRoot 'app\app\host\CloudOS.Host.exe'
$appRoot = Join-Path $versionRoot 'app'
$node = Join-Path $versionRoot 'runtime\node.exe'
foreach ($required in @($bootstrap,$host,$node)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "CLOUDOS_PREVIEW_FILE_MISSING:$required" }
}
$env:CLOUDOS_LOCAL_ROOT = Join-Path $PSScriptRoot 'data'
$env:CLOUDOS_PORTABLE = '1'
& $bootstrap --host $host --root $appRoot --node $node
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $startScript -Encoding utf8

@'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$versionsRoot = Join-Path $PSScriptRoot 'versions'
$names = @('CloudOS.Bootstrap','CloudOS.Host','node')
foreach ($name in $names) {
    foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
        try { $path = $process.Path } catch { continue }
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ($path.StartsWith($versionsRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}
'@ | Set-Content -LiteralPath $stopScript -Encoding utf8

@'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$currentFile = Join-Path $PSScriptRoot 'current.txt'
$previousFile = Join-Path $PSScriptRoot 'previous.txt'
if (-not (Test-Path -LiteralPath $currentFile -PathType Leaf) -or -not (Test-Path -LiteralPath $previousFile -PathType Leaf)) {
    throw 'CLOUDOS_PREVIEW_ROLLBACK_UNAVAILABLE'
}
$current = (Get-Content -LiteralPath $currentFile -Raw).Trim()
$previous = (Get-Content -LiteralPath $previousFile -Raw).Trim()
$previousRoot = Join-Path (Join-Path $PSScriptRoot 'versions') $previous
if ([string]::IsNullOrWhiteSpace($previous) -or -not (Test-Path -LiteralPath $previousRoot -PathType Container)) {
    throw 'CLOUDOS_PREVIEW_PREVIOUS_VERSION_MISSING'
}
& (Join-Path $PSScriptRoot 'Stop-CloudOS.ps1')
Set-Content -LiteralPath $currentFile -Value $previous -Encoding ascii
Set-Content -LiteralPath $previousFile -Value $current -Encoding ascii
Start-Process -FilePath 'pwsh.exe' -ArgumentList @('-NoLogo','-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Start-CloudOS.ps1')) -WorkingDirectory $PSScriptRoot
Write-Host "CLOUDOS_PREVIEW_ROLLED_BACK from=$current to=$previous"
'@ | Set-Content -LiteralPath $rollbackScript -Encoding utf8

@'
@echo off
setlocal
where pwsh.exe >nul 2>&1 || (echo ERRO: PowerShell 7 ^(pwsh.exe^) e obrigatorio.& exit /b 1)
start "" pwsh.exe -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Start-CloudOS.ps1"
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $previewRoot 'Iniciar CloudOS.cmd') -Encoding ascii

@'
@echo off
setlocal
where pwsh.exe >nul 2>&1 || (echo ERRO: PowerShell 7 ^(pwsh.exe^) e obrigatorio.& exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop-CloudOS.ps1"
exit /b %ERRORLEVEL%
'@ | Set-Content -LiteralPath (Join-Path $previewRoot 'Parar CloudOS.cmd') -Encoding ascii

@'
@echo off
setlocal
where pwsh.exe >nul 2>&1 || (echo ERRO: PowerShell 7 ^(pwsh.exe^) e obrigatorio.& exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Rollback-CloudOS.ps1"
exit /b %ERRORLEVEL%
'@ | Set-Content -LiteralPath (Join-Path $previewRoot 'Rollback CloudOS.cmd') -Encoding ascii

# Stop only processes that belong to an older CloudOS Preview installation before switching versions.
& $stopScript

$versionId = '{0}-{1}' -f ([string]$config.version), $sha.Substring(0,8)
$versionRoot = Join-Path $versionsRoot $versionId
if (Test-Path -LiteralPath $versionRoot) {
    Remove-Item -LiteralPath $versionRoot -Recurse -Force
}
Copy-Item -LiteralPath $portableRoot -Destination $versionRoot -Recurse -Force

$oldCurrent = $null
if (Test-Path -LiteralPath $currentFile -PathType Leaf) {
    $candidate = (Get-Content -LiteralPath $currentFile -Raw).Trim()
    if (-not [string]::IsNullOrWhiteSpace($candidate)) { $oldCurrent = $candidate }
}
if ($oldCurrent -and $oldCurrent -ne $versionId) {
    Set-Content -LiteralPath $previousFile -Value $oldCurrent -Encoding ascii
}
Set-Content -LiteralPath $currentFile -Value $versionId -Encoding ascii

# Keep current + previous and prune stale preview versions. Never touches user data.
$protected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[void]$protected.Add($versionId)
if (Test-Path -LiteralPath $previousFile -PathType Leaf) {
    $previous = (Get-Content -LiteralPath $previousFile -Raw).Trim()
    if (-not [string]::IsNullOrWhiteSpace($previous)) { [void]$protected.Add($previous) }
}
$versionDirectories = @(Get-ChildItem -LiteralPath $versionsRoot -Directory | Sort-Object LastWriteTimeUtc -Descending)
$kept = 0
foreach ($directory in $versionDirectories) {
    if ($protected.Contains($directory.Name)) { $kept++; continue }
    if ($kept -lt $KeepVersions) { $kept++; continue }
    Remove-Item -LiteralPath $directory.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

$startupFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
$startupCmd = if ([string]::IsNullOrWhiteSpace($startupFolder)) { $null } else { Join-Path $startupFolder 'CloudOS Preview.cmd' }
if (-not $NoAutoStart -and $startupCmd) {
    $startupContent = "@echo off`r`nstart `"`" pwsh.exe -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startScript`"`r`nexit /b 0`r`n"
    Set-Content -LiteralPath $startupCmd -Value $startupContent -Encoding ascii
}

$state = [ordered]@{
    schemaVersion = 1
    preparedAt = [DateTimeOffset]::UtcNow.ToString('O')
    version = [string]$config.version
    commit = $sha
    current = $versionId
    previous = if (Test-Path -LiteralPath $previousFile -PathType Leaf) { (Get-Content -LiteralPath $previousFile -Raw).Trim() } else { $null }
    previewRoot = $previewRoot
    dataRoot = $dataRoot
    autoStart = (-not $NoAutoStart -and -not [string]::IsNullOrWhiteSpace($startupCmd))
    packageRoot = $portableRoot
}
$state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $previewRoot 'preview-state.json') -Encoding utf8

Write-Host ""
Write-Host "CLOUDOS_PREVIEW_READY version=$versionId"
Write-Host "[CloudOS] Instalação: $previewRoot"
Write-Host "[CloudOS] Dados persistentes: $dataRoot"
Write-Host "[CloudOS] Auto-start: $($state.autoStart)"
Write-Host "[CloudOS] Iniciar: $(Join-Path $previewRoot 'Iniciar CloudOS.cmd')"
Write-Host "[CloudOS] Parar: $(Join-Path $previewRoot 'Parar CloudOS.cmd')"
Write-Host "[CloudOS] Rollback: $(Join-Path $previewRoot 'Rollback CloudOS.cmd')"

if (-not $NoLaunch) {
    Start-Process -FilePath 'pwsh.exe' -ArgumentList @('-NoLogo','-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$startScript) -WorkingDirectory $previewRoot
    Write-Host '[CloudOS] CloudOS Preview iniciado.'
}
