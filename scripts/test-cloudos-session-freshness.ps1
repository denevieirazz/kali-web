$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'launch\cloudos-session-freshness.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$shaA = 'a' * 40
$shaB = 'b' * 40
$matchingSession = [pscustomobject]@{ git = [pscustomobject]@{ sha = $shaA } }
$matchingCheckout = [pscustomobject]@{ sha = $shaA }
$differentCheckout = [pscustomobject]@{ sha = $shaB }
$missingSession = [pscustomobject]@{ git = [pscustomobject]@{ sha = $null } }
$shortSession = [pscustomobject]@{ git = [pscustomobject]@{ sha = 'abc123' } }

Assert-True (Test-CloudOSSessionRevisionMatchesCheckout -Session $matchingSession -Checkout $matchingCheckout) 'Matching 40-hex revisions must be reusable.'
Assert-True (-not (Test-CloudOSSessionRevisionMatchesCheckout -Session $matchingSession -Checkout $differentCheckout)) 'A running session from another commit must never be reused.'
Assert-True (-not (Test-CloudOSSessionRevisionMatchesCheckout -Session $missingSession -Checkout $matchingCheckout)) 'A session without revision identity must fail closed.'
Assert-True (-not (Test-CloudOSSessionRevisionMatchesCheckout -Session $shortSession -Checkout $matchingCheckout)) 'A malformed revision must fail closed.'

$upperSession = [pscustomobject]@{ git = [pscustomobject]@{ sha = $shaA.ToUpperInvariant() } }
Assert-True (Test-CloudOSSessionRevisionMatchesCheckout -Session $upperSession -Checkout $matchingCheckout) 'Revision comparison should be case-insensitive after normalization.'

Write-Host 'PASS CloudOS session revision freshness'
