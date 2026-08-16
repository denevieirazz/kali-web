param([switch]$AllowDetached)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-CloudOSProductizationBranch -AllowDetached:$AllowDetached
$config = Get-CloudOSProductConfig
$paths = Get-CloudOSArtifactPaths
$sha = Get-CloudOSGitSha

$npm = Get-CloudOSCommandName 'npm'
$dotnet = Get-CloudOSCommandName 'dotnet'
$go = Get-CloudOSCommandName 'go'

Write-Host "[CloudOS] Preparando dependências a partir do lockfile raiz..."
Invoke-CloudOSExternal $npm @('ci','--include=dev')

$vpkExe = Join-Path $paths.Tools ($(if($IsWindows){'vpk.exe'}else{'vpk'}))
$vpkPattern = "(?im)^\s*vpk\s+$([regex]::Escape([string]$config.velopackVersion))\s+vpk\s*$"
if (Test-Path -LiteralPath $vpkExe) {
    $currentTools = Invoke-CloudOSExternal $dotnet @('tool','list','--tool-path',$paths.Tools) -Capture -AllowFailure
    if ($currentTools.ExitCode -ne 0 -or $currentTools.Output -notmatch $vpkPattern) {
        Remove-Item -LiteralPath $paths.Tools -Recurse -Force
        Ensure-CloudOSDirectory $paths.Tools | Out-Null
    }
}
if (-not (Test-Path -LiteralPath $vpkExe)) {
    Invoke-CloudOSExternal $dotnet @('tool','install','vpk','--tool-path',$paths.Tools,'--version',[string]$config.velopackVersion)
}
$vpkTools = Invoke-CloudOSExternal $dotnet @('tool','list','--tool-path',$paths.Tools) -Capture
if ($vpkTools.Output -notmatch $vpkPattern) { throw "VELOPACK_VERSION_MISMATCH:$($vpkTools.Output)" }
$vpkVersion = [string]$config.velopackVersion

$nodeRuntime = Ensure-CloudOSNodeRuntime
$nodeHash = (Get-FileHash -LiteralPath (Join-Path $nodeRuntime 'node.exe') -Algorithm SHA256).Hash.ToLowerInvariant()

$tooling = [ordered]@{
    schemaVersion = 1
    preparedAt = [DateTimeOffset]::UtcNow.ToString('O')
    head = $sha
    branch = 'productization/cloudos-distribution-batch-2'
    nodeBuild = (Invoke-CloudOSExternal (Get-CloudOSCommandName 'node') @('--version') -Capture).Output
    nodeRuntime = "v$($config.nodeVersion)"
    nodeRuntimeSha256 = $nodeHash
    npm = (Invoke-CloudOSExternal $npm @('--version') -Capture).Output
    dotnet = (Invoke-CloudOSExternal $dotnet @('--version') -Capture).Output
    go = (Invoke-CloudOSExternal $go @('version') -Capture).Output
    velopack = $vpkVersion
    signing = $config.signing
}
Write-CloudOSJson $tooling (Join-Path $paths.Artifacts 'tooling.json')
Write-Host "CLOUDOS_PRODUCT_PREPARED head=$sha velopack=$($config.velopackVersion) node=$($config.nodeVersion)"
