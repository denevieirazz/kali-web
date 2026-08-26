[CmdletBinding()]
param(
    [string]$SessionId = '',
    [int]$XpraPid = 0,
    [string]$EvidenceDir = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Fail([string]$Message) {
    Write-Error $Message
    exit 2
}

function Decode-MountPath([string]$Value) {
    return $Value.Replace('\040', ' ').Replace('\011', "`t").Replace('\012', "`n").Replace('\134', '\')
}

function Has-MountOptions($Mount, [string[]]$Required) {
    if ($null -eq $Mount) { return $false }
    foreach ($option in $Required) {
        if ($Mount.Options -notcontains $option) { return $false }
    }
    return $true
}

$ledgerPath = Join-Path $env:TEMP 'cloudos-linux-runtime-poc1-sessions.json'
$selectedSession = $null

if ($XpraPid -le 0) {
    if (-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) {
        Fail "Ledger de sessões não encontrado em $ledgerPath. Abra primeiro um aplicativo Linux dentro do CloudOS."
    }

    $ledger = Get-Content -LiteralPath $ledgerPath -Raw | ConvertFrom-Json
    $sessions = @($ledger.sessions)
    if ($sessions.Count -eq 0) {
        Fail 'O ledger não possui uma sessão Linux ativa.'
    }

    if ($SessionId) {
        $selectedSession = $sessions | Where-Object { $_.id -eq $SessionId } | Select-Object -First 1
        if ($null -eq $selectedSession) { Fail "Sessão $SessionId não encontrada no ledger." }
    } else {
        $selectedSession = $sessions | Sort-Object -Property startedAt -Descending | Select-Object -First 1
    }

    $candidatePid = 0
    if ($null -ne $selectedSession.pids -and $null -ne $selectedSession.pids.xpra) {
        [void][int]::TryParse([string]$selectedSession.pids.xpra, [ref]$candidatePid)
    }
    $XpraPid = $candidatePid
}

if ($XpraPid -le 0) {
    Fail 'A sessão existe, mas o PID global do Xpra ainda não foi correlacionado. Aguarde alguns segundos e rode novamente.'
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Fail 'wsl.exe não está disponível neste ambiente.'
}

if (-not $EvidenceDir) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $EvidenceDir = Join-Path $env:TEMP "cloudos-linux-sandbox-evidence-$stamp"
}
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null

$mountInfoPath = "/proc/$XpraPid/mountinfo"
$mountInfoOutput = @(& wsl.exe --system -u root -- cat $mountInfoPath 2>&1)
$mountInfoExitCode = $LASTEXITCODE
if ($mountInfoExitCode -ne 0) {
    $diagnostic = ($mountInfoOutput -join [Environment]::NewLine)
    Fail "Não foi possível ler $mountInfoPath pelo WSL system (exit=$mountInfoExitCode). $diagnostic"
}

$mountInfoText = $mountInfoOutput -join [Environment]::NewLine
$mountInfoEvidence = Join-Path $EvidenceDir 'mountinfo.txt'
Set-Content -LiteralPath $mountInfoEvidence -Value $mountInfoText -Encoding utf8

$mounts = @()
foreach ($line in $mountInfoOutput) {
    $parts = [string]$line -split ' - ', 2
    if ($parts.Count -ne 2) { continue }
    $left = $parts[0] -split ' '
    $right = $parts[1] -split ' '
    if ($left.Count -lt 6 -or $right.Count -lt 2) { continue }

    $mounts += [pscustomobject]@{
        Id = [int]$left[0]
        ParentId = [int]$left[1]
        MountPoint = Decode-MountPath $left[4]
        Options = @($left[5] -split ',')
        FileSystem = $right[0]
        Source = Decode-MountPath $right[1]
    }
}

function Get-TopMount([string]$MountPoint) {
    $candidates = @($mounts | Where-Object { $_.MountPoint -eq $MountPoint })
    if ($candidates.Count -eq 0) { return $null }
    foreach ($candidate in $candidates) {
        $coveredByAnother = @($candidates | Where-Object { $_.ParentId -eq $candidate.Id }).Count -gt 0
        if (-not $coveredByAnother) { return $candidate }
    }
    return $candidates[-1]
}

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $checks.Add([pscustomobject]@{ name = $Name; passed = $Passed; detail = $Detail }) | Out-Null
}

$rootMount = Get-TopMount '/'
Add-Check 'rootfs-readonly' (Has-MountOptions $rootMount @('ro', 'nosuid', 'nodev')) "root options=$($rootMount.Options -join ',')"

$mntMount = Get-TopMount '/mnt'
Add-Check 'windows-mounts-hidden' ($null -ne $mntMount -and $mntMount.FileSystem -eq 'tmpfs' -and (Has-MountOptions $mntMount @('rw', 'nosuid', 'nodev', 'noexec'))) "mount=/mnt fs=$($mntMount.FileSystem) options=$($mntMount.Options -join ',')"

$homeMask = Get-TopMount '/home'
Add-Check 'real-wsl-home-hidden' ($null -ne $homeMask -and $homeMask.FileSystem -eq 'tmpfs' -and (Has-MountOptions $homeMask @('rw', 'nosuid', 'nodev', 'noexec'))) "mount=/home fs=$($homeMask.FileSystem) options=$($homeMask.Options -join ',')"

$containedHomeMount = $mounts | Where-Object { $_.MountPoint -match '^/var/lib/cloudos/contained-homes/[^/]+$' } | Select-Object -First 1
Add-Check 'contained-home-writable' (Has-MountOptions $containedHomeMount @('rw', 'nosuid', 'nodev', 'noexec')) "mount=$($containedHomeMount.MountPoint) options=$($containedHomeMount.Options -join ',')"

$driveAreas = @('Desktop', 'Documents', 'Downloads', 'Projects', 'Shared')
foreach ($area in $driveAreas) {
    $mountPoint = "/run/cloudos-drive/$area"
    $driveMount = Get-TopMount $mountPoint
    Add-Check "drive-$($area.ToLowerInvariant())" (Has-MountOptions $driveMount @('rw', 'nosuid', 'nodev', 'noexec', 'nosymfollow')) "mount=$mountPoint fs=$($driveMount.FileSystem) options=$($driveMount.Options -join ',')"
}

$initMount = Get-TopMount '/init'
Add-Check 'wsl-init-masked' (Has-MountOptions $initMount @('ro', 'nosuid', 'nodev', 'noexec')) "mount=/init fs=$($initMount.FileSystem) options=$($initMount.Options -join ',')"

$failedChecks = @($checks | Where-Object { -not $_.passed })
$report = [ordered]@{
    schemaVersion = 1
    capturedAt = (Get-Date).ToUniversalTime().ToString('o')
    sessionId = if ($null -ne $selectedSession) { $selectedSession.id } else { $SessionId }
    distribution = if ($null -ne $selectedSession) { $selectedSession.distribution } else { $null }
    xpraPid = $XpraPid
    result = if ($failedChecks.Count -eq 0) { 'PASS' } else { 'FAIL' }
    checks = @($checks)
    evidence = [ordered]@{
        mountinfo = $mountInfoEvidence
        ledger = if (Test-Path -LiteralPath $ledgerPath) { $ledgerPath } else { $null }
    }
}

$reportPath = Join-Path $EvidenceDir 'sandbox-report.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8

$checks | Format-Table -AutoSize
Write-Host "EVIDENCE_DIR=$EvidenceDir"
Write-Host "REPORT=$reportPath"
Write-Host "RESULT=$($report.result)"

if ($failedChecks.Count -gt 0) { exit 2 }
exit 0
