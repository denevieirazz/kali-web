Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'PHYSICAL_VALIDATION_WINDOWS_ONLY'}
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Get-CloudOSRepoRoot;$head=Get-CloudOSGitSha;$started=[DateTimeOffset]::Now
Push-Location $root
try{$branch=(& git branch --show-current|Out-String).Trim()}finally{Pop-Location}
if($branch -ne 'productization/cloudos-distribution-batch-2'){throw "PHYSICAL_VALIDATION_BRANCH_MISMATCH:$branch"}
function Snapshot-Db{$path=Join-Path $env:LOCALAPPDATA 'CloudOS\data\cloudos.json';if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return [pscustomobject]@{present=$false;size=0;sha256=$null}};$item=Get-Item -LiteralPath $path;return [pscustomobject]@{present=$true;size=$item.Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}}
function Snapshot-Wsl{$out=[ordered]@{};foreach($item in @(@('version','--version'),@('status','--status'),@('list','--list','--verbose'))){$name=$item[0];$args=$item[1..($item.Count-1)];try{$out[$name]=((& wsl.exe @args 2>&1|Out-String).Trim())}catch{$out[$name]=($_.Exception.Message)}};return [pscustomobject]$out}
function Wsl-Identity($Snapshot){$text=[string]$Snapshot.list;return @(($text -split "`r?`n")|ForEach-Object{($_ -replace '^\s*\*?\s*','').Trim()}|Where-Object{$_ -and $_ -notmatch '^(NAME|NOME)\s+'}|ForEach-Object{if($_ -match '^(?<name>.+?)\s+(Running|Stopped|Executando|Parado)\s+(?<version>\d+)\s*$'){"$($Matches.name.Trim())|$($Matches.version)"}else{$_}}|Sort-Object)}
function Snapshot-Processes{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name -like 'CloudOS*' -or ($_.ExecutablePath -and $_.ExecutablePath -match '(?i)CloudOS')}|ForEach-Object{[pscustomobject]@{pid=$_.ProcessId;name=$_.Name;path=$_.ExecutablePath}})}
$dbBefore=Snapshot-Db;$wslBefore=Snapshot-Wsl;$processBefore=Snapshot-Processes;$innerError=$null
try{& (Join-Path $PSScriptRoot 'validate-distribution.ps1')}catch{$innerError=$_}
$base=Join-Path $root "test-results\productization-batch-2\$head";$resultDir=$null
if(Test-Path -LiteralPath $base){$resultDir=(Get-ChildItem -LiteralPath $base -Directory|Where-Object{$_.LastWriteTime -ge $started.LocalDateTime.AddMinutes(-1)}|Sort-Object LastWriteTime -Descending|Select-Object -First 1).FullName}
if([string]::IsNullOrWhiteSpace($resultDir)){throw 'PHYSICAL_VALIDATION_RESULT_DIRECTORY_NOT_FOUND'}
$dbAfter=Snapshot-Db;$wslAfter=Snapshot-Wsl;$processAfter=Snapshot-Processes;$steps=@();$legacyResult=$null
$stepsPath=Join-Path $resultDir 'steps.json';if(Test-Path -LiteralPath $stepsPath){$steps=@(Get-Content -LiteralPath $stepsPath -Raw|ConvertFrom-Json)}
$legacyPath=Join-Path $resultDir 'result.json';if(Test-Path -LiteralPath $legacyPath){$legacyResult=Get-Content -LiteralPath $legacyPath -Raw|ConvertFrom-Json}
$screenshotDir=Join-Path $resultDir 'screenshots';New-Item -ItemType Directory -Force -Path $screenshotDir|Out-Null
$screenshots=@(Get-ChildItem -LiteralPath $screenshotDir -File -ErrorAction SilentlyContinue|Sort-Object Name|ForEach-Object{[IO.Path]::GetRelativePath($resultDir,$_.FullName).Replace('\','/')})
$logs=@(Get-ChildItem -LiteralPath $resultDir -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Extension -in @('.log','.txt')}|ForEach-Object{[IO.Path]::GetRelativePath($resultDir,$_.FullName).Replace('\','/')}|Sort-Object -Unique)
$paths=Get-CloudOSArtifactPaths;$artifacts=New-Object System.Collections.Generic.List[object];foreach($candidate in @((Join-Path $paths.Artifacts 'package-result.json'),(Join-Path $paths.Artifacts 'update-fixture-result.json'))){if(Test-Path -LiteralPath $candidate){$artifacts.Add([pscustomobject]@{path=$candidate;sha256=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()})}}
foreach($file in Get-ChildItem -LiteralPath $resultDir -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Extension -in @('.zip','.exe')}){$artifacts.Add([pscustomobject]@{path=[IO.Path]::GetRelativePath($resultDir,$file.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()})}
$config=Get-CloudOSProductConfig;$dbChanged=([string]$dbBefore.sha256 -ne [string]$dbAfter.sha256);$wslChanged=((Wsl-Identity $wslBefore)-join "`n") -ne ((Wsl-Identity $wslAfter)-join "`n");$orphans=@($processAfter|Where-Object{$_.path -and $_.path -match [regex]::Escape($resultDir)}).Count
$status=if($innerError -or $dbChanged -or $wslChanged){'failed'}elseif($legacyResult -and $legacyResult.status -eq 'passed'){'passed'}else{'incomplete'}
$validation=[ordered]@{schemaVersion=1;status=$status;physicalInteractive=$true;visualValidation=$(if($legacyResult -and $legacyResult.visualConfirmation){[string]$legacyResult.visualConfirmation}else{'not-completed'});head=$head;executionId=$(Split-Path $resultDir -Leaf);resultDirectory=$resultDir;results=$steps;screenshots=$screenshots;logs=$logs;artifacts=@($artifacts);versions=[ordered]@{product=$config.product;version=$config.version;channel=$config.channel;rid=$config.rid;head=$head};database=[ordered]@{before=$dbBefore;after=$dbAfter;changed=$dbChanged};wsl=[ordered]@{before=$wslBefore;after=$wslAfter;identityChanged=$wslChanged};processes=[ordered]@{before=$processBefore;after=$processAfter;orphans=$orphans};failure=$(if($innerError){[ordered]@{type=$innerError.Exception.GetType().Name;message=$innerError.Exception.Message}}else{$null})}
$validation|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $resultDir 'validation.json') -Encoding utf8
Write-Host "explorer `"$resultDir`""
try{Start-Process explorer.exe -ArgumentList @($resultDir)|Out-Null}catch{}
if($innerError){throw $innerError.Exception};if($dbChanged){throw 'PHYSICAL_REAL_DATABASE_CHANGED'};if($wslChanged){throw 'PHYSICAL_WSL_IDENTITY_CHANGED'};if($status -ne 'passed'){throw "PHYSICAL_VALIDATION_INCOMPLETE:$status"}
