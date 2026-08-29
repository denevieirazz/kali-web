$ErrorActionPreference = 'Stop'
$path = 'scripts/launch/start-cloudos.ps1'
$text = (Get-Content -LiteralPath $path -Raw).Replace("`r`n", "`n")

$sourceOld = ". (Join-Path `$PSScriptRoot 'cloudos-owned-processes.ps1')"
$sourceNew = $sourceOld + "`n. (Join-Path `$PSScriptRoot 'cloudos-session-freshness.ps1')"
if (([regex]::Matches($text, [regex]::Escape($sourceOld))).Count -ne 1) { throw 'SOURCE_IMPORT_PATTERN_NOT_UNIQUE' }
if ($text.Contains("cloudos-session-freshness.ps1")) { throw 'SOURCE_IMPORT_ALREADY_PRESENT' }
$text = $text.Replace($sourceOld, $sourceNew)

$existingOld = @'
$existingSession = Read-CloudOSCurrentSession
if ($existingSession -and $existingSession.status -eq 'running') {
    $healthy = $false
    $hostPid = 0
'@.TrimEnd()
$existingNew = @'
$currentCheckout = Get-CloudOSGitInfo
$existingSession = Read-CloudOSCurrentSession
if ($existingSession -and $existingSession.status -eq 'running') {
    $healthy = $false
    $revisionMatches = Test-CloudOSSessionRevisionMatchesCheckout -Session $existingSession -Checkout $currentCheckout
    if (-not $revisionMatches) {
        $oldSha = try { [string]$existingSession.git.sha } catch { '' }
        Write-Host "CloudOS em execução pertence a outro commit (sessão=$oldSha checkout=$($currentCheckout.sha)); reiniciando runtime."
    }
    $hostPid = 0
'@.TrimEnd()
if (([regex]::Matches($text, [regex]::Escape($existingOld))).Count -ne 1) { throw 'EXISTING_SESSION_PATTERN_NOT_UNIQUE' }
$text = $text.Replace($existingOld, $existingNew)

$healthOld = @'
                        if ([int]$res.StatusCode -ge 200 -and [int]$res.StatusCode -lt 400) {
                            $healthy = $true
                        }
'@.TrimEnd()
$healthNew = @'
                        if ($revisionMatches -and [int]$res.StatusCode -ge 200 -and [int]$res.StatusCode -lt 400) {
                            $healthy = $true
                        }
'@.TrimEnd()
if (([regex]::Matches($text, [regex]::Escape($healthOld))).Count -ne 1) { throw 'HEALTH_PATTERN_NOT_UNIQUE' }
$text = $text.Replace($healthOld, $healthNew)

Set-Content -LiteralPath $path -Value $text -Encoding utf8 -NoNewline
