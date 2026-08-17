param([string]$NextVersion,[string]$FollowingVersion,[string]$ResultPath)
. (Join-Path $PSScriptRoot 'common.ps1')
if(-not $IsWindows){throw 'UPDATE_FIXTURE_WINDOWS_ONLY'}
$config=Get-CloudOSProductConfig;$paths=Get-CloudOSArtifactPaths
if([string]::IsNullOrWhiteSpace($ResultPath)){$ResultPath=Join-Path $paths.Artifacts 'package-result.json'}
$current=Get-Content -LiteralPath $ResultPath -Raw|ConvertFrom-Json
function Get-NextFixtureVersion([string]$Version){
    $m=[regex]::Match($Version,'^(?<prefix>.+?)(?<n>\d+)$')
    if(-not $m.Success){throw "UPDATE_FIXTURE_VERSION_NOT_INCREMENTABLE:$Version"}
    return $m.Groups['prefix'].Value+([int]$m.Groups['n'].Value+1)
}
if([string]::IsNullOrWhiteSpace($NextVersion)){$NextVersion=Get-NextFixtureVersion ([string]$config.version)}
if([string]::IsNullOrWhiteSpace($FollowingVersion)){$FollowingVersion=Get-NextFixtureVersion $NextVersion}
if($NextVersion -eq [string]$config.version -or $FollowingVersion -eq $NextVersion -or $FollowingVersion -eq [string]$config.version){throw 'UPDATE_FIXTURE_VERSIONS_MUST_BE_DISTINCT'}
$fixtureRoot=Join-Path $paths.Artifacts "update-fixture\$($config.version)-to-$NextVersion-to-$FollowingVersion"
$step1=Join-Path $fixtureRoot 'step1';$step2=Join-Path $fixtureRoot 'step2'
$tempStage1=Join-Path $paths.Artifacts "fixture-staging\$NextVersion\$($config.rid)"
$tempStage2=Join-Path $paths.Artifacts "fixture-staging\$FollowingVersion\$($config.rid)"
Remove-Item -LiteralPath $fixtureRoot,$tempStage1,$tempStage2 -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $step1,$step2,$tempStage1,$tempStage2|Out-Null
Copy-Item -Path (Join-Path ([string]$current.staging) '*') -Destination $tempStage1 -Recurse -Force
$releaseSource=Split-Path -Parent ([string]$current.fullPackage)
Copy-Item -Path (Join-Path $releaseSource '*') -Destination $step1 -Recurse -Force
$vpk=Join-Path $paths.Tools 'vpk.exe';if(-not(Test-Path -LiteralPath $vpk)){throw 'UPDATE_FIXTURE_VPK_MISSING'}
function Set-StageVersion([string]$Stage,[string]$Version){
    $productPath=Join-Path $Stage 'meta\product.json';$product=Get-Content -LiteralPath $productPath -Raw|ConvertFrom-Json
    $product.version=$Version;$product.channel='development';Write-CloudOSJson $product $productPath
    Remove-Item -LiteralPath (Join-Path $Stage 'meta\manifest.json'),(Join-Path $Stage 'meta\checksums.sha256') -Force -ErrorAction SilentlyContinue
    $inventory=New-CloudOSFileInventory $Stage
    $manifest=[ordered]@{schemaVersion=1;product='CloudOS';version=$Version;head=(Get-CloudOSGitSha);channel='development';rid=$config.rid;signing='unsigned-development';generatedAt=[DateTimeOffset]::UtcNow.ToString('O');files=$inventory}
    Write-CloudOSJson $manifest (Join-Path $Stage 'meta\manifest.json') 40
    Write-CloudOSChecksums $Stage (Join-Path $Stage 'meta\checksums.sha256') @('meta/checksums.sha256')
}
function Invoke-FixturePack([string]$Stage,[string]$Version,[string]$Output){
    Invoke-CloudOSExternal $vpk @('pack','--packId',[string]$config.packId,'--packVersion',$Version,'--packDir',$Stage,'--mainExe','CloudOS.Bootstrap.exe','--packTitle',[string]$config.packTitle,'--packAuthors',[string]$config.publisher,'--channel','development','--runtime',[string]$config.rid,'--shortcuts','StartMenuRoot','--outputDir',$Output,'--noPortable')
}
Set-StageVersion $tempStage1 $NextVersion
Invoke-FixturePack $tempStage1 $NextVersion $step1
Copy-Item -Path (Join-Path $tempStage1 '*') -Destination $tempStage2 -Recurse -Force
Copy-Item -Path (Join-Path $step1 '*') -Destination $step2 -Recurse -Force
Set-StageVersion $tempStage2 $FollowingVersion
Invoke-FixturePack $tempStage2 $FollowingVersion $step2
function Get-FullAsset([string]$Directory,[string]$Version){
    $feedPath=Join-Path $Directory 'releases.development.json';if(-not(Test-Path -LiteralPath $feedPath)){throw "UPDATE_FIXTURE_FEED_MISSING:$Directory"}
    $feed=Get-Content -LiteralPath $feedPath -Raw|ConvertFrom-Json
    $asset=@($feed.Assets)|Where-Object{[string]$_.Version -eq $Version -and [string]$_.Type -match '(?i)full'}|Select-Object -First 1
    if(-not $asset){throw "UPDATE_FIXTURE_FEED_VERSION_MISSING:$Version"}
    $full=Join-Path $Directory ([string]$asset.FileName);if(-not(Test-Path -LiteralPath $full)){throw "UPDATE_FIXTURE_PACKAGE_MISSING:$full"}
    return $full
}
$currentFull=Get-FullAsset $step1 ([string]$config.version)
$nextFull=Get-FullAsset $step1 $NextVersion
$followingFull=Get-FullAsset $step2 $FollowingVersion
$result=[ordered]@{
    schemaVersion=2;currentVersion=$config.version;nextVersion=$NextVersion;followingVersion=$FollowingVersion;channel='development';
    directory=$step1;followingDirectory=$step2;feed=(Join-Path $step1 'releases.development.json');followingFeed=(Join-Path $step2 'releases.development.json');
    currentFullPackage=$currentFull;nextFullPackage=$nextFull;followingFullPackage=$followingFull;nextStaging=$tempStage1;followingStaging=$tempStage2
}
Write-CloudOSJson $result (Join-Path $paths.Artifacts 'update-fixture-result.json')
Write-Host "PRODUCTIZATION_UPDATE_FIXTURE_OK current=$($config.version) next=$NextVersion following=$FollowingVersion directory=$step1"
