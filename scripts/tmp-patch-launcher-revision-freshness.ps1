$ErrorActionPreference = 'Stop'
$path = 'scripts/launch/start-cloudos.ps1'
$text = (Get-Content -LiteralPath $path -Raw).Replace("`r`n", "`n")

$sourceOld = ". (Join-Path `$PSScriptRoot 'cloudos-owned-processes.ps1')"
$sourceNew = $sourceOld + "`n. (Join-Path `$PSScriptRoot 'cloudos-session-freshness.ps1')"
if (([regex]::Matches($text, [regex]::Escape($sourceOld))).Count -ne 1) { throw 'SOURCE_IMPORT_PATTERN_NOT_UNIQUE' }
if ($text.Contains("cloudos-session-freshness.ps1")) { throw 'SOURCE_IMPORT_ALREADY_PRESENT' }
$text = $text.Replace($sourceOld, $sourceNew)

$sessionMarker = '$existingSession = Read-CloudOSCurrentSession'
$sessionIndex = $text.IndexOf($sessionMarker, [StringComparison]::Ordinal)
if ($sessionIndex -lt 0 -or $text.IndexOf($sessionMarker, $sessionIndex + 1, [StringComparison]::Ordinal) -ge 0) {
    throw 'EXISTING_SESSION_MARKER_NOT_UNIQUE'
}
$text = $text.Insert($sessionIndex, "`$currentCheckout = Get-CloudOSGitInfo`n")
$sessionIndex = $text.IndexOf($sessionMarker, [StringComparison]::Ordinal)

$healthyMarker = '    $healthy = $false'
$healthyIndex = $text.IndexOf($healthyMarker, $sessionIndex, [StringComparison]::Ordinal)
if ($healthyIndex -lt 0) { throw 'HEALTHY_MARKER_NOT_FOUND' }
$nextHostPidIndex = $text.IndexOf('    $hostPid = 0', $healthyIndex, [StringComparison]::Ordinal)
if ($nextHostPidIndex -lt 0 -or $nextHostPidIndex - $healthyIndex -gt 100) { throw 'HOST_PID_MARKER_NOT_FOUND_AFTER_HEALTHY' }
$healthyLineEnd = $text.IndexOf("`n", $healthyIndex, [StringComparison]::Ordinal)
if ($healthyLineEnd -lt 0) { throw 'HEALTHY_LINE_END_NOT_FOUND' }
$revisionBlock = @'
    $revisionMatches = Test-CloudOSSessionRevisionMatchesCheckout -Session $existingSession -Checkout $currentCheckout
    if (-not $revisionMatches) {
        $oldSha = try { [string]$existingSession.git.sha } catch { '' }
        Write-Host "CloudOS em execução pertence a outro commit (sessão=$oldSha checkout=$($currentCheckout.sha)); reiniciando runtime."
    }
'@
$text = $text.Insert($healthyLineEnd + 1, $revisionBlock.Replace("`r`n", "`n"))

$healthCondition = '                        if ([int]$res.StatusCode -ge 200 -and [int]$res.StatusCode -lt 400) {'
$healthIndex = $text.IndexOf($healthCondition, $sessionIndex, [StringComparison]::Ordinal)
if ($healthIndex -lt 0) { throw 'HEALTH_CONDITION_NOT_FOUND' }
$sessionEnd = $text.IndexOf('    if ($healthy) {', $healthIndex, [StringComparison]::Ordinal)
if ($sessionEnd -lt 0 -or $healthIndex -gt $sessionEnd) { throw 'HEALTH_CONDITION_OUTSIDE_SESSION_BLOCK' }
$replacementCondition = '                        if ($revisionMatches -and [int]$res.StatusCode -ge 200 -and [int]$res.StatusCode -lt 400) {'
$text = $text.Remove($healthIndex, $healthCondition.Length).Insert($healthIndex, $replacementCondition)

Set-Content -LiteralPath $path -Value $text -Encoding utf8 -NoNewline
