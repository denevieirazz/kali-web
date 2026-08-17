param()
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Get-CloudOSRepoRoot;$path=Join-Path $root 'productization\channels.json'
if(-not(Test-Path -LiteralPath $path)){throw 'CHANNEL_MATRIX_MISSING'}
try{$matrix=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}catch{throw 'CHANNEL_MATRIX_JSON_INVALID'}
if($matrix.schemaVersion -ne 1){throw 'CHANNEL_MATRIX_SCHEMA_INVALID'}
$names=@($matrix.channels.PSObject.Properties.Name)
foreach($required in @('development','preview','stable')){if($names -notcontains $required){throw "CHANNEL_MATRIX_REQUIRED_CHANNEL_MISSING:$required"}}
if($matrix.channels.development.allowLocalSource -ne $true -or $matrix.channels.development.requiresAuthenticode -ne $false){throw 'CHANNEL_MATRIX_DEVELOPMENT_POLICY_INVALID'}
foreach($name in @('preview','stable')){if($matrix.channels.$name.requiresAuthenticode -ne $true -or $matrix.channels.$name.allowLocalSource -ne $false){throw "CHANNEL_MATRIX_SIGNED_CHANNEL_POLICY_INVALID:$name"}}
$allowed=@($matrix.transitions|ForEach-Object{"$($_.from)->$($_.to)"})
foreach($transition in @('development->development','development->preview','preview->stable','stable->stable')){if($allowed -notcontains $transition){throw "CHANNEL_MATRIX_REQUIRED_TRANSITION_MISSING:$transition"}}
foreach($forbidden in @('development->stable','stable->preview','stable->development','preview->development')){if($allowed -contains $forbidden){throw "CHANNEL_MATRIX_FORBIDDEN_TRANSITION_PRESENT:$forbidden"}}
$service=Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.Bootstrap\DistributionUpdateService.cs') -Raw
$store=Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.Bootstrap\DistributionStateStore.cs') -Raw
$window=Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.Bootstrap\UpdateWindow.cs') -Raw
$project=Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.Bootstrap\CloudOS.Bootstrap.csproj') -Raw
if($service -notmatch 'DistributionChannelPolicy\.Load' -or $service -notmatch 'AssertTransition' -or $service -notmatch 'AssertVersionDirection'){throw 'CHANNEL_MATRIX_NOT_BOUND_TO_UPDATER'}
if($store -notmatch 'ConfirmedChannel' -or $store -notmatch 'AssertPackageChannel'){throw 'CHANNEL_MATRIX_NOT_BOUND_TO_STATE'}
if($window -notmatch 'AssertPackageChannel' -or $window -notmatch 'CheckAsync\(_source,_channel,_metadata,_stateStore\)'){throw 'CHANNEL_MATRIX_NOT_BOUND_TO_UI_FLOW'}
if($project -notmatch 'productization\\channels\.json' -or $project -notmatch 'meta\\channels\.json'){throw 'CHANNEL_MATRIX_NOT_PACKAGED'}
Write-Host 'PRODUCTIZATION_CHANNEL_MATRIX_OK development=true preview=true stable=true silentSwitchBlocked=true stableOriginFailClosed=true packaged=true'
