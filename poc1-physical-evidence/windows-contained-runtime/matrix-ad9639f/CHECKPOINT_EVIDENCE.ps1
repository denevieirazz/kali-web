[CmdletBinding()]
param(
    [string] $Message = '',
    [string] $EvidenceWorktree = 'C:\CloudOS-PR16-Evidence'
)

$ErrorActionPreference = 'Stop'

$ProductSha = 'ad9639f1ce8d808d2d532404fd9ca6673244052e'
$EvidenceBranch = 'evidence/pr16-physical-ad9639f'
$MatrixRelativePath = 'poc1-physical-evidence/windows-contained-runtime/matrix-ad9639f'
$RequiredReports = @('CURRENT_STATE.md','PHYSICAL_MATRIX_REPORT.md','PHYSICAL_MATRIX_REPORT.json')

function Invoke-Git {
    param([Parameter(Mandatory)][string[]] $Arguments, [switch] $AllowFailure)
    $output = & git -C $EvidenceWorktree @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed ($exitCode):`n$($output -join [Environment]::NewLine)"
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output) }
}

function Get-GitLines {
    param([Parameter(Mandatory)][string[]] $Arguments)
    return @((Invoke-Git -Arguments $Arguments).Output | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' })
}

if (-not (Test-Path -LiteralPath $EvidenceWorktree -PathType Container)) {
    throw "Evidence worktree does not exist: $EvidenceWorktree"
}

$inside = ((Invoke-Git -Arguments @('rev-parse','--is-inside-work-tree')).Output -join '').Trim()
if ($inside -ne 'true') { throw "Not a Git worktree: $EvidenceWorktree" }

$branch = ((Invoke-Git -Arguments @('branch','--show-current')).Output -join '').Trim()
if ($branch -ne $EvidenceBranch) {
    throw "Wrong evidence branch. expected=$EvidenceBranch actual=$branch"
}

$ancestor = Invoke-Git -Arguments @('merge-base','--is-ancestor',$ProductSha,'HEAD') -AllowFailure
if ($ancestor.ExitCode -ne 0) {
    throw "Evidence branch no longer descends from product SHA $ProductSha"
}

$alreadyStaged = Get-GitLines -Arguments @('diff','--cached','--name-only')
if ($alreadyStaged.Count -gt 0) {
    throw "Refusing to mix with pre-existing staged changes:`n$($alreadyStaged -join [Environment]::NewLine)"
}

$matrixPath = Join-Path $EvidenceWorktree ($MatrixRelativePath -replace '/', '\')
if (-not (Test-Path -LiteralPath $matrixPath -PathType Container)) {
    throw "Matrix directory does not exist: $matrixPath"
}

foreach ($report in $RequiredReports) {
    $path = Join-Path $matrixPath $report
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required report is missing: $path"
    }
    $text = [System.IO.File]::ReadAllText($path)
    if (-not $text.Contains($ProductSha)) {
        throw "Required report does not pin PRODUCT_TESTED_SHA=$ProductSha in $path"
    }
}

$validatorPath = Join-Path $matrixPath 'VALIDATE_REPORT.ps1'
if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
    throw "Matrix validator is missing: $validatorPath"
}
& $validatorPath -MatrixDirectory $matrixPath
if ($LASTEXITCODE -ne 0) { throw "Matrix validator returned exit code $LASTEXITCODE" }

[void](Invoke-Git -Arguments @('add','--',$MatrixRelativePath))
$staged = Get-GitLines -Arguments @('diff','--cached','--name-only')
if ($staged.Count -eq 0) {
    Write-Host 'No evidence changes to checkpoint.' -ForegroundColor Yellow
    exit 0
}

$invalidPaths = @($staged | Where-Object {
    $normalized = $_.Replace('\','/')
    -not ($normalized -eq $MatrixRelativePath -or $normalized.StartsWith("$MatrixRelativePath/", [System.StringComparison]::Ordinal))
})
if ($invalidPaths.Count -gt 0) {
    [void](Invoke-Git -Arguments @('restore','--staged','--',$MatrixRelativePath) -AllowFailure)
    throw "Refusing to commit paths outside the matrix:`n$($invalidPaths -join [Environment]::NewLine)"
}

# Scan the staged patch for common credential material. This is deliberately conservative.
$stagedPatch = ((Invoke-Git -Arguments @('diff','--cached','--no-ext-diff','--unified=0','--',$MatrixRelativePath)).Output -join [Environment]::NewLine)
$secretPatterns = @(
    '(?im)^\+.*authorization\s*:\s*bearer\s+[A-Za-z0-9._~+\/-]+=*',
    '(?im)^\+.*(?:password|senha)\s*[=:]\s*[^\s<>{}\[\]]{6,}',
    '(?im)^\+.*(?:recovery[_ -]?code|codigo[_ -]?de[_ -]?recuperacao|c[oó]digo[_ -]?de[_ -]?recupera[cç][aã]o)\s*[=:]\s*[^\s<>{}\[\]]{6,}',
    '(?im)^\+.*(?:cookie|set-cookie)\s*:\s*.+',
    '(?im)^\+.*\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b'
)
foreach ($pattern in $secretPatterns) {
    if ($stagedPatch -match $pattern) {
        [void](Invoke-Git -Arguments @('restore','--staged','--',$MatrixRelativePath) -AllowFailure)
        throw 'Potential credential material detected in staged evidence. Nothing was committed; redact it before retrying.'
    }
}

if ([string]::IsNullOrWhiteSpace($Message)) {
    $Message = 'test(evidence): checkpoint ' + (Get-Date -Format 'yyyyMMdd-HHmmss')
}
if ($Message.Contains("`n") -or $Message.Contains("`r")) {
    [void](Invoke-Git -Arguments @('restore','--staged','--',$MatrixRelativePath) -AllowFailure)
    throw 'Commit message must be one line.'
}

Write-Host 'Staged evidence:' -ForegroundColor Cyan
$staged | ForEach-Object { Write-Host "  $_" }

[void](Invoke-Git -Arguments @('commit','-m',$Message))
[void](Invoke-Git -Arguments @('push','origin',"HEAD:refs/heads/$EvidenceBranch"))

$head = ((Invoke-Git -Arguments @('rev-parse','HEAD')).Output -join '').Trim()
Write-Host ''
Write-Host 'EVIDENCE CHECKPOINT: SUCCESS' -ForegroundColor Green
Write-Host "branch=$EvidenceBranch"
Write-Host "commit=$head"
Write-Host "productTestedSha=$ProductSha"

