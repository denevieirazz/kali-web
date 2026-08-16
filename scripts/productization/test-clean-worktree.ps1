. (Join-Path $PSScriptRoot 'common.ps1')
$root=Get-CloudOSRepoRoot
$head=Get-CloudOSGitSha
$temp=Join-Path ([IO.Path]::GetTempPath()) "cloudos-product-worktree-$([Guid]::NewGuid().ToString('N'))"
$primaryError=$null;$cleanupError=$null;$safeToForce=$false
try{
    Push-Location $root
    try{& git worktree add --detach $temp $head;if($LASTEXITCODE -ne 0){throw 'PRODUCT_WORKTREE_ADD_FAILED'}}finally{Pop-Location}
    if(Test-Path -LiteralPath (Join-Path $temp 'node_modules')){throw 'PRODUCT_WORKTREE_NOT_CLEAN_NODE_MODULES_PRESENT'}
    $status=(& git -C $temp status --porcelain=v1 --untracked-files=all 2>&1 | Out-String).Trim()
    if($LASTEXITCODE -ne 0){throw "PRODUCT_WORKTREE_STATUS_FAILED:$status"}
    if($status){throw "PRODUCT_WORKTREE_INITIAL_DIRTY:$status"}
    & (Get-Command pwsh).Source -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $temp 'scripts\productization\test-productization-contract.ps1')
    if($LASTEXITCODE -ne 0){throw 'PRODUCT_WORKTREE_CONTRACT_FAILED'}
    $tracked=(& git -C $temp diff --ignore-cr-at-eol --name-only HEAD -- 2>&1 | Out-String).Trim()
    if($LASTEXITCODE -ne 0){throw "PRODUCT_WORKTREE_DIFF_FAILED:$tracked"}
    if($tracked){throw "PRODUCT_WORKTREE_TRACKED_CHANGED:$tracked"}
    $safeToForce=$true
    Write-Host "PRODUCTIZATION_CLEAN_WORKTREE_OK head=$head"
}catch{$primaryError=$_}finally{
    if(Test-Path -LiteralPath $temp){
        Push-Location $root
        try{
            & git worktree remove $temp 2>$null
            if($LASTEXITCODE -ne 0){
                if(-not $safeToForce){$cleanupError=[InvalidOperationException]::new('PRODUCT_WORKTREE_FORCE_REMOVE_REFUSED_NO_CLEAN_PROOF')}
                else{& git worktree remove --force $temp 2>$null;if($LASTEXITCODE -ne 0){$cleanupError=[InvalidOperationException]::new('PRODUCT_WORKTREE_FORCE_REMOVE_FAILED')}}
            }
        }finally{Pop-Location}
    }
}
if($primaryError){throw $primaryError}
if($cleanupError){throw $cleanupError}
