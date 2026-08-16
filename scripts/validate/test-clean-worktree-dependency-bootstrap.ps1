[CmdletBinding()]
param([string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$head=(& git -C $root rev-parse HEAD 2>$null).Trim()
if(-not $head){throw 'WORKTREE_BOOTSTRAP_HEAD_UNRESOLVED'}
if(-not $EvidenceDirectory){$EvidenceDirectory=Join-Path $root 'test-results\dependency-worktree'}
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory,(Get-Location).Path)
New-Item -ItemType Directory -Force -Path $EvidenceDirectory|Out-Null

$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
$temp=Join-Path $tempRoot "cloudos-dependency-worktree-$([guid]::NewGuid().ToString('N'))"
$tempFull=[IO.Path]::GetFullPath($temp).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
$added=$false
$cleanupError=$null
$trackedClean=$false

function Assert-OwnedTemporaryWorktree {
 param([Parameter(Mandatory)][string]$Path)
 $full=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
 $prefix="$tempRoot$([IO.Path]::DirectorySeparatorChar)cloudos-dependency-worktree-"
 if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "UNSAFE_WORKTREE_CLEANUP_PATH:$full"}
 if(-not(Test-Path -LiteralPath $full)){return $full}
 $top=(& git -C $full rev-parse --show-toplevel 2>$null).Trim()
 if($LASTEXITCODE -ne 0){throw "WORKTREE_OWNERSHIP_REPO_UNRESOLVED:$full"}
 $topFull=[IO.Path]::GetFullPath($top).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
 if($topFull -ne $full){throw "WORKTREE_OWNERSHIP_ROOT_MISMATCH:expected=$full:actual=$topFull"}
 $actualHead=(& git -C $full rev-parse HEAD 2>$null).Trim()
 if($LASTEXITCODE -ne 0 -or $actualHead -ne $head){throw "WORKTREE_OWNERSHIP_HEAD_MISMATCH:expected=$head:actual=$actualHead"}
 return $full
}

try{
 & git -C $root worktree add --detach $temp $head
 if($LASTEXITCODE -ne 0){throw "WORKTREE_ADD_FAILED:$LASTEXITCODE"}
 $added=$true
 [void](Assert-OwnedTemporaryWorktree $temp)

 foreach($relative in @('node_modules','frontend/node_modules','backend/node_modules')){
  if(Test-Path -LiteralPath (Join-Path $temp $relative)){throw "WORKTREE_NOT_CLEAN_NODE_MODULES_PRESENT:$relative"}
 }

 . (Join-Path $temp 'scripts/validate/cloudos-node-dependencies.ps1')
 $before=Get-CloudOSNodeDependencyState -Root $temp
 if($before.complete){throw 'WORKTREE_PREFLIGHT_UNEXPECTEDLY_COMPLETE_WITHOUT_NODE_MODULES'}
 if($before.missing -notcontains 'directory:node_modules'){throw 'WORKTREE_PREFLIGHT_DID_NOT_DETECT_MISSING_NODE_MODULES'}

 $result=Ensure-CloudOSNodeDependencies -Root $temp -EvidenceDirectory $EvidenceDirectory -AllowInstall
 if(-not $result.complete -or -not $result.installPerformed){throw 'WORKTREE_BOOTSTRAP_DID_NOT_INSTALL'}

 foreach($name in @('tsc','vite','express','ws','dotenv')){
  $resolved=[string]$result.resolved[$name]
  if(-not $resolved){throw "WORKTREE_BINARY_NOT_RESOLVED:$name"}
  $resolvedFull=[IO.Path]::GetFullPath($resolved)
  if(-not $resolvedFull.StartsWith($tempFull,[StringComparison]::OrdinalIgnoreCase)){
   throw "WORKTREE_DEPENDENCY_LEAKED_FROM_OTHER_WORKTREE:${name}:$resolvedFull"
  }
 }

 foreach($relative in @('node_modules','frontend/node_modules','backend/node_modules')){
  $path=Join-Path $temp $relative
  if(-not(Test-Path -LiteralPath $path)){continue}
  $item=Get-Item -LiteralPath $path -Force
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "NODE_MODULES_JUNCTION_FORBIDDEN:$relative"}
 }

 $status=@(& git -C $temp status --porcelain)
 if($LASTEXITCODE -ne 0){throw "WORKTREE_STATUS_FAILED:$LASTEXITCODE"}
 if($status.Count -gt 0){throw "WORKTREE_TRACKED_FILES_CHANGED:$($status -join ',')"}
 $trackedClean=$true

 @{schemaVersion=1;head=$head;worktree=$temp;nodeModulesInitiallyAbsent=$true;rootInstallPerformed=$true;noNodeModulesJunction=$true;resolved=$result.resolved;versions=$result.versions;status='passed';timestamp=(Get-Date).ToUniversalTime().ToString('o')}|
  ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'worktree-bootstrap-result.json') -Encoding UTF8
 Write-Host 'CLEAN_WORKTREE_DEPENDENCY_BOOTSTRAP_OK'
}finally{
 if($added -and (Test-Path -LiteralPath $temp)){
  $cleanupLog=Join-Path $EvidenceDirectory 'worktree-cleanup.log'
  try{
   [void](Assert-OwnedTemporaryWorktree $temp)
   $normalOutput=@(& git -C $root worktree remove $temp 2>&1)
   $normalExit=$LASTEXITCODE
   @("normal-exit=$normalExit")+$normalOutput|Set-Content -LiteralPath $cleanupLog -Encoding UTF8

   if($normalExit -ne 0 -and (Test-Path -LiteralPath $temp)){
    [void](Assert-OwnedTemporaryWorktree $temp)
    $trackedStatus=@(& git -C $temp status --porcelain --untracked-files=no 2>&1)
    $statusExit=$LASTEXITCODE
    Add-Content -LiteralPath $cleanupLog -Value "tracked-status-exit=$statusExit" -Encoding UTF8
    Add-Content -LiteralPath $cleanupLog -Value $trackedStatus -Encoding UTF8
    if($statusExit -ne 0){throw "WORKTREE_CLEANUP_STATUS_FAILED:$statusExit:log=$cleanupLog"}
    if($trackedStatus.Count -gt 0 -or -not $trackedClean){throw "WORKTREE_FORCE_REMOVE_REFUSED_TRACKED_CHANGES:log=$cleanupLog"}

    Start-Sleep -Milliseconds 500
    $forceOutput=@(& git -C $root worktree remove --force $temp 2>&1)
    $forceExit=$LASTEXITCODE
    Add-Content -LiteralPath $cleanupLog -Value "force-exit=$forceExit" -Encoding UTF8
    Add-Content -LiteralPath $cleanupLog -Value $forceOutput -Encoding UTF8
    if($forceExit -ne 0){throw "WORKTREE_REMOVE_FAILED:${forceExit}:$temp:log=$cleanupLog:error=$($forceOutput -join ' | ')"}
   }
  }catch{
   $cleanupError=$_.Exception.Message
  }finally{
   $pruneOutput=@(& git -C $root worktree prune 2>&1)
   Add-Content -LiteralPath $cleanupLog -Value $pruneOutput -Encoding UTF8 -ErrorAction SilentlyContinue
  }
 }
 if($cleanupError){throw $cleanupError}
}
