$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'launch\cloudos-session-freshness.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$shaA = 'a' * 40
$shaB = 'b' * 40
$matchingSession = [pscustomobject]@{
    mode = 'Full'
    git = [pscustomobject]@{ sha = $shaA }
    readiness = [pscustomobject]@{ sourceRevision = $shaA }
}
$matchingCheckout = [pscustomobject]@{ sha = $shaA }
$differentCheckout = [pscustomobject]@{ sha = $shaB }
$missingSession = [pscustomobject]@{
    mode = 'Full'
    git = [pscustomobject]@{ sha = $null }
    readiness = [pscustomobject]@{ sourceRevision = $shaA }
}
$missingRuntime = [pscustomobject]@{
    mode = 'Full'
    git = [pscustomobject]@{ sha = $shaA }
    readiness = [pscustomobject]@{ sourceRevision = $null }
}
$staleRuntime = [pscustomobject]@{
    mode = 'Full'
    git = [pscustomobject]@{ sha = $shaA }
    readiness = [pscustomobject]@{ sourceRevision = $shaB }
}
$shortSession = [pscustomobject]@{
    mode = 'Full'
    git = [pscustomobject]@{ sha = 'abc123' }
    readiness = [pscustomobject]@{ sourceRevision = $shaA }
}

Assert-True (Test-CloudOSSessionRevisionMatchesCheckout -Session $matchingSession -Checkout $matchingCheckout) 'Matching checkout, session and runtime revisions must be reusable.'
Assert-True (-not (Test-CloudOSSessionRevisionMatchesCheckout -Session $matchingSession -Checkout $differentCheckout)) 'A running session from another commit must never be reused.'
Assert-True (-not (Test-CloudOSSessionRevisionMatchesCheckout -Session $missingSession -Checkout $matchingCheckout)) 'A session without Git revision identity must fail closed.'
Assert-True (-not (Test-CloudOSSessionRevisionMatchesCheckout -Session $missingRuntime -Checkout $matchingCheckout)) 'A native session without recorded runtime revision must fail closed.'
Assert-True (-not (Test-CloudOSSessionRevisionMatchesCheckout -Session $staleRuntime -Checkout $matchingCheckout)) 'A stale runtime must not be reused even if the session Git SHA matches the checkout.'
Assert-True (-not (Test-CloudOSSessionRevisionMatchesCheckout -Session $shortSession -Checkout $matchingCheckout)) 'A malformed revision must fail closed.'

$upperSession = [pscustomobject]@{
    mode = 'Full'
    git = [pscustomobject]@{ sha = $shaA.ToUpperInvariant() }
    readiness = [pscustomobject]@{ sourceRevision = $shaA.ToUpperInvariant() }
}
Assert-True (Test-CloudOSSessionRevisionMatchesCheckout -Session $upperSession -Checkout $matchingCheckout) 'Revision comparison should be case-insensitive after normalization.'

$webOnlySession = [pscustomobject]@{
    mode = 'WebOnly'
    git = [pscustomobject]@{ sha = $shaA }
    readiness = [pscustomobject]@{ backendApiBase = 'http://127.0.0.1:1234' }
}
Assert-True (Test-CloudOSSessionRevisionMatchesCheckout -Session $webOnlySession -Checkout $matchingCheckout) 'A non-native session may rely on its Git revision when no native runtime identity exists.'

Write-Host 'PASS CloudOS session revision freshness'
