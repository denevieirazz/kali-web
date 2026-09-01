# run-reactive-broker-v23-smoke.ps1
# Proves that the actual Flutter broker client survives event-before-response
# interleaving, concurrent RPCs, disconnect/reconnect and subscription restore.

[CmdletBinding()]
param(
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$broker = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.SystemBroker.exe'
$probe = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.BrokerProbe.exe'
if (-not (Test-Path -LiteralPath $broker -PathType Leaf)) { throw "Missing SystemBroker: $broker" }
if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw "Missing BrokerProbe: $probe" }

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\artifacts\reactive-broker-v23-smoke.json'
}
$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

function Get-WinlogonShellState {
    $key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
    if (-not (Test-Path -LiteralPath $key)) { return 'key-absent' }
    $props = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
    if ($null -eq $props.PSObject.Properties['Shell']) { return 'value-absent' }
    return "value:$([string]$props.Shell)"
}

function Invoke-Probe {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFailure)
    $output = & $probe @Arguments 2>&1
    $code = $LASTEXITCODE
    if (-not $AllowFailure -and $code -ne 0) {
        throw "BrokerProbe failed with exit code $code: $($Arguments -join ' ')`n$($output | Out-String)"
    }
    return [pscustomobject]@{ ExitCode = $code; Text = ($output | Out-String).Trim() }
}

$winlogonBefore = Get-WinlogonShellState
Get-Process -Name 'CloudOS.SystemBroker' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 250

$brokerProcess = Start-Process -FilePath $broker -PassThru -WindowStyle Hidden
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    $ready = $false
    do {
        Start-Sleep -Milliseconds 100
        $ping = Invoke-Probe -Arguments @('ping') -AllowFailure
        if ($ping.ExitCode -eq 0) { $ready = $true; break }
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $ready) { throw 'SystemBroker did not become ready for V23 smoke.' }

    Write-Host '[Smoke-V23] Proving event/response interleaving and reconnect...' -ForegroundColor Cyan
    $probeResult = Invoke-Probe -Arguments @('reactive-self-test')
    $reactive = $probeResult.Text | ConvertFrom-Json -Depth 20
    if ($reactive.schema -ne 23 -or $reactive.verdict -ne 'pass') {
        throw "Reactive probe did not pass: $($probeResult.Text)"
    }
    foreach ($name in @('event_before_response','concurrent_response_correlation','reconnect_subscription_restore')) {
        if ($reactive.$name -ne $true) { throw "Reactive V23 evidence failed: $name" }
    }
    if ([int]$reactive.concurrent_rpc_count -lt 8) { throw 'Reactive V23 did not exercise enough concurrent RPCs.' }
    if ([int]$reactive.files_changed_events -lt 2) { throw 'Reactive V23 did not receive file events before and after reconnect.' }

    $postPing = Invoke-Probe -Arguments @('ping')
    $pingJson = $postPing.Text | ConvertFrom-Json -Depth 20
    if ($pingJson.ok -ne $true) { throw 'Broker stopped responding after V23 reactive self-test.' }

    $winlogonAfter = Get-WinlogonShellState
    if ($winlogonAfter -cne $winlogonBefore) {
        throw "Production Winlogon Shell state changed during V23 smoke: before='$winlogonBefore' after='$winlogonAfter'"
    }

    $evidence = [ordered]@{
        schema = 23
        verdict = 'pass'
        event_before_response = [bool]$reactive.event_before_response
        concurrent_rpc_count = [int]$reactive.concurrent_rpc_count
        concurrent_response_correlation = [bool]$reactive.concurrent_response_correlation
        reconnect_subscription_restore = [bool]$reactive.reconnect_subscription_restore
        files_changed_events = [int]$reactive.files_changed_events
        post_test_broker_ping = $true
        production_winlogon_unchanged = $true
        userchoice_mutation_executed = $false
        package_mutation_executed = $false
        shell_activation_executed = $false
        limitations = @(
            'Hosted smoke validates named-pipe interleaving/reconnect, not physical RDP/suspend/hotplug.',
            'No package mutation, shell activation, logoff, reboot or production Winlogon write is performed.'
        )
    }
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    Write-Host '[PASS] V23 reactive broker runtime smoke passed.' -ForegroundColor Green
    Get-Content -LiteralPath $OutputPath
}
finally {
    if ($brokerProcess -and -not $brokerProcess.HasExited) {
        Stop-Process -Id $brokerProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
