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
if (Test-Path -LiteralPath $vpkExe) {
    $current = Invoke-CloudOSExternal $vpkExe @('--version') -Capture -AllowFailure
    if ($current.ExitCode -ne 0 -or $current.Output -notmatch [regex]::Escape([string]$config.velopackVersion)) {
        Remove-Item -LiteralPath $paths.Tools -Recurse -Force
        Ensure-CloudOSDirectory $paths.Tools | Out-Null
    }
}
if (-not (Test-Path -LiteralPath $vpkExe)) {
    Invoke-CloudOSExternal $dotnet @('tool','install','vpk','--tool-path',$paths.Tools,'--version',[string]$config.velopackVersion)
}
$vpkVersion = Invoke-CloudOSExternal $vpkExe @('--version') -Capture
if ($vpkVersion.Output -notmatch [regex]::Escape([string]$config.velopackVersion)) { throw "VELOPACK_VERSION_MISMATCH:$($vpkVersion.Output)" }

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
    velopack = $vpkVersion.Output
    signing = $config.signing
}
Write-CloudOSJson $tooling (Join-Path $paths.Artifacts 'tooling.json')
Write-Host "CLOUDOS_PRODUCT_PREPARED head=$sha velopack=$($config.velopackVersion) node=$($config.nodeVersion)"
