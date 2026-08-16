param([switch]$SkipIfUnavailable)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if(-not $IsWindows){throw 'WSL_CORE_SMOKE_WINDOWS_REQUIRED'}
$paths=Get-CloudOSArtifactPaths
$resultPath=Join-Path $paths.Artifacts 'package-result.json'
if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'WSL_CORE_SMOKE_PACKAGE_RESULT_MISSING'}
$result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
$corePath=Join-Path ([string]$result.staging) 'runtime\cloudos-core'
if(-not(Test-Path -LiteralPath $corePath -PathType Leaf)){throw 'WSL_CORE_SMOKE_BINARY_MISSING'}

$wsl=Get-Command 'wsl.exe' -ErrorAction SilentlyContinue
if(-not $wsl){
    if($SkipIfUnavailable){Write-Host 'PRODUCTIZATION_WSL_CORE_SMOKE_SKIPPED reason=wsl-executable-unavailable';return}
    throw 'WSL_CORE_SMOKE_WSL_UNAVAILABLE'
}

$list=& $wsl.Source --list --quiet 2>&1 | Out-String
$listExit=$LASTEXITCODE
$distros=@($list -split "`r?`n" | ForEach-Object {(($_ -replace "`0",'').Trim())} | Where-Object {-not [string]::IsNullOrWhiteSpace($_)})
if($listExit -ne 0 -or $distros.Count -eq 0){
    if($SkipIfUnavailable){Write-Host "PRODUCTIZATION_WSL_CORE_SMOKE_SKIPPED reason=no-existing-distro exit=$listExit";return}
    throw "WSL_CORE_SMOKE_DISTRO_UNAVAILABLE:exit=$listExit"
}
$distro=[string]$distros[0]

$translated=& $wsl.Source -d $distro --exec wslpath -a -u $corePath 2>&1 | Out-String
$translateExit=$LASTEXITCODE
$linuxPath=$translated.Trim()
if($translateExit -ne 0 -or [string]::IsNullOrWhiteSpace($linuxPath) -or -not $linuxPath.StartsWith('/')){
    throw "WSL_CORE_SMOKE_PATH_TRANSLATION_FAILED:exit=$translateExit"
}

$smoke=& $wsl.Source -d $distro --exec $linuxPath 2>&1 | Out-String
$smokeExit=$LASTEXITCODE
if($smokeExit -ne 2){throw "WSL_CORE_SMOKE_UNEXPECTED_EXIT:$smokeExit"}
if($smoke -notmatch 'usage:\s+cloudos-core\s+serve'){throw 'WSL_CORE_SMOKE_USAGE_MISSING'}

$coreHash=(Get-FileHash -LiteralPath $corePath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "PRODUCTIZATION_WSL_CORE_SMOKE_OK distro=$distro sha256=$coreHash"
