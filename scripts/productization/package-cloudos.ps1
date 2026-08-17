param([switch]$AllowDetached)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-CloudOSProductizationBranch -AllowDetached:$AllowDetached
if (-not $IsWindows) { throw 'WINDOWS_PACKAGING_REQUIRED' }
$config = Get-CloudOSProductConfig
$paths = Get-CloudOSArtifactPaths
$root = Get-CloudOSRepoRoot
$sha = Get-CloudOSGitSha
$buildResultPath = Join-Path $paths.Build 'build-result.json'
if (-not (Test-Path -LiteralPath $buildResultPath)) { throw 'BUILD_RESULT_MISSING:run Compilar CloudOS.cmd first' }
$buildResult = Get-Content -LiteralPath $buildResultPath -Raw | ConvertFrom-Json
if ($buildResult.head -ne $sha) { throw "BUILD_HEAD_MISMATCH:built=$($buildResult.head) current=$sha" }
if ([string]$buildResult.corePackage -ne './cmd/cloudos-core') { throw "CLOUDOS_CORE_PACKAGE_MISMATCH:$($buildResult.corePackage)" }
if ([string]$buildResult.coreGoos -ne 'linux' -or [string]$buildResult.coreGoarch -ne 'amd64') { throw "CLOUDOS_CORE_TARGET_MISMATCH:$($buildResult.coreGoos)/$($buildResult.coreGoarch)" }
if ([string]$buildResult.coreSha256 -notmatch '^[0-9a-f]{64}$') { throw 'CLOUDOS_CORE_BUILD_HASH_INVALID' }
if (-not (Test-Path -LiteralPath $buildResult.core -PathType Leaf)) { throw 'CLOUDOS_CORE_BUILD_OUTPUT_MISSING' }
$coreBuildHash=(Get-FileHash -LiteralPath $buildResult.core -Algorithm SHA256).Hash.ToLowerInvariant()
if($coreBuildHash -ne ([string]$buildResult.coreSha256).ToLowerInvariant()){throw 'CLOUDOS_CORE_BUILD_HASH_MISMATCH'}

Remove-Item -LiteralPath $paths.Staging,$paths.Releases,$paths.Portable -Recurse -Force -ErrorAction SilentlyContinue
$stage = Ensure-CloudOSDirectory $paths.Staging
$releaseDir = Ensure-CloudOSDirectory $paths.Releases
$portableParent = Ensure-CloudOSDirectory $paths.Portable

Copy-Item -Path (Join-Path $buildResult.bootstrap '*') -Destination $stage -Recurse -Force
$hostDir = Ensure-CloudOSDirectory (Join-Path $stage 'app\host')
Copy-Item -Path (Join-Path $buildResult.host '*') -Destination $hostDir -Recurse -Force
$backendDir = Ensure-CloudOSDirectory (Join-Path $stage 'agent\backend')
Copy-Item -Path (Join-Path $buildResult.backend '*') -Destination $backendDir -Recurse -Force
$webDir = Ensure-CloudOSDirectory (Join-Path $stage 'web')
Copy-Item -Path (Join-Path $buildResult.frontend '*') -Destination $webDir -Recurse -Force
$runtimeDir = Ensure-CloudOSDirectory (Join-Path $stage 'runtime')
$nodeCache = Ensure-CloudOSNodeRuntime
$nodeExe=Join-Path $nodeCache 'node.exe'
$nodeRuntimeHash=(Get-FileHash -LiteralPath $nodeExe -Algorithm SHA256).Hash.ToLowerInvariant()
Copy-Item -LiteralPath $nodeExe -Destination (Join-Path $runtimeDir 'node.exe') -Force
if (Test-Path -LiteralPath (Join-Path $nodeCache 'LICENSE')) { Copy-Item -LiteralPath (Join-Path $nodeCache 'LICENSE') -Destination (Join-Path $runtimeDir 'NODE-LICENSE.txt') -Force }
$coreStagePath=Join-Path $runtimeDir 'cloudos-core'
Copy-Item -LiteralPath $buildResult.core -Destination $coreStagePath -Force
$coreStageHash=(Get-FileHash -LiteralPath $coreStagePath -Algorithm SHA256).Hash.ToLowerInvariant()
if($coreStageHash -ne ([string]$buildResult.coreSha256).ToLowerInvariant()){throw 'CLOUDOS_CORE_STAGING_HASH_MISMATCH'}

$meta = Ensure-CloudOSDirectory (Join-Path $stage 'meta')
$sbom = Ensure-CloudOSDirectory (Join-Path $meta 'SBOM')
$licenses = Ensure-CloudOSDirectory (Join-Path $meta 'licenses')
Copy-Item -LiteralPath (Join-Path $root 'productization\cloudos-product.json') -Destination (Join-Path $meta 'product.json') -Force
@"
CloudOS Experimental - unsigned-development
Velopack 1.2.0 - MIT - https://github.com/velopack/velopack
Node.js $($config.nodeVersion) - licença distribuída em runtime/NODE-LICENSE.txt
Microsoft.Web.WebView2 $($config.webView2SdkVersion) - consulte pacote NuGet oficial
Demais dependências: consulte meta/SBOM e meta/supply-chain.json.
"@ | Set-Content -LiteralPath (Join-Path $licenses 'THIRD-PARTY-NOTICES.txt') -Encoding utf8
@"
CLOUDOS EXPERIMENTAL / UNSIGNED DEVELOPMENT BUILD

Este artefato não possui assinatura Authenticode e não é uma release de produção.
Não altera WSL, Kali, Registro, partições ou políticas do Windows automaticamente.
"@ | Set-Content -LiteralPath (Join-Path $stage 'README-UNSIGNED.txt') -Encoding utf8

$npm = Get-CloudOSCommandName 'npm'; $dotnet=Get-CloudOSCommandName 'dotnet'; $go=Get-CloudOSCommandName 'go'
$npmSbom = Invoke-CloudOSExternal $npm @('sbom','--omit=dev','--sbom-format=cyclonedx') -Capture -AllowFailure
if ($npmSbom.ExitCode -eq 0) { Set-Content -LiteralPath (Join-Path $sbom 'npm.cyclonedx.json') -Value $npmSbom.Output -Encoding utf8 } else { throw "NPM_SBOM_FAILED:$($npmSbom.Output)" }
$nugetSbom = Invoke-CloudOSExternal $dotnet @('list','desktop/CloudOS.Host/CloudOS.Host.csproj','package','--include-transitive','--format','json') -Capture
Set-Content -LiteralPath (Join-Path $sbom 'nuget-host.json') -Value $nugetSbom.Output -Encoding utf8
$nugetBootstrap = Invoke-CloudOSExternal $dotnet @('list','desktop/CloudOS.Bootstrap/CloudOS.Bootstrap.csproj','package','--include-transitive','--format','json') -Capture
Set-Content -LiteralPath (Join-Path $sbom 'nuget-bootstrap.json') -Value $nugetBootstrap.Output -Encoding utf8
$goModules = Invoke-CloudOSExternal $go @('list','-m','-json','all') (Join-Path $root 'core/wsl/cloudos-core') -Capture
Set-Content -LiteralPath (Join-Path $sbom 'go-modules.jsonl') -Value $goModules.Output -Encoding utf8

$components=[ordered]@{
    schemaVersion=2; product=$config.product; version=$config.version; head=$sha; channel=$config.channel; rid=$config.rid; signing=$config.signing;
    components=@(
        [ordered]@{name='CloudOS.Bootstrap';kind='dotnet-wpf';deployment='self-contained';path='CloudOS.Bootstrap.exe';origin='repository:desktop/CloudOS.Bootstrap';evidence='meta/SBOM/nuget-bootstrap.json'},
        [ordered]@{name='CloudOS.Host';kind='dotnet-wpf-webview2';deployment='self-contained';path='app/host/CloudOS.Host.exe';origin='repository:desktop/CloudOS.Host';evidence='meta/SBOM/nuget-host.json'},
        [ordered]@{name='backend';kind='node-esm-bundle';runtime="Node $($config.nodeVersion)";path='agent/backend/src/server.js';origin='repository:backend';evidence='meta/SBOM/npm.cyclonedx.json'},
        [ordered]@{name='frontend';kind='vite-production';path='web/index.html';origin='repository:frontend';evidence='meta/SBOM/npm.cyclonedx.json'},
        [ordered]@{name='node';kind='runtime';version=$config.nodeVersion;path='runtime/node.exe';sha256=$nodeRuntimeHash;origin="https://nodejs.org/dist/v$($config.nodeVersion)/node-v$($config.nodeVersion)-win-x64.zip";evidence="runtime/node.exe sha256=$nodeRuntimeHash"},
        [ordered]@{name='cloudos-core';kind='linux-amd64';package='./cmd/cloudos-core';goos='linux';goarch='amd64';path='runtime/cloudos-core';sha256=$coreStageHash;origin='repository:core/wsl/cloudos-core';evidence='meta/SBOM/go-modules.jsonl'}
    )
}
Write-CloudOSJson $components (Join-Path $meta 'components.json')

$supplyChain=[ordered]@{
    schemaVersion=1;product=$config.product;version=$config.version;head=$sha;channel=$config.channel;rid=$config.rid;signing=$config.signing;
    generatedAt=[DateTimeOffset]::UtcNow.ToString('O');
    policies=[ordered]@{sourceTreeExcluded=$true;nodeModulesExcluded=$true;highConfidenceSecretScan='required';checksums='sha256';stablePublication=$false;authenticode='future'};
    inventories=@('meta/manifest.json','meta/components.json','meta/checksums.sha256','meta/SBOM/npm.cyclonedx.json','meta/SBOM/nuget-host.json','meta/SBOM/nuget-bootstrap.json','meta/SBOM/go-modules.jsonl');
    components=@(
        [ordered]@{name='CloudOS';version=$config.version;origin='git-repository';evidence="HEAD $sha";licenseEvidence='repository notices'},
        [ordered]@{name='CloudOS.Bootstrap';origin='repository:desktop/CloudOS.Bootstrap';evidence='meta/SBOM/nuget-bootstrap.json';licenseEvidence='NuGet inventory'},
        [ordered]@{name='CloudOS.Host';origin='repository:desktop/CloudOS.Host';evidence='meta/SBOM/nuget-host.json';licenseEvidence='NuGet inventory'},
        [ordered]@{name='backend';origin='repository:backend';evidence='package-lock.json + meta/SBOM/npm.cyclonedx.json';licenseEvidence='CycloneDX'},
        [ordered]@{name='frontend';origin='repository:frontend';evidence='package-lock.json + meta/SBOM/npm.cyclonedx.json';licenseEvidence='CycloneDX'},
        [ordered]@{name='Node.js';version=$config.nodeVersion;origin="https://nodejs.org/dist/v$($config.nodeVersion)/node-v$($config.nodeVersion)-win-x64.zip";evidence="runtime/node.exe sha256=$nodeRuntimeHash";licenseEvidence='runtime/NODE-LICENSE.txt'},
        [ordered]@{name='cloudos-core';origin='repository:core/wsl/cloudos-core';evidence="runtime/cloudos-core sha256=$coreStageHash + meta/SBOM/go-modules.jsonl";licenseEvidence='Go module inventory'},
        [ordered]@{name='Microsoft.Web.WebView2';version=$config.webView2SdkVersion;origin='NuGet:Microsoft.Web.WebView2';evidence='meta/SBOM/nuget-host.json';licenseEvidence='NuGet inventory'},
        [ordered]@{name='Velopack vpk';version=$config.velopackVersion;origin='NuGet:vpk';evidence='artifacts/tooling.json';licenseEvidence='meta/licenses/THIRD-PARTY-NOTICES.txt'}
    )
}
Write-CloudOSJson $supplyChain (Join-Path $meta 'supply-chain.json') 30

Assert-CloudOSStagingClean $stage
$unexpectedGoSource=Get-ChildItem -LiteralPath $stage -File -Recurse | Where-Object {$_.Extension -eq '.go' -or $_.Name -in @('go.mod','go.sum')}
if($unexpectedGoSource){throw "STAGING_GO_SOURCE_FORBIDDEN:$((@($unexpectedGoSource.FullName)-join ','))"}
$coreFiles=@(Get-ChildItem -LiteralPath $runtimeDir -File | Where-Object {$_.Name -eq 'cloudos-core'})
if($coreFiles.Count -ne 1){throw "STAGING_CLOUDOS_CORE_COUNT_INVALID:$($coreFiles.Count)"}

$inventory = New-CloudOSFileInventory $stage
$manifest=[ordered]@{
    schemaVersion=1; product=$config.product; version=$config.version; head=$sha; channel=$config.channel; rid=$config.rid; signing=$config.signing;
    generatedAt=[DateTimeOffset]::UtcNow.ToString('O');
    core=[ordered]@{path='runtime/cloudos-core';package='./cmd/cloudos-core';goos='linux';goarch='amd64';sha256=$coreStageHash};
    files=$inventory
}
Write-CloudOSJson $manifest (Join-Path $meta 'manifest.json') 40
Write-CloudOSChecksums $stage (Join-Path $meta 'checksums.sha256') @('meta/checksums.sha256')

$globalSbom = Join-Path $paths.Artifacts 'SBOM'; $globalLicenses=Join-Path $paths.Artifacts 'licenses'
Remove-Item -LiteralPath $globalSbom,$globalLicenses -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath $sbom -Destination $globalSbom -Recurse
Copy-Item -LiteralPath $licenses -Destination $globalLicenses -Recurse
Copy-Item -LiteralPath (Join-Path $meta 'manifest.json') -Destination (Join-Path $paths.Artifacts 'manifest.json') -Force
Copy-Item -LiteralPath (Join-Path $meta 'components.json') -Destination (Join-Path $paths.Artifacts 'components.json') -Force
Copy-Item -LiteralPath (Join-Path $meta 'supply-chain.json') -Destination (Join-Path $paths.Artifacts 'supply-chain.json') -Force
Copy-Item -LiteralPath (Join-Path $meta 'checksums.sha256') -Destination (Join-Path $paths.Artifacts 'checksums.sha256') -Force

$portableRoot = Ensure-CloudOSDirectory (Join-Path $portableParent 'CloudOS-Portable')
$appRoot = Ensure-CloudOSDirectory (Join-Path $portableRoot 'app')
foreach($file in Get-ChildItem -LiteralPath $stage -File){ Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $appRoot $file.Name) -Force }
foreach($name in @('app','agent','web','meta')){ if(Test-Path -LiteralPath (Join-Path $stage $name)){ Copy-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $appRoot $name) -Recurse -Force } }
Copy-Item -LiteralPath (Join-Path $stage 'runtime') -Destination (Join-Path $portableRoot 'runtime') -Recurse -Force
@'
@echo off
setlocal
if not exist "%~dp0data-portable" mkdir "%~dp0data-portable"
if not exist "%~dp0logs" mkdir "%~dp0logs"
set "CLOUDOS_LOCAL_ROOT=%~dp0data-portable"
set "CLOUDOS_PORTABLE=1"
"%~dp0app\CloudOS.Bootstrap.exe" --host "%~dp0app\app\host\CloudOS.Host.exe" --root "%~dp0app" --node "%~dp0runtime\node.exe"
exit /b %ERRORLEVEL%
'@ | Set-Content -LiteralPath (Join-Path $portableRoot 'Iniciar CloudOS.cmd') -Encoding ascii
$portableMeta=Ensure-CloudOSDirectory (Join-Path $portableRoot 'meta')
$portableInventory=New-CloudOSFileInventory $portableRoot
$portableManifest=[ordered]@{
    schemaVersion=1;product=$config.product;version=$config.version;head=$sha;channel=$config.channel;rid=$config.rid;signing=$config.signing;
    generatedAt=[DateTimeOffset]::UtcNow.ToString('O');layout='portable-relocated';sourceManifestSha256=(Get-FileHash -LiteralPath (Join-Path $meta 'manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant();files=$portableInventory
}
Write-CloudOSJson $portableManifest (Join-Path $portableMeta 'portable-manifest.json') 40
Write-CloudOSChecksums $portableRoot (Join-Path $portableMeta 'portable-checksums.sha256') @('meta/portable-checksums.sha256')
$portableZip = Join-Path $portableParent "CloudOS-Portable-$($config.version)-$($config.rid).zip"
New-CloudOSDeterministicZip $portableRoot $portableZip | Out-Null

$vpk = Join-Path $paths.Tools 'vpk.exe'
if (-not (Test-Path -LiteralPath $vpk)) { throw 'VELOPACK_TOOL_MISSING' }
Invoke-CloudOSExternal $vpk @('pack','--packId',[string]$config.packId,'--packVersion',[string]$config.version,'--packDir',$stage,'--mainExe','CloudOS.Bootstrap.exe','--packTitle',[string]$config.packTitle,'--packAuthors',[string]$config.publisher,'--channel',[string]$config.channel,'--runtime',[string]$config.rid,'--shortcuts','StartMenuRoot','--outputDir',$releaseDir,'--noPortable')

$setup = Get-ChildItem -LiteralPath $releaseDir -File -Filter '*Setup.exe' | Select-Object -First 1
$full = Get-ChildItem -LiteralPath $releaseDir -File -Filter '*-full.nupkg' | Select-Object -First 1
if (-not $setup -or -not $full) { throw 'VELOPACK_REQUIRED_OUTPUT_MISSING' }
$result=[ordered]@{schemaVersion=2;head=$sha;version=$config.version;rid=$config.rid;signing=$config.signing;staging=$stage;portableZip=$portableZip;setup=$setup.FullName;fullPackage=$full.FullName;supplyChain=(Join-Path $meta 'supply-chain.json');coreSha256=$coreStageHash;status='packaged'}
Write-CloudOSJson $result (Join-Path $paths.Artifacts 'package-result.json')
Write-Host "CLOUDOS_PRODUCT_PACKAGED setup=$($setup.FullName) portable=$portableZip coreSha256=$coreStageHash supplyChain=true portableManifest=true"
