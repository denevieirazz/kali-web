param([string]$PackageResult,[string]$FixtureResult,[string]$OutputPath)
. (Join-Path $PSScriptRoot 'common.ps1')
$paths=Get-CloudOSArtifactPaths
if([string]::IsNullOrWhiteSpace($PackageResult)){$PackageResult=Join-Path $paths.Artifacts 'package-result.json'}
if([string]::IsNullOrWhiteSpace($FixtureResult)){$FixtureResult=Join-Path $paths.Artifacts 'update-fixture-result.json'}
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path $paths.Artifacts 'audit\release-candidate-metrics.json'}
foreach($required in @($PackageResult,$FixtureResult)){if(-not(Test-Path -LiteralPath $required -PathType Leaf)){throw "RC_METRICS_INPUT_MISSING:$required"}}
$package=Get-Content -LiteralPath $PackageResult -Raw|ConvertFrom-Json
$fixture=Get-Content -LiteralPath $FixtureResult -Raw|ConvertFrom-Json
function Measure-File([string]$Name,[string]$Path){
    if([string]::IsNullOrWhiteSpace($Path)-or -not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "RC_METRICS_FILE_MISSING:$Name"}
    $item=Get-Item -LiteralPath $Path
    return [ordered]@{status='measured';path=$item.FullName;bytes=[int64]$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
function Not-Measured([string]$Reason){return [ordered]@{status='not-measured';reason=$Reason}}
$diagnosticsPath=Join-Path $paths.Artifacts 'diagnostics\CloudOSDiagnostics.zip'
$delta=Get-ChildItem -LiteralPath ([string]$fixture.directory) -File -Filter '*-delta.nupkg' -ErrorAction SilentlyContinue|Where-Object{$_.Name -match [regex]::Escape([string]$fixture.nextVersion)}|Sort-Object Name|Select-Object -First 1
if(-not $delta){$delta=Get-ChildItem -LiteralPath ([string]$fixture.directory) -File -Filter '*-delta.nupkg' -ErrorAction SilentlyContinue|Sort-Object Name|Select-Object -First 1}
$deltaMetric=if($delta){Measure-File 'update-delta' $delta.FullName}else{Not-Measured 'Velopack did not generate a delta package for this fixture.'}
$metrics=[ordered]@{
    schemaVersion=2
    head=Get-CloudOSGitSha
    measuredAt=[DateTimeOffset]::UtcNow.ToString('O')
    artifacts=[ordered]@{
        installer=Measure-File 'installer' ([string]$package.setup)
        portable=Measure-File 'portable' ([string]$package.portableZip)
        updateFull=Measure-File 'update-full' ([string]$fixture.nextFullPackage)
        updateDelta=$deltaMetric
        diagnostics=Measure-File 'diagnostics' $diagnosticsPath
    }
    runtime=[ordered]@{
        startupWebOnly=Not-Measured 'The real Bootstrap WebOnly path is interactive; hosted CI does not provide a representative user-readiness signal.'
        startupFull=Not-Measured 'The real Full path supervises the native Host; hosted CI is not the physical or visual gate.'
        shutdown=Not-Measured 'Hosted CI does not execute a representative interactive startup-to-shutdown lifecycle.'
        memory=Not-Measured 'Build and test processes are not representative of runtime memory for the main interactive components.'
    }
}
Write-CloudOSJson $metrics $OutputPath 30
$deltaText=if($metrics.artifacts.updateDelta.status -eq 'measured'){$metrics.artifacts.updateDelta.bytes}else{'not-measured'}
Write-Host "PRODUCTIZATION_RC_METRICS_OK installerBytes=$($metrics.artifacts.installer.bytes) portableBytes=$($metrics.artifacts.portable.bytes) updateFullBytes=$($metrics.artifacts.updateFull.bytes) updateDeltaBytes=$deltaText diagnosticsBytes=$($metrics.artifacts.diagnostics.bytes) startupWebOnly=not-measured startupFull=not-measured shutdown=not-measured memory=not-measured"
