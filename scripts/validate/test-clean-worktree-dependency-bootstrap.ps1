[CmdletBinding()]
param([string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$head=(& git -C $root rev-parse HEAD 2>$null).Trim()
if(-not $head){throw 'WORKTREE_BOOTSTRAP_HEAD_UNRESOLVED'}
if(-not $EvidenceDirectory){$EvidenceDirectory=Join-Path $root 'test-results\dependency-worktree'}
New-Item -ItemType Directory -Force -Path $EvidenceDirectory|Out-Null
$temp=Join-Path ([IO.Path]::GetTempPath()) "cloudos-dependency-worktree-$([guid]::NewGuid().ToString('N'))"
$added=$false;$cleanupError=$null
try{
 & git -C $root worktree add --detach $temp $head
 if($LASTEXITCODE -ne 0){throw "WORKTREE_ADD_FAILED:$LASTEXITCODE"}
 $added=$true
 foreach($relative in @('node_modules','frontend/node_modules','backend/node_modules')){if(Test-Path -LiteralPath (Join-Path $temp $relative)){throw "WORKTREE_NOT_CLEAN_NODE_MODULES_PRESENT:$relative"}}
 . (Join-Path $temp 'scripts/validate/cloudos-node-dependencies.ps1')
 $before=Get-CloudOSNodeDependencyState -Root $temp
 if($before.complete){throw 'WORKTREE_PREFLIGHT_UNEXPECTEDLY_COMPLETE_WITHOUT_NODE_MODULES'}
 if($before.missing -notcontains 'directory:node_modules'){throw 'WORKTREE_PREFLIGHT_DID_NOT_DETECT_MISSING_NODE_MODULES'}
 $result=Ensure-CloudOSNodeDependencies -Root $temp -EvidenceDirectory $EvidenceDirectory -AllowInstall
 if(-not $result.complete -or -not $result.installPerformed){throw 'WORKTREE_BOOTSTRAP_DID_NOT_INSTALL'}
 $tempFull=[IO.Path]::GetFullPath($temp).TrimEnd([IO.Path]::DirectorySeparatorChar)
 foreach($name in @('tsc','vite','express','ws','dotenv')){
  $resolved=[string]$result.resolved[$name]
  if(-not $resolved){throw "WORKTREE_BINARY_NOT_RESOLVED:$name"}
  $resolvedFull=[IO.Path]::GetFullPath($resolved)
  if(-not $resolvedFull.StartsWith($tempFull,[StringComparison]::OrdinalIgnoreCase)){throw "WORKTREE_DEPENDENCY_LEAKED_FROM_OTHER_WORKTREE:${name}:$resolvedFull"}
 }
 foreach($relative in @('node_modules','frontend/node_modules','backend/node_modules')){
  $path=Join-Path $temp $relative;if(-not(Test-Path -LiteralPath $path)){continue}
  $item=Get-Item -LiteralPath $path -Force
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "NODE_MODULES_JUNCTION_FORBIDDEN:$relative"}
 }
 $status=@(& git -C $temp status --porcelain)
 if($LASTEXITCODE -ne 0){throw "WORKTREE_STATUS_FAILED:$LASTEXITCODE"}
 if($status.Count -gt 0){throw "WORKTREE_TRACKED_FILES_CHANGED:$($status -join ',')"}
 @{schemaVersion=1;head=$head;worktree=$temp;nodeModulesInitiallyAbsent=$true;rootInstallPerformed=$true;noNodeModulesJunction=$true;resolved=$result.resolved;versions=$result.versions;status='passed';timestamp=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'worktree-bootstrap-result.json') -Encoding UTF8
 Write-Host 'CLEAN_WORKTREE_DEPENDENCY_BOOTSTRAP_OK'
}finally{
 if($added -and (Test-Path -LiteralPath $temp)){
  foreach($relative in @('node_modules','frontend/node_modules','backend/node_modules')){$path=Join-Path $temp $relative;if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue}}
  & git -C $root worktree remove $temp 2>$null
  if($LASTEXITCODE -ne 0){$cleanupError="WORKTREE_REMOVE_FAILED:${LASTEXITCODE}:$temp"}
  & git -C $root worktree prune 2>$null
 }
 if($cleanupError){throw $cleanupError}
}
