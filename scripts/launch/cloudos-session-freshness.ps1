Set-StrictMode -Version Latest

function Test-CloudOSSessionRevisionMatchesCheckout {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Checkout
    )

    $sessionSha = ''
    $runtimeSha = ''
    $checkoutSha = ''
    $mode = ''
    try { $sessionSha = ([string]$Session.git.sha).Trim().ToLowerInvariant() } catch {}
    try { $runtimeSha = ([string]$Session.readiness.sourceRevision).Trim().ToLowerInvariant() } catch {}
    try { $checkoutSha = ([string]$Checkout.sha).Trim().ToLowerInvariant() } catch {}
    try { $mode = ([string]$Session.mode).Trim() } catch {}

    if ($sessionSha -notmatch '^[a-f0-9]{40}$') { return $false }
    if ($checkoutSha -notmatch '^[a-f0-9]{40}$') { return $false }
    if (-not [string]::Equals($sessionSha, $checkoutSha, [StringComparison]::Ordinal)) { return $false }

    $requiresRuntimeIdentity = $mode -in @('Full', 'BrowserValidation')
    if ($requiresRuntimeIdentity -and $runtimeSha -notmatch '^[a-f0-9]{40}$') { return $false }
    if ($runtimeSha) {
        if ($runtimeSha -notmatch '^[a-f0-9]{40}$') { return $false }
        if (-not [string]::Equals($runtimeSha, $checkoutSha, [StringComparison]::Ordinal)) { return $false }
    }

    return $true
}
