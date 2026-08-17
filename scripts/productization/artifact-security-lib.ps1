Set-StrictMode -Version Latest
function Get-CloudOSSecurityRelativePath{param([string]$Root,[string]$Path);return [IO.Path]::GetRelativePath($Root,$Path).Replace('\','/')}
function Get-CloudOSSecuritySourcePath{
 param([string]$Relative,$BuildResult)
 if($Relative -match '^app/host/(?<rest>.+)$'){return Join-Path ([string]$BuildResult.host) $Matches.rest}
 if($Relative -match '^agent/backend/(?<rest>.+)$'){return Join-Path ([string]$BuildResult.backend) $Matches.rest}
 if($Relative -match '^web/(?<rest>.+)$'){return Join-Path ([string]$BuildResult.frontend) $Matches.rest}
 $bootstrapCandidate=Join-Path ([string]$BuildResult.bootstrap) ($Relative.Replace('/','\'))
 if(Test-Path -LiteralPath $bootstrapCandidate -PathType Leaf){return $bootstrapCandidate}
 return $null
}
function Find-CloudOSSecurityRepoRoot{
 param([string]$BuildResultPath)
 $cursor=Split-Path -Parent ([IO.Path]::GetFullPath($BuildResultPath))
 for($i=0;$i -lt 8 -and -not [string]::IsNullOrWhiteSpace($cursor);$i++){
  if(Test-Path -LiteralPath (Join-Path $cursor 'package.json') -PathType Leaf){return $cursor}
  $parent=Split-Path -Parent $cursor;if([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor){break};$cursor=$parent
 }
 return $null
}
function Get-CloudOSPrivateWorkspaceNames{
 param([string]$BuildResultPath)
 $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$repoRoot=Find-CloudOSSecurityRepoRoot $BuildResultPath
 if([string]::IsNullOrWhiteSpace($repoRoot)){return @($names)}
 try{
  $rootPackage=Get-Content -LiteralPath (Join-Path $repoRoot 'package.json') -Raw|ConvertFrom-Json
  if($rootPackage.private -ne $true){return @($names)}
  if(-not [string]::IsNullOrWhiteSpace([string]$rootPackage.name)){[void]$names.Add([string]$rootPackage.name)}
  $workspaceEntries=New-Object System.Collections.Generic.List[string];$workspacesProperty=$rootPackage.PSObject.Properties['workspaces']
  if($workspacesProperty){
   $workspaceValue=$workspacesProperty.Value
   if($workspaceValue -is [string]){$workspaceEntries.Add([string]$workspaceValue)}
   elseif($workspaceValue -is [Collections.IEnumerable] -and $workspaceValue -isnot [pscustomobject]){foreach($entry in $workspaceValue){if($entry){$workspaceEntries.Add([string]$entry)}}}
   elseif($workspaceValue){$packagesProperty=$workspaceValue.PSObject.Properties['packages'];if($packagesProperty){foreach($entry in @($packagesProperty.Value)){if($entry){$workspaceEntries.Add([string]$entry)}}}}
  }
  foreach($workspace in $workspaceEntries.ToArray()){
   $workspaceDirs=@();$candidate=Join-Path $repoRoot $workspace
   if($workspace.IndexOfAny([char[]]'*?[') -ge 0){$workspaceDirs=@(Get-ChildItem -Path $candidate -Directory -ErrorAction SilentlyContinue)}elseif(Test-Path -LiteralPath $candidate -PathType Container){$workspaceDirs=@(Get-Item -LiteralPath $candidate)}
   foreach($directory in $workspaceDirs){
    $packagePath=Join-Path $directory.FullName 'package.json';if(-not(Test-Path -LiteralPath $packagePath -PathType Leaf)){continue};$package=Get-Content -LiteralPath $packagePath -Raw|ConvertFrom-Json;if($package.private -ne $true){continue};[void]$names.Add($directory.Name);if(-not [string]::IsNullOrWhiteSpace([string]$package.name)){[void]$names.Add([string]$package.name)}
   }
  }
 }catch{return @($names)}
 return @($names)
}
function Test-CloudOSArtifactSecurity{
 param([string]$Staging,[string]$ManifestPath,[string]$ComponentsPath,[string]$SupplyChainPath,[string]$ArtifactAuditPath,[string]$BuildResultPath)
 $errors=New-Object System.Collections.Generic.List[string];foreach($required in @($Staging,$ManifestPath,$ComponentsPath,$SupplyChainPath,$ArtifactAuditPath,$BuildResultPath)){if(-not(Test-Path -LiteralPath $required)){throw "ARTIFACT_SECURITY_INPUT_MISSING:$required"}}
 $manifest=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json;$components=Get-Content -LiteralPath $ComponentsPath -Raw|ConvertFrom-Json;$supply=Get-Content -LiteralPath $SupplyChainPath -Raw|ConvertFrom-Json;$audit=Get-Content -LiteralPath $ArtifactAuditPath -Raw|ConvertFrom-Json;$build=Get-Content -LiteralPath $BuildResultPath -Raw|ConvertFrom-Json
 $privateWorkspaceNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);foreach($name in @(Get-CloudOSPrivateWorkspaceNames $BuildResultPath)){if(-not [string]::IsNullOrWhiteSpace([string]$name)){[void]$privateWorkspaceNames.Add([string]$name)}}
 if($manifest.schemaVersion -ne 1){$errors.Add('manifest-schema')};if($components.schemaVersion -ne 2){$errors.Add('components-schema')};if($supply.schemaVersion -ne 1){$errors.Add('supply-chain-schema')};if(-not $audit){$errors.Add('artifact-audit-invalid')}
 $manifestFiles=@($manifest.files);$pathSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($entry in $manifestFiles){
  $relative=[string]$entry.path;if([string]::IsNullOrWhiteSpace($relative) -or -not $pathSet.Add($relative)){$errors.Add("duplicate:$relative");continue};$segments=$relative -split '/';if($segments|Where-Object{$_.StartsWith('.')}){$errors.Add("hidden-path:$relative")};$full=Join-Path $Staging ($relative.Replace('/','\'));if(-not(Test-Path -LiteralPath $full -PathType Leaf)){$errors.Add("missing:$relative");continue};$file=Get-Item -LiteralPath $full -Force;if(($file.Attributes -band [IO.FileAttributes]::Hidden) -ne 0){$errors.Add("hidden-attribute:$relative")};if([int64]$entry.size -ne $file.Length){$errors.Add("size:$relative")};if($file.Length -le 0 -and $file.Extension.ToLowerInvariant() -in @('.exe','.dll')){$errors.Add("binary-empty:$relative")};$actual=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant();if($actual -ne ([string]$entry.sha256).ToLowerInvariant()){$errors.Add("hash:$relative")}
  if($relative -eq 'runtime/cloudos-core'){if($actual -ne ([string]$build.coreSha256).ToLowerInvariant()){$errors.Add('origin-hash:runtime/cloudos-core')};continue}
  if($relative -eq 'runtime/node.exe'){$node=@($components.components|Where-Object{[string]$_.path -eq 'runtime/node.exe'})|Select-Object -First 1;if(-not $node -or [string]::IsNullOrWhiteSpace([string]$node.origin) -or $actual -ne ([string]$node.sha256).ToLowerInvariant()){$errors.Add('origin-missing:runtime/node.exe')};continue}
  if($relative -in @('runtime/NODE-LICENSE.txt','README-UNSIGNED.txt') -or $relative.StartsWith('meta/')){continue}
  $source=Get-CloudOSSecuritySourcePath $relative $build;if($source){$sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant();if($sourceHash -ne $actual){$errors.Add("origin-hash:$relative")}}else{$errors.Add("uninventoried:$relative")}
 }
 $actualFiles=@(Get-ChildItem -LiteralPath $Staging -File -Recurse -Force);$artifactRoot=Split-Path -Parent $ManifestPath;$globalChecksums=Join-Path $artifactRoot 'checksums.sha256'
 foreach($file in $actualFiles){
  $relative=Get-CloudOSSecurityRelativePath $Staging $file.FullName
  if($pathSet.Contains($relative)){continue}
  if($relative -eq 'meta/manifest.json'){$left=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant();$right=(Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant();if($left -ne $right){$errors.Add('generated-meta-hash:meta/manifest.json')};continue}
  if($relative -eq 'meta/checksums.sha256'){if(-not(Test-Path -LiteralPath $globalChecksums -PathType Leaf)){$errors.Add('generated-meta-origin-missing:meta/checksums.sha256')}else{$left=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant();$right=(Get-FileHash -LiteralPath $globalChecksums -Algorithm SHA256).Hash.ToLowerInvariant();if($left -ne $right){$errors.Add('generated-meta-hash:meta/checksums.sha256')}};continue}
  $errors.Add("extra:$relative")
 }
 foreach($component in @($components.components)){if([string]::IsNullOrWhiteSpace([string]$component.name)){$errors.Add('component-name-missing')};if([string]::IsNullOrWhiteSpace([string]$component.path)){$errors.Add("component-path-missing:$($component.name)")};if([string]::IsNullOrWhiteSpace([string]$component.origin)){$errors.Add("component-origin-missing:$($component.name)")};if([string]::IsNullOrWhiteSpace([string]$component.evidence)){$errors.Add("component-evidence-missing:$($component.name)")};$origin=[string]$component.origin;if($origin -and -not(@($supply.components|Where-Object{[string]$_.origin -eq $origin}).Count -gt 0)){$errors.Add("component-not-in-supply-chain:$($component.name)")}}
 foreach($component in @($supply.components)){if([string]::IsNullOrWhiteSpace([string]$component.origin)){$errors.Add("supply-origin-missing:$($component.name)")};if([string]::IsNullOrWhiteSpace([string]$component.evidence)){$errors.Add("supply-evidence-missing:$($component.name)")};if([string]::IsNullOrWhiteSpace([string]$component.licenseEvidence)){$errors.Add("license-missing:$($component.name)")}}
 foreach($licenseFile in @('runtime/NODE-LICENSE.txt','meta/licenses/THIRD-PARTY-NOTICES.txt')){if(-not(Test-Path -LiteralPath (Join-Path $Staging ($licenseFile.Replace('/','\'))) -PathType Leaf)){$errors.Add("license-file-missing:$licenseFile")}};foreach($evidence in @('meta/SBOM/npm.cyclonedx.json','meta/SBOM/nuget-host.json','meta/SBOM/nuget-bootstrap.json','meta/SBOM/go-modules.jsonl')){if(-not(Test-Path -LiteralPath (Join-Path $Staging ($evidence.Replace('/','\'))) -PathType Leaf)){$errors.Add("inventory-evidence-missing:$evidence")}}
 $npmSbomPath=Join-Path $Staging 'meta\SBOM\npm.cyclonedx.json';if(Test-Path -LiteralPath $npmSbomPath){try{$npmSbom=Get-Content -LiteralPath $npmSbomPath -Raw|ConvertFrom-Json;$componentsProperty=$npmSbom.PSObject.Properties['components'];if($componentsProperty){foreach($component in @($componentsProperty.Value)){$licensesProperty=$component.PSObject.Properties['licenses'];if(-not $licensesProperty -or @($licensesProperty.Value).Count -eq 0){$componentName=[string]$component.name;if(-not $privateWorkspaceNames.Contains($componentName)){$errors.Add("npm-license-missing:$componentName@$($component.version)")}}}}}catch{$errors.Add('npm-sbom-invalid')}}
 $binaryFiles=@($actualFiles|Where-Object{$_.Extension.ToLowerInvariant() -in @('.exe','.dll')});foreach($file in $binaryFiles){$relative=Get-CloudOSSecurityRelativePath $Staging $file.FullName;$source=Get-CloudOSSecuritySourcePath $relative $build;$known=($relative -eq 'runtime/node.exe') -or ($source -and (Test-Path -LiteralPath $source -PathType Leaf));if(-not $known){$errors.Add("unexpected-binary:$relative")}}
 $unique=@($errors|Sort-Object -Unique);return [pscustomobject]@{ok=($unique.Count -eq 0);errors=$unique;manifestFiles=$manifestFiles.Count;actualFiles=$actualFiles.Count;binaries=$binaryFiles.Count;privateWorkspacePackages=$privateWorkspaceNames.Count;duplicatePaths=@($unique|Where-Object{$_ -like 'duplicate:*'}).Count;hiddenFiles=@($unique|Where-Object{$_ -like 'hidden-*'}).Count;hashMismatches=@($unique|Where-Object{$_ -like 'hash:*' -or $_ -like 'origin-hash:*' -or $_ -like 'generated-meta-hash:*'}).Count;missingOrigins=@($unique|Where-Object{$_ -like '*origin-missing:*'}).Count;missingLicenses=@($unique|Where-Object{$_ -like '*license-missing:*'}).Count;uninventoried=@($unique|Where-Object{$_ -like 'uninventoried:*' -or $_ -like 'extra:*' -or $_ -like 'unexpected-binary:*'}).Count;anomalousSizes=@($unique|Where-Object{$_ -like 'size:*' -or $_ -like 'binary-empty:*'}).Count}
}
