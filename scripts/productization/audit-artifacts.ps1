param([string]$ResultPath,[string]$OutputPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'artifact-audit-lib.ps1')
$config=Get-CloudOSProductConfig
$paths=Get-CloudOSArtifactPaths
$head=Get-CloudOSGitSha
if([string]::IsNullOrWhiteSpace($ResultPath)){$ResultPath=Join-Path $paths.Artifacts 'package-result.json'}
if(-not(Test-Path -LiteralPath $ResultPath -PathType Leaf)){throw "ARTIFACT_AUDIT_PACKAGE_RESULT_MISSING:$ResultPath"}
$result=Get-Content -LiteralPath $ResultPath -Raw|ConvertFrom-Json
if([string]$result.head -ne $head){throw "ARTIFACT_AUDIT_HEAD_MISMATCH:package=$($result.head) current=$head"}
$stage=[IO.Path]::GetFullPath([string]$result.staging)
$stageCount=Assert-CloudOSArtifactDirectory -Root $stage -Label 'staging'

$manifestPath=Join-Path $stage 'meta\manifest.json'
$checksumsPath=Join-Path $stage 'meta\checksums.sha256'
$componentsPath=Join-Path $stage 'meta\components.json'
$supplyPath=Join-Path $stage 'meta\supply-chain.json'
foreach($required in @($manifestPath,$checksumsPath,$componentsPath,$supplyPath)){if(-not(Test-Path -LiteralPath $required -PathType Leaf)){throw "ARTIFACT_AUDIT_METADATA_MISSING:$required"}}
$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
if([string]$manifest.head -ne $head -or [string]$manifest.version -ne [string]$config.version -or [string]$manifest.channel -ne [string]$config.channel){throw 'ARTIFACT_AUDIT_MANIFEST_IDENTITY_MISMATCH'}
$manifestExpected=@(Get-ChildItem -LiteralPath $stage -File -Recurse|ForEach-Object{Get-CloudOSRelativePath $stage $_.FullName}|Where-Object{$_ -notin @('meta/manifest.json','meta/checksums.sha256')}|Sort-Object)
$manifestActual=@($manifest.files|ForEach-Object{[string]$_.path}|Sort-Object)
if(($manifestExpected -join "`n") -ne ($manifestActual -join "`n")){throw "ARTIFACT_AUDIT_MANIFEST_COVERAGE_MISMATCH:expected=$($manifestExpected.Count) actual=$($manifestActual.Count)"}
foreach($file in @($manifest.files)){
    $relative=[string]$file.path;$path=Join-Path $stage $relative.Replace('/',[IO.Path]::DirectorySeparatorChar)
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ne ([string]$file.sha256).ToLowerInvariant()){throw "ARTIFACT_AUDIT_MANIFEST_HASH_MISMATCH:$relative"}
}
$checksumCount=Assert-CloudOSChecksumsExact -Root $stage -ChecksumPath $checksumsPath -Exclude @('meta/checksums.sha256')

$components=Get-Content -LiteralPath $componentsPath -Raw|ConvertFrom-Json
if(@($components.components).Count -lt 6){throw 'ARTIFACT_AUDIT_COMPONENT_INVENTORY_TOO_SMALL'}
foreach($component in @($components.components)){
    if([string]::IsNullOrWhiteSpace([string]$component.name) -or [string]::IsNullOrWhiteSpace([string]$component.origin) -or [string]::IsNullOrWhiteSpace([string]$component.evidence)){
        throw "ARTIFACT_AUDIT_COMPONENT_ORIGIN_UNCLEAR:$($component.name)"
    }
}
$supply=Get-Content -LiteralPath $supplyPath -Raw|ConvertFrom-Json
if([string]$supply.head -ne $head -or [string]$supply.signing -ne [string]$config.signing){throw 'ARTIFACT_AUDIT_SUPPLY_CHAIN_IDENTITY_MISMATCH'}
if(@($supply.components).Count -lt 8){throw 'ARTIFACT_AUDIT_SUPPLY_CHAIN_INCOMPLETE'}
foreach($component in @($supply.components)){
    if([string]::IsNullOrWhiteSpace([string]$component.origin) -or [string]::IsNullOrWhiteSpace([string]$component.evidence)){throw "ARTIFACT_AUDIT_SUPPLY_ORIGIN_UNCLEAR:$($component.name)"}
}

$npmSbomPath=Join-Path $stage 'meta\SBOM\npm.cyclonedx.json'
$nugetHostPath=Join-Path $stage 'meta\SBOM\nuget-host.json'
$nugetBootstrapPath=Join-Path $stage 'meta\SBOM\nuget-bootstrap.json'
$goModulesPath=Join-Path $stage 'meta\SBOM\go-modules.jsonl'
foreach($required in @($npmSbomPath,$nugetHostPath,$nugetBootstrapPath,$goModulesPath)){if(-not(Test-Path -LiteralPath $required -PathType Leaf)){throw "ARTIFACT_AUDIT_SBOM_MISSING:$required"}}
$npmSbom=Get-Content -LiteralPath $npmSbomPath -Raw|ConvertFrom-Json
if([string]$npmSbom.bomFormat -ne 'CycloneDX' -or @($npmSbom.components).Count -eq 0){throw 'ARTIFACT_AUDIT_NPM_SBOM_INVALID'}
$nugetHost=Get-Content -LiteralPath $nugetHostPath -Raw|ConvertFrom-Json
$nugetBootstrap=Get-Content -LiteralPath $nugetBootstrapPath -Raw|ConvertFrom-Json
if($null -eq $nugetHost -or $null -eq $nugetBootstrap){throw 'ARTIFACT_AUDIT_NUGET_SBOM_INVALID'}
$goModulesRaw=Get-Content -LiteralPath $goModulesPath -Raw
if($goModulesRaw -notmatch '"Path"\s*:' -or $goModulesRaw -notmatch '"Version"\s*:'){throw 'ARTIFACT_AUDIT_GO_SBOM_INVALID'}

$fullPackage=[IO.Path]::GetFullPath([string]$result.fullPackage)
$portableZip=[IO.Path]::GetFullPath([string]$result.portableZip)
$setup=[IO.Path]::GetFullPath([string]$result.setup)
$nupkgEntries=Assert-CloudOSZipArchive -Path $fullPackage -Label 'velopack-nupkg'
$portableEntries=Assert-CloudOSZipArchive -Path $portableZip -Label 'portable-zip'
if(-not(Test-Path -LiteralPath $setup -PathType Leaf)){throw 'ARTIFACT_AUDIT_SETUP_MISSING'}

$tempRoot=Join-Path ([IO.Path]::GetTempPath()) "cloudos-portable-audit-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempRoot -Force|Out-Null
try{
    [IO.Compression.ZipFile]::ExtractToDirectory($portableZip,$tempRoot)
    $portableCount=Assert-CloudOSArtifactDirectory -Root $tempRoot -Label 'portable-expanded'
    $portableManifestPath=Join-Path $tempRoot 'meta\portable-manifest.json'
    $portableChecksumsPath=Join-Path $tempRoot 'meta\portable-checksums.sha256'
    foreach($required in @($portableManifestPath,$portableChecksumsPath)){if(-not(Test-Path -LiteralPath $required -PathType Leaf)){throw "PORTABLE_AUDIT_METADATA_MISSING:$required"}}
    $portableManifest=Get-Content -LiteralPath $portableManifestPath -Raw|ConvertFrom-Json
    if([string]$portableManifest.head -ne $head -or [string]$portableManifest.version -ne [string]$config.version){throw 'PORTABLE_AUDIT_IDENTITY_MISMATCH'}
    $portableExpected=@(Get-ChildItem -LiteralPath $tempRoot -File -Recurse|ForEach-Object{Get-CloudOSRelativePath $tempRoot $_.FullName}|Where-Object{$_ -notin @('meta/portable-manifest.json','meta/portable-checksums.sha256')}|Sort-Object)
    $portableActual=@($portableManifest.files|ForEach-Object{[string]$_.path}|Sort-Object)
    if(($portableExpected -join "`n") -ne ($portableActual -join "`n")){throw "PORTABLE_AUDIT_MANIFEST_COVERAGE_MISMATCH:expected=$($portableExpected.Count) actual=$($portableActual.Count)"}
    foreach($file in @($portableManifest.files)){
        $relative=[string]$file.path;$path=Join-Path $tempRoot $relative.Replace('/',[IO.Path]::DirectorySeparatorChar)
        $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if($actual -ne ([string]$file.sha256).ToLowerInvariant()){throw "PORTABLE_AUDIT_MANIFEST_HASH_MISMATCH:$relative"}
    }
    $portableChecksumCount=Assert-CloudOSChecksumsExact -Root $tempRoot -ChecksumPath $portableChecksumsPath -Exclude @('meta/portable-checksums.sha256')
}finally{Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue}

$artifactRows=@()
foreach($pair in @(@('setup',$setup),@('fullPackage',$fullPackage),@('portableZip',$portableZip))){
    $file=Get-Item -LiteralPath $pair[1]
    $artifactRows+=[pscustomobject]@{name=$pair[0];file=$file.Name;size=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path $paths.Artifacts 'audit\artifact-audit.json'}
$report=[ordered]@{
    schemaVersion=1;head=$head;version=$config.version;channel=$config.channel;rid=$config.rid;signing=$config.signing;
    auditedAt=[DateTimeOffset]::UtcNow.ToString('O');status='passed';
    policy=[ordered]@{sourceTree='rejected';nodeModules='rejected';sensitiveFiles='rejected';highConfidenceSecrets='rejected';checksums='exact-coverage';componentOrigins='required'};
    counts=[ordered]@{stagingFiles=$stageCount;stagingChecksums=$checksumCount;nupkgEntries=$nupkgEntries;portableEntries=$portableEntries;portableFiles=$portableCount;portableChecksums=$portableChecksumCount;npmComponents=@($npmSbom.components).Count;supplyComponents=@($supply.components).Count};
    artifacts=$artifactRows
}
Write-CloudOSJson $report $OutputPath 20
Write-Host "PRODUCTIZATION_ARTIFACT_AUDIT_OK head=$head report=$OutputPath portableEntries=$portableEntries nupkgEntries=$nupkgEntries"
