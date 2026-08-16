param([string]$NextVersion,[string]$ResultPath)
. (Join-Path $PSScriptRoot 'common.ps1')
if(-not $IsWindows){throw 'UPDATE_FIXTURE_WINDOWS_ONLY'}
$config=Get-CloudOSProductConfig;$paths=Get-CloudOSArtifactPaths
if([string]::IsNullOrWhiteSpace($ResultPath)){$ResultPath=Join-Path $paths.Artifacts 'package-result.json'}
$current=Get-Content -LiteralPath $ResultPath -Raw|ConvertFrom-Json
if([string]::IsNullOrWhiteSpace($NextVersion)){
    $m=[regex]::Match([string]$config.version,'^(?<prefix>.+?)(?<n>\d+)$')
    if(-not $m.Success){throw 'UPDATE_FIXTURE_VERSION_NOT_INCREMENTABLE'}
    $NextVersion=$m.Groups['prefix'].Value+([int]$m.Groups['n'].Value+1)
}
if($NextVersion -eq [string]$config.version){throw 'UPDATE_FIXTURE_VERSION_MUST_DIFFER'}
$fixture=Join-Path $paths.Artifacts "update-fixture\$($config.version)-to-$NextVersion"
$tempStage=Join-Path $paths.Artifacts "fixture-staging\$NextVersion\$($config.rid)"
Remove-Item -LiteralPath $fixture,$tempStage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $fixture,$tempStage|Out-Null
Copy-Item -Path (Join-Path ([string]$current.staging) '*') -Destination $tempStage -Recurse -Force
$releaseSource=Split-Path -Parent ([string]$current.fullPackage)
Copy-Item -Path (Join-Path $releaseSource '*') -Destination $fixture -Recurse -Force
$productPath=Join-Path $tempStage 'meta\product.json';$product=Get-Content -LiteralPath $productPath -Raw|ConvertFrom-Json
$product.version=$NextVersion;$product.channel='development';Write-CloudOSJson $product $productPath
Remove-Item -LiteralPath (Join-Path $tempStage 'meta\manifest.json'),(Join-Path $tempStage 'meta\checksums.sha256') -Force -ErrorAction SilentlyContinue
$inventory=New-CloudOSFileInventory $tempStage
$manifest=[ordered]@{schemaVersion=1;product='CloudOS';version=$NextVersion;head=(Get-CloudOSGitSha);channel='development';rid=$config.rid;signing='unsigned-development';generatedAt=[DateTimeOffset]::UtcNow.ToString('O');files=$inventory}
Write-CloudOSJson $manifest (Join-Path $tempStage 'meta\manifest.json') 40
Write-CloudOSChecksums $tempStage (Join-Path $tempStage 'meta\checksums.sha256') @('meta/checksums.sha256')
$vpk=Join-Path $paths.Tools 'vpk.exe';if(-not(Test-Path -LiteralPath $vpk)){throw 'UPDATE_FIXTURE_VPK_MISSING'}
Invoke-CloudOSExternal $vpk @('pack','--packId',[string]$config.packId,'--packVersion',$NextVersion,'--packDir',$tempStage,'--mainExe','CloudOS.Bootstrap.exe','--packTitle',[string]$config.packTitle,'--packAuthors',[string]$config.publisher,'--channel','development','--runtime',[string]$config.rid,'--shortcuts','StartMenuRoot','--outputDir',$fixture,'--noPortable')
$feedPath=Join-Path $fixture 'releases.development.json';if(-not(Test-Path -LiteralPath $feedPath)){throw 'UPDATE_FIXTURE_FEED_MISSING'}
$feed=Get-Content -LiteralPath $feedPath -Raw|ConvertFrom-Json;$assets=@($feed.Assets)
$currentAsset=$assets|Where-Object{[string]$_.Version -eq [string]$config.version -and [string]$_.Type -match '(?i)full'}|Select-Object -First 1
$nextAsset=$assets|Where-Object{[string]$_.Version -eq $NextVersion -and [string]$_.Type -match '(?i)full'}|Select-Object -First 1
if(-not $currentAsset -or -not $nextAsset){throw "UPDATE_FIXTURE_FEED_VERSIONS_MISSING:current=$($config.version):next=$NextVersion"}
$currentFull=Join-Path $fixture ([string]$currentAsset.FileName);$nextFull=Join-Path $fixture ([string]$nextAsset.FileName)
foreach($file in @($currentFull,$nextFull)){if(-not(Test-Path -LiteralPath $file)){throw "UPDATE_FIXTURE_PACKAGE_MISSING:$file"}}
$result=[ordered]@{schemaVersion=1;currentVersion=$config.version;nextVersion=$NextVersion;channel='development';directory=$fixture;feed=$feedPath;currentFullPackage=$currentFull;nextFullPackage=$nextFull;nextStaging=$tempStage}
Write-CloudOSJson $result (Join-Path $paths.Artifacts 'update-fixture-result.json')
Write-Host "PRODUCTIZATION_UPDATE_FIXTURE_OK current=$($config.version) next=$NextVersion directory=$fixture"
