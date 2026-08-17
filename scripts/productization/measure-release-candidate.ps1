param([string]$PackageResult,[string]$FixtureResult,[string]$OutputPath)
. (Join-Path $PSScriptRoot 'common.ps1')
$paths=Get-CloudOSArtifactPaths
if([string]::IsNullOrWhiteSpace($PackageResult)){$PackageResult=Join-Path $paths.Artifacts 'package-result.json'}
if([string]::IsNullOrWhiteSpace($FixtureResult)){$FixtureResult=Join-Path $paths.Artifacts 'update-fixture-result.json'}
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path $paths.Artifacts 'audit\release-candidate-metrics.json'}
foreach($required in @($PackageResult,$FixtureResult)){if(-not(Test-Path -LiteralPath $required -PathType Leaf)){throw "RC_METRICS_INPUT_MISSING:$required"}}
$package=Get-Content -LiteralPath $PackageResult -Raw|ConvertFrom-Json
$fixture=Get-Content -LiteralPath $FixtureResult -Raw|ConvertFrom-Json
function Measure-File([string]$Name,[string]$Path){if([string]::IsNullOrWhiteSpace($Path)-or -not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "RC_METRICS_FILE_MISSING:$Name"};$item=Get-Item -LiteralPath $Path;return [ordered]@{status='measured';path=$item.FullName;bytes=[int64]$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}}
$diagnosticsPath=Join-Path $paths.Artifacts 'diagnostics\CloudOSDiagnostics.zip'
$delta=@(Get-ChildItem -LiteralPath ([string]$fixture.directory) -File -Filter '*-delta.nupkg' -ErrorAction SilentlyContinue|Where-Object{$_.Name -match [regex]::Escape([string]$fixture.nextVersion)}|Sort-Object Name|Select-Object -First 1)
if($delta.Count -eq 0){$delta=@(Get-ChildItem -LiteralPath ([string]$fixture.directory) -File -Filter '*-delta.nupkg' -ErrorAction SilentlyContinue|Sort-Object Name|Select-Object -First 1)}
if($delta.Count -eq 0){throw 'RC_METRICS_UPDATE_DELTA_MISSING'}
$metrics=[ordered]@{
 schemaVersion=1;head=Get-CloudOSGitSha;measuredAt=[DateTimeOffset]::UtcNow.ToString('O');
 artifacts=[ordered]@{
  installer=(Measure-File 'installer' ([string]$package.setup));portable=(Measure-File 'portable' ([string]$package.portableZip));
  updateFull=(Measure-File 'update-full' ([string]$fixture.nextFullPackage));updateDelta=(Measure-File 'update-delta' ([string]$delta[0].FullName));diagnostics=(Measure-File 'diagnostics' $diagnosticsPath)
 };
 runtime=[ordered]@{
  startupWebOnly=[ordered]@{status='not-measured';reason='Mode Web returns after spawning the development server and exposes no readiness signal.'};
  startupFull=[ordered]@{status='not-measured';reason='Full startup requires the native interactive path; hosted CI is not a physical/visual gate.'};
  shutdown=[ordered]@{status='not-measured';reason='Hosted CI does not execute a complete interactive CloudOS startup/shutdown lifecycle.'};
  memory=[ordered]@{status='not-measured';reason='Main interactive components are not held in a representative running state by hosted CI.'}
 }
}
Write-CloudOSJson $metrics $OutputPath 30
Write-Host "PRODUCTIZATION_RC_METRICS_OK installerBytes=$($metrics.artifacts.installer.bytes) portableBytes=$($metrics.artifacts.portable.bytes) updateFullBytes=$($metrics.artifacts.updateFull.bytes) updateDeltaBytes=$($metrics.artifacts.updateDelta.bytes) diagnosticsBytes=$($metrics.artifacts.diagnostics.bytes) startupWebOnly=not-measured startupFull=not-measured shutdown=not-measured memory=not-measured"
