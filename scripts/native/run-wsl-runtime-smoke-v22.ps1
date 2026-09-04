[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Distro,

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [ValidateRange(1000, 15000)]
    [int]$TimeoutMs = 8000,

    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$bin = Join-Path $root "desktop\CloudOS.NativeShell\bin\$Configuration"
$brokerExe = Join-Path $bin 'CloudOS.SystemBroker.exe'
$probeExe = Join-Path $bin 'CloudOS.BrokerProbe.exe'

foreach ($path in @($brokerExe, $probeExe)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "WSL Runtime V22 binary missing: $path"
    }
}

$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslCommand) {
    throw 'wsl.exe is not installed/available on this Windows installation.'
}

if (-not $OutputPath) {
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
    $safeDistro = ($Distro -replace '[^A-Za-z0-9._-]', '_')
    $OutputPath = Join-Path $base (
        'CloudOS\Diagnostics\wsl-runtime-v22-' + $safeDistro + '-' +
        [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '.json')
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$outputParent = [IO.Path]::GetDirectoryName($OutputPath)
if ($outputParent) { New-Item -ItemType Directory -Path $outputParent -Force | Out-Null }
if (Test-Path -LiteralPath $OutputPath) {
    throw "Evidence path already exists: $OutputPath"
}

function Convert-ProbeJson {
    param(
        [Parameter(Mandatory = $true)][string[]]$Text,
        [Parameter(Mandatory = $true)][string]$Operation
    )
    $raw = ($Text -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "$Operation returned no JSON."
    }
    try {
        return $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "$Operation returned invalid JSON: $raw"
    }
}

function Get-WslProcessSnapshot {
    $names = @('wsl', 'wslhost', 'wslrelay')
    $items = @(
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $names -contains $_.ProcessName.ToLowerInvariant() } |
            Sort-Object ProcessName, Id |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    name = $_.ProcessName
                    pid = $_.Id
                    start_time_utc = try { $_.StartTime.ToUniversalTime().ToString('o') } catch { $null }
                }
            }
    )
    return $items
}

$startedUtc = [DateTime]::UtcNow
$broker = $null
$failures = [Collections.Generic.List[string]]::new()
$baselineProcesses = @(Get-WslProcessSnapshot)
$finalProcesses = @()
$registeredDistros = @()
$snapshot = $null
$health = $null

try {
    Write-Host "[WSL-V22] Reading physical WSL registration from Windows..."
    $rawDistros = @(& $wslCommand.Source --list --quiet 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "wsl.exe --list --quiet failed with exit code $LASTEXITCODE: $($rawDistros -join ' ')"
    }

    # wsl.exe output can contain NULs depending on host/encoding. Normalize
    # without inventing distro names.
    $registeredDistros = @(
        $rawDistros |
            ForEach-Object { ([string]$_).Replace([char]0, '').Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($registeredDistros.Count -eq 0) {
        throw 'Windows reports no registered WSL distributions.'
    }
    if (-not ($registeredDistros | Where-Object { $_ -ieq $Distro })) {
        throw "Requested distro '$Distro' is not physically registered. Registered: $($registeredDistros -join ', ')"
    }

    Write-Host "[WSL-V22] Starting isolated CloudOS System Broker..."
    $broker = Start-Process -FilePath $brokerExe -WorkingDirectory $bin -PassThru

    $ping = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 150
        if ($broker.HasExited) {
            throw "CloudOS.SystemBroker exited before readiness with code $($broker.ExitCode)."
        }
        try {
            $ping = Convert-ProbeJson -Text @(& $probeExe ping 2>$null) -Operation 'health.ping'
        }
        catch {
            $ping = $null
        }
    } while ((-not $ping -or -not $ping.ok) -and [DateTime]::UtcNow -lt $deadline)

    if (-not $ping -or -not $ping.ok -or -not $ping.payload.pong) {
        throw 'CloudOS System Broker did not become reachable through BrokerProbe.'
    }

    Write-Host "[WSL-V22] Verifying passive typed WSL inventory through CloudOS..."
    $snapshot = Convert-ProbeJson -Text @(& $probeExe snapshot) -Operation 'system.snapshot'
    if (-not $snapshot.ok) {
        throw "system.snapshot failed: $($snapshot.error.code) $($snapshot.error.message)"
    }
    if (-not [bool]$snapshot.payload.wslEngineAvailable) {
        throw 'CloudOS passive inventory reports WSL engine unavailable.'
    }
    if (-not (@($snapshot.payload.distros) | Where-Object { [string]$_ -ieq $Distro })) {
        throw "CloudOS passive inventory does not contain '$Distro'."
    }

    $typed = @($snapshot.payload.wslDistros | Where-Object { $_.name -ieq $Distro })
    if ($typed.Count -ne 1) {
        throw "CloudOS typed inventory must contain exactly one '$Distro' record; found $($typed.Count)."
    }
    if (-not [bool]$typed[0].basePathPresent) {
        throw "CloudOS sees '$Distro' registered but its backing base path is not present."
    }

    Write-Host "[WSL-V22] Running fixed active probe through Broker -> WSL ($Distro)..."
    $health = Convert-ProbeJson -Text @(& $probeExe wsl-health $Distro $TimeoutMs) -Operation 'wsl.health.probe'
    if (-not $health.ok) {
        throw "wsl.health.probe RPC failed: $($health.error.code) $($health.error.message)"
    }

    $payload = $health.payload
    if ([string]$payload.distro -ine $Distro) { $failures.Add('ProbeDistroMismatch') }
    if (-not [bool]$payload.attempted) { $failures.Add('ProbeNotAttempted') }
    if ([bool]$payload.timedOut) { $failures.Add('ProbeTimedOut') }
    if (-not [bool]$payload.markerSeen) { $failures.Add('ProbeMarkerMissing') }
    if ([int]$payload.exitCode -ne 0) { $failures.Add('ProbeExitCodeNonZero') }
    if (-not [bool]$payload.healthy) { $failures.Add('ProbeNotHealthy') }
    if ([string]$payload.output -notmatch 'CLOUDOS_WSL_HEALTH_V22') { $failures.Add('ProbeOutputMarkerMissing') }

    if ($failures.Count -gt 0) {
        throw "CloudOS WSL active probe failed invariants: $($failures -join ', ')"
    }
}
catch {
    if ($failures.Count -eq 0) {
        $failures.Add(('HarnessException:' + $_.Exception.Message))
    }
}
finally {
    if ($broker -and -not $broker.HasExited) {
        Stop-Process -Id $broker.Id -Force -ErrorAction SilentlyContinue
        try { [void]$broker.WaitForExit(5000) } catch {}
    }
    Start-Sleep -Milliseconds 750
    $finalProcesses = @(Get-WslProcessSnapshot)
}

$baselineIds = @($baselineProcesses | ForEach-Object { $_.pid })
$newRemaining = @($finalProcesses | Where-Object { $baselineIds -notcontains $_.pid })

$report = [ordered]@{
    schema = 22
    test = 'CloudOS WSL Runtime Physical Smoke V22'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    started_utc = $startedUtc.ToString('o')
    verdict = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    distro_requested = $Distro
    timeout_ms = $TimeoutMs
    physical_windows_registration = $registeredDistros
    broker_binary_sha256 = (Get-FileHash -LiteralPath $brokerExe -Algorithm SHA256).Hash
    probe_binary_sha256 = (Get-FileHash -LiteralPath $probeExe -Algorithm SHA256).Hash
    passive_snapshot = $snapshot
    active_probe = $health
    process_evidence = [ordered]@{
        before = $baselineProcesses
        after = $finalProcesses
        newly_remaining = $newRemaining
        interpretation = 'Diagnostic only. This health probe proves Broker -> WSL bounded execution, not the ConPTY terminal session lifecycle. Terminal Ctrl+C/resize/shutdown orphan checks require the terminal lifecycle certification.'
    }
    claims = [ordered]@{
        windows_distro_physically_registered = ($registeredDistros | Where-Object { $_ -ieq $Distro }).Count -gt 0
        cloudos_passive_inventory_verified = $null -ne $snapshot -and [bool]$snapshot.ok
        cloudos_broker_to_wsl_active_probe_verified = $null -ne $health -and [bool]$health.ok -and [bool]$health.payload.healthy
        conpty_terminal_streaming_verified = $false
        ctrl_c_verified = $false
        resize_verified = $false
        terminal_shutdown_orphan_free_verified = $false
    }
    failures = $failures.ToArray()
}

$json = $report | ConvertTo-Json -Depth 12
$stream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $stream.Write($bytes, 0, $bytes.Length)
}
finally {
    $stream.Dispose()
}

if ($failures.Count -gt 0) {
    Write-Error "FAIL: WSL Runtime Physical Smoke V22 failed. Evidence: $OutputPath"
    exit 1
}

Write-Host "PASS: physical '$Distro' registration + CloudOS passive inventory + Broker -> WSL active probe verified."
Write-Host "Evidence: $OutputPath"
Write-Host 'NOTE: ConPTY terminal streaming/Ctrl+C/resize/orphan lifecycle remain separate certification gates and are deliberately not marked PASS here.'
