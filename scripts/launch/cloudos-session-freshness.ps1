Set-StrictMode -Version Latest

function Test-CloudOSSessionRevisionMatchesCheckout {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Checkout
    )

    $sessionSha = ''
    $runtimeSha = ''
    $checkoutSha = ''
    try { $sessionSha = ([string]$Session.git.sha).Trim().ToLowerInvariant() } catch {}
    try { $runtimeSha = ([string]$Session.readiness.sourceRevision).Trim().ToLowerInvariant() } catch {}
    try { $checkoutSha = ([string]$Checkout.sha).Trim().ToLowerInvariant() } catch {}

    if ($sessionSha -notmatch '^[a-f0-9]{40}$') { return $false }
    if ($runtimeSha -notmatch '^[a-f0-9]{40}$') { return $false }
    if ($checkoutSha -notmatch '^[a-f0-9]{40}$') { return $false }
    return [string]::Equals($sessionSha, $checkoutSha, [StringComparison]::Ordinal) `
        -and [string]::Equals($runtimeSha, $checkoutSha, [StringComparison]::Ordinal)
}
