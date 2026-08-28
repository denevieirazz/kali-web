[CmdletBinding()]
param(
    [string] $RepoRoot = 'C:\kali-web-sandbox-test',
    [string] $ProductWorktree = 'C:\CloudOS-PR16-Product',
    [string] $EvidenceWorktree = 'C:\CloudOS-PR16-Evidence',
    [switch] $SkipFetch
)

$ErrorActionPreference = 'Stop'

$ProductSha = 'ad9639f1ce8d808d2d532404fd9ca6673244052e'
$EvidenceBranch = 'evidence/pr16-physical-ad9639f'
$MatrixRelativePath = 'poc1-physical-evidence/windows-contained-runtime/matrix-ad9639f'

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string] $WorkingTree,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $AllowFailure
    )

    $output = & git -C $WorkingTree @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "git -C '$WorkingTree' $($Arguments -join ' ') failed ($exitCode):`n$($output -join [Environment]::NewLine)"
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output) }
}

function Assert-GitRepository {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Repository path does not exist: $Path"
    }
    $probe = Invoke-Git -WorkingTree $Path -Arguments @('rev-parse','--is-inside-work-tree') -AllowFailure
    if ($probe.ExitCode -ne 0 -or ($probe.Output -join '').Trim() -ne 'true') {
        throw "Not a Git worktree: $Path"
    }
}

function Get-HeadSha {
    param([Parameter(Mandatory)][string] $Path)
    return ((Invoke-Git -WorkingTree $Path -Arguments @('rev-parse','HEAD')).Output -join '').Trim().ToLowerInvariant()
}

function Get-BranchName {
    param([Parameter(Mandatory)][string] $Path)
    return ((Invoke-Git -WorkingTree $Path -Arguments @('branch','--show-current')).Output -join '').Trim()
}

function Get-StatusLines {
    param([Parameter(Mandatory)][string] $Path)
    return @((Invoke-Git -WorkingTree $Path -Arguments @('status','--porcelain=v1')).Output | Where-Object { $_ -ne $null -and [string]$_ -ne '' })
}

function Assert-DirectoryCanBeCreatedAsWorktree {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)
    if ($items.Count -gt 0) {
        throw "Refusing to replace non-empty directory '$Path'. Inspect/preserve it manually first."
    }
}

Assert-GitRepository -Path $RepoRoot

if (-not $SkipFetch) {
    [void](Invoke-Git -WorkingTree $RepoRoot -Arguments @('fetch','origin','--prune'))
}

$commitProbe = Invoke-Git -WorkingTree $RepoRoot -Arguments @('cat-file','-e',"$ProductSha^{commit}") -AllowFailure
if ($commitProbe.ExitCode -ne 0) {
    throw "Exact product commit is unavailable locally after fetch: $ProductSha"
}

$remoteEvidenceProbe = Invoke-Git -WorkingTree $RepoRoot -Arguments @('show-ref','--verify','--quiet',"refs/remotes/origin/$EvidenceBranch") -AllowFailure
if ($remoteEvidenceProbe.ExitCode -ne 0) {
    throw "Remote evidence branch is unavailable: origin/$EvidenceBranch"
}

# PRODUCT worktree: immutable source under test.
if (-not (Test-Path -LiteralPath $ProductWorktree -PathType Container) -or
    (Invoke-Git -WorkingTree $ProductWorktree -Arguments @('rev-parse','--is-inside-work-tree') -AllowFailure).ExitCode -ne 0) {
    Assert-DirectoryCanBeCreatedAsWorktree -Path $ProductWorktree
    [void](Invoke-Git -WorkingTree $RepoRoot -Arguments @('worktree','add','--detach',$ProductWorktree,$ProductSha))
}

Assert-GitRepository -Path $ProductWorktree
$productStatus = Get-StatusLines -Path $ProductWorktree
if ($productStatus.Count -gt 0) {
    throw "PRODUCT worktree is dirty; refusing to rewrite it:`n$($productStatus -join [Environment]::NewLine)"
}
$productHead = Get-HeadSha -Path $ProductWorktree
if ($productHead -ne $ProductSha) {
    throw "PRODUCT worktree HEAD mismatch. expected=$ProductSha actual=$productHead. Refusing to checkout/reset automatically."
}

# EVIDENCE branch: mutable checkpoint history, separate from product execution.
$localEvidenceProbe = Invoke-Git -WorkingTree $RepoRoot -Arguments @('show-ref','--verify','--quiet',"refs/heads/$EvidenceBranch") -AllowFailure
if ($localEvidenceProbe.ExitCode -ne 0) {
    [void](Invoke-Git -WorkingTree $RepoRoot -Arguments @('branch','--track',$EvidenceBranch,"origin/$EvidenceBranch"))
}

if (-not (Test-Path -LiteralPath $EvidenceWorktree -PathType Container) -or
    (Invoke-Git -WorkingTree $EvidenceWorktree -Arguments @('rev-parse','--is-inside-work-tree') -AllowFailure).ExitCode -ne 0) {
    Assert-DirectoryCanBeCreatedAsWorktree -Path $EvidenceWorktree
    [void](Invoke-Git -WorkingTree $RepoRoot -Arguments @('worktree','add',$EvidenceWorktree,$EvidenceBranch))
}

Assert-GitRepository -Path $EvidenceWorktree
$evidenceBranchActual = Get-BranchName -Path $EvidenceWorktree
if ($evidenceBranchActual -ne $EvidenceBranch) {
    throw "EVIDENCE worktree branch mismatch. expected=$EvidenceBranch actual=$evidenceBranchActual. Refusing to checkout automatically."
}

$evidenceStatus = Get-StatusLines -Path $EvidenceWorktree
if ($evidenceStatus.Count -eq 0 -and -not $SkipFetch) {
    [void](Invoke-Git -WorkingTree $EvidenceWorktree -Arguments @('pull','--ff-only','origin',$EvidenceBranch))
} elseif ($evidenceStatus.Count -gt 0) {
    Write-Warning "EVIDENCE worktree has uncommitted data; preserving it and skipping pull."
    $evidenceStatus | ForEach-Object { Write-Host "  $_" }
}

$ancestorProbe = Invoke-Git -WorkingTree $EvidenceWorktree -Arguments @('merge-base','--is-ancestor',$ProductSha,'HEAD') -AllowFailure
if ($ancestorProbe.ExitCode -ne 0) {
    throw "Evidence history no longer descends from the tested product SHA. Stop before collecting evidence."
}

$matrixPath = Join-Path $EvidenceWorktree ($MatrixRelativePath -replace '/', '\')
[System.IO.Directory]::CreateDirectory($matrixPath) | Out-Null

$proofScript = Join-Path $ProductWorktree 'scripts\run-windows-contained-runtime-physical-proof.ps1'
$collectorScript = Join-Path $ProductWorktree 'scripts\collect-windows-native-containment-evidence.ps1'
if (-not (Test-Path -LiteralPath $proofScript -PathType Leaf)) { throw "Missing product proof script: $proofScript" }
if (-not (Test-Path -LiteralPath $collectorScript -PathType Leaf)) { throw "Missing product collector: $collectorScript" }

Write-Host ''
Write-Host 'CLOUDOS PR16 LOCAL PHYSICAL MATRIX: READY' -ForegroundColor Green
Write-Host "PRODUCT_SHA=$ProductSha"
Write-Host "PRODUCT_WORKTREE=$ProductWorktree"
Write-Host "EVIDENCE_BRANCH=$EvidenceBranch"
Write-Host "EVIDENCE_WORKTREE=$EvidenceWorktree"
Write-Host "MATRIX=$matrixPath"
Write-Host ''
Write-Host 'Launch CloudOS from the PRODUCT worktree:' -ForegroundColor Cyan
Write-Host "  cmd.exe /c `"$ProductWorktree\Iniciar CloudOS.cmd`" Full"
Write-Host ''
Write-Host 'Representative proof command:' -ForegroundColor Cyan
Write-Host "  Set-Location '$ProductWorktree'"
Write-Host "  .\scripts\run-windows-contained-runtime-physical-proof.ps1 -ExpectedHeadSha $ProductSha -ProofName win32-simple -OutputDirectory '$matrixPath'"
