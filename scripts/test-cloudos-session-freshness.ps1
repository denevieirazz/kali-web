$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'launch\cloudos-session-freshness.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$shaA = 'a' * 40
$shaB = 'b' * 40
$matchingSession = [pscustomobject]@{
    git = [pscustomobject]@{ sha = $shaA }
    readiness = [pscustomobject]@{ sourceRevision = $shaA }
}
$matchingCheckout = [pscustomobject]@{ sha = $shaA }
$differentCheckout = [pscustomobject]@{ sha = $shaB }
$missingSession = [pscustomobject]@{
    git = [pscustomobject]@{ sha = $null }
    readiness = [pscustomobject]@{ sourceRevision = $shaA }
}
$missingRuntime = [pscustomobject]@{
    git = [pscustomobject]@{ sha = $shaA }
    readiness = [pscustomobject]@{ sourceRevision = $null }
}
$staleRuntime = [pscustomobject]@{
    git = [pscustomobject]@{ sha = $shaA }
    readiness = [pscustomobject]@{ sourceRevision = $shaB }
}
$shortSession = [pscustomobject]@{
    git = [pscustomobject]@{ sha = 'abc123' }
    readiness = [pscustomobject]@{ sourceRevision = $shaA }
}

Assert-True (Test-CloudOSSessionRevisionMatchesCheckout -Session $matchingSession -Checkout $matchingCheckout) 'Matching checkout, session and runtime revisions must be reusable.'
Assert-True (-not (Test-CloudOSSessionRevisionMatchesCheckout -Session $matchingSession -Checkout $differentCheckout)) 'A running session from another commit must never be reused.'
Assert-True (-not (Test-CloudOSSessionRevisionMatchesCheckout -Session $missingSession -Checkout $matchingCheckout)) 'A session without Git revision identity must fail closed.'
Assert-True (-not (Test-CloudOSSessionRevisionMatchesCheckout -Session $missingRuntime -Checkout $matchingCheckout)) 'A session without recorded runtime revision must fail closed.'
Assert-True (-not (Test-CloudOSSessionRevisionMatchesCheckout -Session $staleRuntime -Checkout $matchingCheckout)) 'A stale runtime must not be reused even if the session Git SHA matches the checkout.'
Assert-True (-not (Test-CloudOSSessionRevisionMatchesCheckout -Session $shortSession -Checkout $matchingCheckout)) 'A malformed revision must fail closed.'

$upperSession = [pscustomobject]@{
    git = [pscustomobject]@{ sha = $shaA.ToUpperInvariant() }
    readiness = [pscustomobject]@{ sourceRevision = $shaA.ToUpperInvariant() }
}
Assert-True (Test-CloudOSSessionRevisionMatchesCheckout -Session $upperSession -Checkout $matchingCheckout) 'Revision comparison should be case-insensitive after normalization.'

Write-Host 'PASS CloudOS session revision freshness'
