param([string]$ResultPath)
. (Join-Path $PSScriptRoot 'common.ps1')
$config=Get-CloudOSProductConfig
$paths=Get-CloudOSArtifactPaths
if([string]::IsNullOrWhiteSpace($ResultPath)){$ResultPath=Join-Path $paths.Artifacts 'package-result.json'}
$result=Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json
$stage=[IO.Path]::GetFullPath([string]$result.staging)
foreach($relative in @('CloudOS.Bootstrap.exe','app\host\CloudOS.Host.exe','agent\backend\src\server.js','web\index.html','runtime\node.exe','runtime\cloudos-core','meta\product.json','meta\manifest.json','meta\components.json','meta\supply-chain.json','meta\checksums.sha256','README-UNSIGNED.txt')){
    if(-not(Test-Path -LiteralPath (Join-Path $stage $relative))){throw "PACKAGE_REQUIRED_FILE_MISSING:$relative"}
}
Assert-CloudOSStagingClean $stage
$goSources=@(Get-ChildItem -LiteralPath $stage -File -Recurse | Where-Object {$_.Extension -eq '.go' -or $_.Name -in @('go.mod','go.sum')})
if($goSources.Count -ne 0){throw "PACKAGE_GO_SOURCE_PRESENT:$((@($goSources.FullName)-join ','))"}
$coreFiles=@(Get-ChildItem -LiteralPath (Join-Path $stage 'runtime') -File | Where-Object {$_.Name -eq 'cloudos-core'})
if($coreFiles.Count -ne 1){throw "PACKAGE_CLOUDOS_CORE_COUNT_INVALID:$($coreFiles.Count)"}
$corePath=Join-Path $stage 'runtime\cloudos-core'
$coreHash=(Get-FileHash -LiteralPath $corePath -Algorithm SHA256).Hash.ToLowerInvariant()
if(([string]$result.coreSha256).ToLowerInvariant() -ne $coreHash){throw 'PACKAGE_RESULT_CORE_HASH_MISMATCH'}

$manifest=Get-Content -LiteralPath (Join-Path $stage 'meta\manifest.json') -Raw | ConvertFrom-Json
if([string]$manifest.core.path -ne 'runtime/cloudos-core'){throw 'PACKAGE_MANIFEST_CORE_PATH_INVALID'}
if([string]$manifest.core.package -ne './cmd/cloudos-core'){throw 'PACKAGE_MANIFEST_CORE_PACKAGE_INVALID'}
if([string]$manifest.core.goos -ne 'linux' -or [string]$manifest.core.goarch -ne 'amd64'){throw 'PACKAGE_MANIFEST_CORE_TARGET_INVALID'}
if(([string]$manifest.core.sha256).ToLowerInvariant() -ne $coreHash){throw 'PACKAGE_MANIFEST_CORE_HASH_MISMATCH'}
foreach($file in @($manifest.files)){
    $path=Join-Path $stage (([string]$file.path).Replace('/',[IO.Path]::DirectorySeparatorChar))
    if(-not(Test-Path -LiteralPath $path)){throw "PACKAGE_MANIFEST_FILE_MISSING:$($file.path)"}
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ne ([string]$file.sha256).ToLowerInvariant()){throw "PACKAGE_MANIFEST_HASH_MISMATCH:$($file.path)"}
}
$coreInventory=@($manifest.files | Where-Object {[string]$_.path -eq 'runtime/cloudos-core'})
if($coreInventory.Count -ne 1 -or ([string]$coreInventory[0].sha256).ToLowerInvariant() -ne $coreHash){throw 'PACKAGE_MANIFEST_CORE_INVENTORY_INVALID'}
$components=Get-Content -LiteralPath (Join-Path $stage 'meta\components.json') -Raw | ConvertFrom-Json
$coreComponent=@($components.components | Where-Object {[string]$_.name -eq 'cloudos-core'})
if($coreComponent.Count -ne 1){throw 'PACKAGE_COMPONENT_CORE_MISSING'}
if([string]$coreComponent[0].package -ne './cmd/cloudos-core' -or [string]$coreComponent[0].goos -ne 'linux' -or [string]$coreComponent[0].goarch -ne 'amd64'){throw 'PACKAGE_COMPONENT_CORE_CONTRACT_INVALID'}
if(([string]$coreComponent[0].sha256).ToLowerInvariant() -ne $coreHash){throw 'PACKAGE_COMPONENT_CORE_HASH_MISMATCH'}
foreach($component in @($components.components)){if([string]::IsNullOrWhiteSpace([string]$component.origin) -or [string]::IsNullOrWhiteSpace([string]$component.evidence)){throw "PACKAGE_COMPONENT_ORIGIN_MISSING:$($component.name)"}}
$supply=Get-Content -LiteralPath (Join-Path $stage 'meta\supply-chain.json') -Raw|ConvertFrom-Json
if([string]$supply.head -ne [string]$result.head -or @($supply.components).Count -lt 8){throw 'PACKAGE_SUPPLY_CHAIN_INVALID'}
foreach($component in @($supply.components)){if([string]::IsNullOrWhiteSpace([string]$component.origin) -or [string]::IsNullOrWhiteSpace([string]$component.evidence)){throw "PACKAGE_SUPPLY_ORIGIN_MISSING:$($component.name)"}}

$nodeVersion=(& (Join-Path $stage 'runtime\node.exe') --version 2>&1 | Out-String).Trim()
if($nodeVersion -ne "v$($config.nodeVersion)"){throw "PACKAGED_NODE_VERSION_MISMATCH:$nodeVersion"}
if(-not(Test-Path -LiteralPath $result.setup)){throw 'PACKAGE_SETUP_MISSING'}
if(-not(Test-Path -LiteralPath $result.fullPackage)){throw 'PACKAGE_FULL_NUPKG_MISSING'}
if(-not(Test-Path -LiteralPath $result.portableZip)){throw 'PACKAGE_PORTABLE_ZIP_MISSING'}
$signature=Get-AuthenticodeSignature -LiteralPath $result.setup
if($signature.Status -eq 'Valid'){throw 'UNEXPECTED_SIGNED_SETUP_IN_UNSIGNED_BATCH'}
Add-Type -AssemblyName System.IO.Compression

$nupkg=[IO.Compression.ZipFile]::OpenRead([string]$result.fullPackage)
try{
    $nupkgEntries=@($nupkg.Entries.FullName | ForEach-Object {$_.Replace('\','/')})
    foreach($suffix in @('/CloudOS.Bootstrap.exe','/meta/product.json','/meta/manifest.json','/meta/components.json','/meta/supply-chain.json','/runtime/node.exe','/runtime/cloudos-core')){
        $matches=@($nupkgEntries | Where-Object {$_.EndsWith($suffix,[StringComparison]::OrdinalIgnoreCase)})
        if($matches.Count -ne 1){throw "FULL_PACKAGE_ENTRY_COUNT_INVALID:suffix=$suffix count=$($matches.Count)"}
    }
    $nupkgGoSources=@($nupkgEntries | Where-Object {$_ -match '(^|/)go\.(mod|sum)$|\.go$'})
    if($nupkgGoSources.Count -ne 0){throw "FULL_PACKAGE_GO_SOURCE_PRESENT:$($nupkgGoSources -join ',')"}
    $nupkgForbidden=@($nupkgEntries|Where-Object{$_ -match '(^|/)node_modules/|(^|/)test-results/|(^|/)\.git/|(^|/)\.github/|(^|/)frontend/src/|(^|/)core/wsl/'})
    if($nupkgForbidden.Count -ne 0){throw "FULL_PACKAGE_FORBIDDEN_CONTENT:$($nupkgForbidden -join ',')"}
}finally{$nupkg.Dispose()}

$zip=[IO.Compression.ZipFile]::OpenRead([string]$result.portableZip)
try{
    $entries=@($zip.Entries.FullName)
    foreach($required in @('Iniciar CloudOS.cmd','app/CloudOS.Bootstrap.exe','app/app/host/CloudOS.Host.exe','runtime/node.exe','runtime/cloudos-core','meta/portable-manifest.json','meta/portable-checksums.sha256')){
        if($entries -notcontains $required){throw "PORTABLE_ENTRY_MISSING:$required"}
    }
    if($entries | Where-Object {$_ -match '(^|/)node_modules/|(^|/)test-results/|\.env($|\.)|\.log$|\.go$|(^|/)go\.(mod|sum)$|(^|/)\.git/|(^|/)\.github/|(^|/)frontend/src/|(^|/)core/wsl/'}){throw 'PORTABLE_FORBIDDEN_CONTENT'}
    $portableCore=@($entries | Where-Object {$_ -eq 'runtime/cloudos-core'})
    if($portableCore.Count -ne 1){throw "PORTABLE_CLOUDOS_CORE_COUNT_INVALID:$($portableCore.Count)"}
    $launcherEntry=$zip.GetEntry('Iniciar CloudOS.cmd')
    if($null -eq $launcherEntry){throw 'PORTABLE_LAUNCHER_MISSING'}
    $reader=[IO.StreamReader]::new($launcherEntry.Open())
    try{$launcher=$reader.ReadToEnd()}finally{$reader.Dispose()}
    foreach($required in @('mkdir "%~dp0data-portable"','mkdir "%~dp0logs"','CLOUDOS_LOCAL_ROOT=%~dp0data-portable','--node "%~dp0runtime\node.exe"')){
        if($launcher.IndexOf($required,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "PORTABLE_LAUNCHER_CONTRACT_MISSING:$required"}
    }
}finally{$zip.Dispose()}
Write-Host "PRODUCTIZATION_PACKAGE_LAYOUT_OK setup=$($result.setup) portable=$($result.portableZip) coreSha256=$coreHash fullPackageContent=true provenance=true portableManifest=true"
