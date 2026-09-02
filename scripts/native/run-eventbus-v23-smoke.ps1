# CloudOS V23 — real named-pipe EventBus subscription + job delivery smoke
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$brokerExe = Join-Path $root 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.SystemBroker.exe'
$sandbox = 'C:\CloudOS-V23-EventBusSmoke'
$expectedSandbox = [IO.Path]::GetFullPath($sandbox).TrimEnd('\')
$evidenceDir = Join-Path $root 'TestResults\v23-eventbus-smoke'
$evidencePath = Join-Path $evidenceDir 'eventbus-v23-smoke.json'
$requestCounter = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Remove-Sandbox {
    if (-not (Test-Path -LiteralPath $sandbox)) { return }
    $resolved = [IO.Path]::GetFullPath($sandbox).TrimEnd('\')
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($resolved, $expectedSandbox)) {
        throw "Refusing EventBus smoke cleanup outside sandbox: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Get-PipeName {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $session = (Get-Process -Id $PID).SessionId
    return "CloudOS.SystemBroker.v21.$sid.$session"
}

function New-BrokerPipe {
    $pipe = [IO.Pipes.NamedPipeClientStream]::new(
        '.',
        (Get-PipeName),
        [IO.Pipes.PipeDirection]::InOut,
        [IO.Pipes.PipeOptions]::Asynchronous
    )
    $pipe.Connect(3000)
    return $pipe
}

function Write-Frame {
    param(
        [Parameter(Mandatory)]$Stream,
        [Parameter(Mandatory)][string]$Json
    )
    $bytes = [Text.Encoding]::UTF8.GetBytes($Json)
    Assert-True ($bytes.Length -le 1048576) 'EventBus smoke attempted oversized request frame.'
    $header = [BitConverter]::GetBytes([uint32]$bytes.Length)
    $Stream.Write($header, 0, $header.Length)
    if ($bytes.Length -gt 0) { $Stream.Write($bytes, 0, $bytes.Length) }
    $Stream.Flush()
}

function Read-ExactAsync {
    param(
        [Parameter(Mandatory)]$Stream,
        [Parameter(Mandatory)][byte[]]$Buffer,
        [Parameter(Mandatory)][int]$Count,
        [Parameter(Mandatory)][int]$TimeoutMs
    )
    $offset = 0
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ($offset -lt $Count) {
        $remainingRaw = [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds
        if ($remainingRaw -le 0) { throw 'Timed out while reading Broker frame.' }
        $remainingMs = [Math]::Max(1, $remainingRaw)
        $task = $Stream.ReadAsync($Buffer, $offset, $Count - $offset)
        if (-not $task.Wait($remainingMs)) { throw 'Timed out while reading Broker frame.' }
        $read = $task.Result
        if ($read -le 0) { throw 'Broker closed EventBus pipe while a frame was being read.' }
        $offset += $read
    }
}

function Read-Frame {
    param(
        [Parameter(Mandatory)]$Stream,
        [int]$TimeoutMs = 5000
    )
    $header = [byte[]]::new(4)
    Read-ExactAsync -Stream $Stream -Buffer $header -Count 4 -TimeoutMs $TimeoutMs
    $length = [BitConverter]::ToUInt32($header, 0)
    Assert-True ($length -le 1048576) "Broker sent oversized EventBus frame: $length"
    $payload = [byte[]]::new([int]$length)
    if ($length -gt 0) {
        Read-ExactAsync -Stream $Stream -Buffer $payload -Count ([int]$length) -TimeoutMs $TimeoutMs
    }
    $json = [Text.Encoding]::UTF8.GetString($payload)
    return ($json | ConvertFrom-Json -Depth 30)
}

function New-RequestJson {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)]$Payload
    )
    return ([ordered]@{
        protocol = 21
        type = 'request'
        id = $Id
        method = $Method
        payload = $Payload
    } | ConvertTo-Json -Depth 20 -Compress)
}

function Wait-Response {
    param(
        [Parameter(Mandatory)]$Stream,
        [Parameter(Mandatory)][string]$Id,
        [int]$TimeoutMs = 5000
    )
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $remaining = [Math]::Max(1, [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        $frame = Read-Frame -Stream $Stream -TimeoutMs $remaining
        if ($frame.type -eq 'response' -and $frame.id -eq $Id) { return $frame }
    }
    throw "Timed out waiting for Broker response '$Id'."
}

function Invoke-BrokerRpc {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)]$Payload
    )
    $script:requestCounter++
    $id = "event-smoke-rpc-$($script:requestCounter)"
    $pipe = New-BrokerPipe
    try {
        Write-Frame -Stream $pipe -Json (New-RequestJson -Id $id -Method $Method -Payload $Payload)
        return Wait-Response -Stream $pipe -Id $id -TimeoutMs 5000
    }
    finally {
        $pipe.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $brokerExe)) { throw "System Broker missing: $brokerExe" }
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
Get-Process -Name 'CloudOS.SystemBroker' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 250
$broker = Start-Process -FilePath $brokerExe -PassThru -WindowStyle Hidden
$eventPipe = $null

try {
    Start-Sleep -Milliseconds 700
    Remove-Sandbox
    $sourceDir = Join-Path $sandbox 'source'
    $destinationDir = Join-Path $sandbox 'destination'
    New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    $sourceFile = Join-Path $sourceDir 'event-source.bin'
    [IO.File]::WriteAllBytes($sourceFile, [byte[]]::new(4 * 1024 * 1024))

    # Dedicated subscriber connection: hello -> subscribe('*').
    $eventPipe = New-BrokerPipe
    $helloId = 'event-smoke-hello'
    Write-Frame -Stream $eventPipe -Json (New-RequestJson -Id $helloId -Method 'hello' -Payload @{
        clientName = 'CloudOS.EventBusSmoke'
        clientVersion = '23'
    })
    $hello = Wait-Response -Stream $eventPipe -Id $helloId
    Assert-True ($hello.ok -eq $true) 'EventBus subscriber hello failed.'

    $subscribeId = 'event-smoke-subscribe'
    Write-Frame -Stream $eventPipe -Json (New-RequestJson -Id $subscribeId -Method 'events.subscribe' -Payload @{
        pattern = '*'
    })
    $subscribed = Wait-Response -Stream $eventPipe -Id $subscribeId
    Assert-True ($subscribed.ok -eq $true) 'events.subscribe request failed.'
    Assert-True ($subscribed.payload.subscribed -eq $true) 'Broker did not confirm wildcard EventBus subscription.'

    # Trigger a real asynchronous Files job on another pipe.
    $copy = Invoke-BrokerRpc -Method 'files.copy' -Payload @{
        sources = @($sourceFile)
        destination = $destinationDir
        overwritePolicy = 'ask'
    }
    Assert-True ($copy.ok -eq $true) "files.copy was rejected: $($copy | ConvertTo-Json -Compress)"
    $jobId = [string]$copy.payload.jobId
    Assert-True (-not [string]::IsNullOrWhiteSpace($jobId)) 'files.copy did not return a jobId.'

    $events = [System.Collections.Generic.List[string]]::new()
    $observedFrames = [System.Collections.Generic.List[string]]::new()
    $sawStarted = $false
    $sawCompleted = $false
    $sawWrongJob = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    try {
        while ([DateTime]::UtcNow -lt $deadline -and -not $sawCompleted) {
            $remainingRaw = [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds
            if ($remainingRaw -le 0) { break }
            $frame = Read-Frame -Stream $eventPipe -TimeoutMs ([Math]::Max(1, $remainingRaw))
            $frameType = [string]$frame.type
            $eventName = if ($null -ne $frame.PSObject.Properties['event']) { [string]$frame.event } else { '' }
            $eventJobId = if (
                $null -ne $frame.PSObject.Properties['payload'] -and
                $null -ne $frame.payload -and
                $null -ne $frame.payload.PSObject.Properties['jobId']
            ) { [string]$frame.payload.jobId } else { '' }
            $observedFrames.Add("$frameType|$eventName|$eventJobId")

            if ($frameType -ne 'event') { continue }
            if ($eventJobId -ne $jobId) {
                if (-not [string]::IsNullOrWhiteSpace($eventJobId)) { $sawWrongJob = $true }
                continue
            }
            $events.Add($eventName)
            if ($eventName -eq 'job.started') { $sawStarted = $true }
            if ($eventName -eq 'job.completed') { $sawCompleted = $true }
            if ($eventName -eq 'job.failed') {
                throw "Files job failed while validating EventBus: $($frame | ConvertTo-Json -Depth 10 -Compress)"
            }
        }
    }
    catch {
        $statusText = '<unavailable>'
        try {
            $status = Invoke-BrokerRpc -Method 'jobs.status' -Payload @{ jobId = $jobId }
            $statusText = $status | ConvertTo-Json -Depth 8 -Compress
        } catch {
            $statusText = "<status query failed: $($_.Exception.Message)>"
        }
        $framesText = if ($observedFrames.Count -eq 0) { '<none>' } else { $observedFrames -join ', ' }
        throw "EventBus delivery read failed for $jobId. Observed frames: $framesText. Job status: $statusText. Cause: $($_.Exception.Message)"
    }

    $framesText = if ($observedFrames.Count -eq 0) { '<none>' } else { $observedFrames -join ', ' }
    Assert-True $sawStarted "EventBus did not deliver job.started for $jobId. Observed: $framesText"
    Assert-True $sawCompleted "EventBus did not deliver job.completed for $jobId. Observed: $framesText"
    $copiedFile = Join-Path $destinationDir 'event-source.bin'
    Assert-True (Test-Path -LiteralPath $copiedFile) 'Files job reported completed but destination file is missing.'
    Assert-True ((Get-Item -LiteralPath $copiedFile).Length -eq 4 * 1024 * 1024) 'Copied file size mismatch.'

    $ping = Invoke-BrokerRpc -Method 'health.ping' -Payload @{}
    Assert-True ($ping.ok -eq $true -and $ping.payload.pong -eq $true) 'Broker stopped responding after EventBus job delivery.'

    $evidence = [ordered]@{
        schema = 233
        verdict = 'pass'
        protocol = 21
        wildcardSubscription = $true
        separateSubscriberPipe = $true
        trigger = 'files.copy'
        jobId = $jobId
        eventsForJob = @($events)
        observedFrames = @($observedFrames)
        jobStarted = $sawStarted
        jobCompleted = $sawCompleted
        unrelatedJobEventObserved = $sawWrongJob
        brokerResponsiveAfterDelivery = $true
        arbitraryCommandApi = $false
        completedUtc = [DateTime]::UtcNow.ToString('o')
    }
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding utf8
    Write-Host "[PASS] V23 EventBus named-pipe smoke passed. Evidence: $evidencePath" -ForegroundColor Green
}
finally {
    if ($null -ne $eventPipe) { $eventPipe.Dispose() }
    if ($null -ne $broker -and -not $broker.HasExited) {
        Stop-Process -Id $broker.Id -Force -ErrorAction SilentlyContinue
        $null = $broker.WaitForExit(3000)
    }
    Remove-Sandbox
}

exit 0
