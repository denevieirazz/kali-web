param([switch]$AllowDetached)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-CloudOSProductizationBranch -AllowDetached:$AllowDetached
$config = Get-CloudOSProductConfig
$paths = Get-CloudOSArtifactPaths
$sha = Get-CloudOSGitSha
$root = Get-CloudOSRepoRoot

if (-not (Test-Path -LiteralPath (Join-Path $root 'node_modules'))) { throw 'DEPENDENCIES_NOT_PREPARED:run Preparar CloudOS.cmd first' }
if (-not (Test-Path -LiteralPath (Join-Path $paths.Tools ($(if($IsWindows){'vpk.exe'}else{'vpk'}))))) { throw 'VELOPACK_NOT_PREPARED:run Preparar CloudOS.cmd first' }

$npm = Get-CloudOSCommandName 'npm'
$dotnet = Get-CloudOSCommandName 'dotnet'
$npx = Get-CloudOSCommandName 'npx'
$go = Get-CloudOSCommandName 'go'

$oldVersion=$env:VITE_CLOUDOS_VERSION; $oldSha=$env:VITE_CLOUDOS_SHA; $oldChannel=$env:VITE_CLOUDOS_CHANNEL
try {
    $env:VITE_CLOUDOS_VERSION=[string]$config.version
    $env:VITE_CLOUDOS_SHA=$sha
    $env:VITE_CLOUDOS_CHANNEL=[string]$config.channel
    Invoke-CloudOSExternal $npm @('run','lint')
    Invoke-CloudOSExternal $npm @('test')
    Invoke-CloudOSExternal $npm @('run','test:e2e')
    Invoke-CloudOSExternal $npm @('run','test:frontend')
    Invoke-CloudOSExternal $npm @('run','build')
} finally {
    $env:VITE_CLOUDOS_VERSION=$oldVersion; $env:VITE_CLOUDOS_SHA=$oldSha; $env:VITE_CLOUDOS_CHANNEL=$oldChannel
}

Invoke-CloudOSExternal $dotnet @('build','desktop/CloudOS.Host/CloudOS.Host.csproj','-c','Release','--nologo')
Invoke-CloudOSExternal $dotnet @('run','--project','desktop/CloudOS.Host.Tests/CloudOS.Host.Tests.csproj','-c','Release')
Invoke-CloudOSExternal $dotnet @('build','desktop/CloudOS.Bootstrap/CloudOS.Bootstrap.csproj','-c','Release','--nologo')
Invoke-CloudOSExternal $dotnet @('run','--project','desktop/CloudOS.Bootstrap.Tests/CloudOS.Bootstrap.Tests.csproj','-c','Release')
Invoke-CloudOSExternal $dotnet @('build','desktop/CloudOS.WslCore/CloudOS.WslCore.csproj','-c','Release','--nologo')
Invoke-CloudOSExternal $dotnet @('run','--project','desktop/CloudOS.WslCore.Tests/CloudOS.WslCore.Tests.csproj','-c','Release')
if ($IsWindows) { & (Join-Path $root 'scripts/test-native-host-freshness.ps1'); if ($LASTEXITCODE -ne 0) { throw 'NATIVE_HOST_FRESHNESS_FAILED' } }

$hostPublish = Join-Path $paths.Build 'host'
$bootstrapPublish = Join-Path $paths.Build 'bootstrap'
$backendBuild = Join-Path $paths.Build 'backend'
Remove-Item -LiteralPath $hostPublish,$bootstrapPublish,$backendBuild -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $hostPublish,$bootstrapPublish,(Join-Path $backendBuild 'src') | Out-Null

Invoke-CloudOSExternal $dotnet @('publish','desktop/CloudOS.Host/CloudOS.Host.csproj','-c','Release','-r',[string]$config.rid,'--self-contained','true','-p:PublishSingleFile=false','-p:DebugType=None','-p:DebugSymbols=false','-o',$hostPublish)
Invoke-CloudOSExternal $dotnet @('publish','desktop/CloudOS.Bootstrap/CloudOS.Bootstrap.csproj','-c','Release','-r',[string]$config.rid,'--self-contained','true','-p:PublishSingleFile=false','-p:DebugType=None','-p:DebugSymbols=false','-o',$bootstrapPublish)

$backendOutput = Join-Path $backendBuild 'src\server.js'
Invoke-CloudOSExternal $npx @('--no-install','esbuild','backend/src/server.js','--bundle','--platform=node','--format=esm','--target=node22',"--outfile=$backendOutput",'--log-level=warning')
Set-Content -LiteralPath (Join-Path $backendBuild 'package.json') -Value '{"type":"module","private":true}' -Encoding utf8

$coreRoot = Join-Path $root 'core/wsl/cloudos-core'
$corePackage = './cmd/cloudos-core'
$coreOutput = Join-Path $paths.Build 'cloudos-core-linux-amd64'
$coreTestMode = 'linux-ci-prerequisite'
if (-not $IsWindows) {
    Invoke-CloudOSExternal $go @('test','./...') $coreRoot
    $coreTestMode = 'executed-on-linux-host'
} else {
    Write-Host '[CloudOS] cloudos-core usa syscalls Linux; go test ./... é exigido no job Linux, que antecede o job Windows.'
}
$oldGoos=$env:GOOS; $oldGoarch=$env:GOARCH; $oldCgo=$env:CGO_ENABLED
try {
    $env:GOOS='linux'; $env:GOARCH='amd64'; $env:CGO_ENABLED='0'
    Invoke-CloudOSExternal $go @('build','-trimpath','-ldflags=-buildid=','-o',$coreOutput,$corePackage) $coreRoot
} finally { $env:GOOS=$oldGoos; $env:GOARCH=$oldGoarch; $env:CGO_ENABLED=$oldCgo }
if (-not (Test-Path -LiteralPath $coreOutput -PathType Leaf)) { throw 'CLOUDOS_CORE_BUILD_OUTPUT_MISSING' }
$coreFile = Get-Item -LiteralPath $coreOutput
if ($coreFile.Length -le 0) { throw 'CLOUDOS_CORE_BUILD_OUTPUT_EMPTY' }
$coreSha256 = (Get-FileHash -LiteralPath $coreOutput -Algorithm SHA256).Hash.ToLowerInvariant()

$result=[ordered]@{
    schemaVersion=1; head=$sha; version=$config.version; rid=$config.rid; status='built';
    frontend=(Join-Path $root 'frontend/dist'); backend=$backendBuild; host=$hostPublish; bootstrap=$bootstrapPublish;
    core=$coreOutput; corePackage=$corePackage; coreGoos='linux'; coreGoarch='amd64'; coreSha256=$coreSha256; coreTestMode=$coreTestMode
}
Write-CloudOSJson $result (Join-Path $paths.Build 'build-result.json')
Write-Host "CLOUDOS_PRODUCT_BUILT head=$sha version=$($config.version) core=$corePackage sha256=$coreSha256 testMode=$coreTestMode"
