function Get-CloudOSGitContext {
    param(
        [Parameter(Mandatory=$false)]
        [string]$RepoPath = (Join-Path $PSScriptRoot '..')
    )

    $root = [IO.Path]::GetFullPath($RepoPath)
    if (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) {
        return [PSCustomObject]@{
            IsGit = $false
            HeadSha = ''
            Branch = ''
            IsDetached = $false
            IsKnownNonWslBranch = $false
            ScopeSource = 'not-a-git-repo'
            GitError = 'NOT_A_GIT_REPOSITORY'
        }
    }

    $isWsl = (Get-Command wslpath -ErrorAction SilentlyContinue) -ne $null
    $winPath = if ($isWsl) { (& wslpath -w $root 2>$null).Trim() } else { $root }
    $gitBin = if ($isWsl) { "git.exe" } else { "git" }

    $gitCmd = Get-Command $gitBin -ErrorAction SilentlyContinue
    if ($null -eq $gitCmd) {
        return [PSCustomObject]@{
            IsGit = $false
            HeadSha = ''
            Branch = ''
            IsDetached = $false
            IsKnownNonWslBranch = $false
            ScopeSource = 'git-executable-not-found'
            GitError = "GIT_EXECUTABLE_NOT_FOUND: $gitBin"
        }
    }

    $headSha = ''
    $gitError = $null

    try {
        $headOut = & $gitBin -C $winPath rev-parse HEAD 2>&1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($headOut)) {
            $gitError = "GIT_REV_PARSE_HEAD_FAILED: $headOut"
        } else {
            $candidate = ([string]$headOut).Trim()
            if ($candidate -match '^[0-9a-fA-F]{40}$') {
                $headSha = $candidate
            } else {
                $gitError = "INVALID_HEAD_SHA: $candidate"
            }
        }
    } catch {
        $gitError = "GIT_EXECUTION_EXCEPTION: $($_.Exception.Message)"
    }

    $branch = ''
    $source = 'detached-no-branch'
    $isKnownNonWslBranch = $false

    function Test-ValidBranchName([string]$b) {
        if ([string]::IsNullOrWhiteSpace($b)) { return $false }
        $t = $b.Trim()
        if ($t.Length -eq 0 -or $t.Length -gt 255) { return $false }
        if ($t -match '[\s\\~^:?*\[\]@{}]' -or $t.Contains('..') -or $t.Contains('//')) { return $false }
        if ($t.StartsWith('/') -or $t.EndsWith('/') -or $t.StartsWith('.') -or $t.EndsWith('.')) { return $false }
        if ($t -match '^[\d]+/merge$' -or $t -match '^pull/[\d]+/(merge|head)$') { return $false }
        if ($t -notmatch '^[a-zA-Z0-9._/-]+$') { return $false }
        return $true
    }

    # 1. GITHUB_HEAD_REF (PR target)
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_HEAD_REF) -and (Test-ValidBranchName $env:GITHUB_HEAD_REF)) {
        $branch = $env:GITHUB_HEAD_REF.Trim()
        $source = 'github-head-ref'
    }
    # 2. GITHUB_REF_NAME (Push ref)
    elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REF_NAME) -and (Test-ValidBranchName $env:GITHUB_REF_NAME)) {
        $branch = $env:GITHUB_REF_NAME.Trim()
        $source = 'github-ref-name'
    }
    # 3. Local git branch
    else {
        try {
            $branchOut = & $gitBin -C $winPath branch --show-current 2>&1
            if ($LASTEXITCODE -eq 0 -and $null -ne $branchOut) {
                $candidateBranch = ([string]$branchOut).Trim()
                if (Test-ValidBranchName $candidateBranch) {
                    $branch = $candidateBranch
                    $source = 'git-local-branch'
                }
            }
        } catch {
            if ($null -eq $gitError) {
                $gitError = "GIT_BRANCH_RESOLVE_EXCEPTION: $($_.Exception.Message)"
            }
        }
    }

    $isDetached = [string]::IsNullOrEmpty($branch)
    if (-not $isDetached) {
        if ($branch -notlike 'feature/wsl-core*') {
            $isKnownNonWslBranch = $true
        }
    }

    return [PSCustomObject]@{
        IsGit = ($null -eq $gitError -and -not [string]::IsNullOrEmpty($headSha))
        HeadSha = $headSha
        Branch = $branch
        IsDetached = $isDetached
        IsKnownNonWslBranch = $isKnownNonWslBranch
        ScopeSource = $source
        GitError = $gitError
    }
}
