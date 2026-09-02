# CloudOS V22.1 / V23 feature pass — real named-pipe text file smoke
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$brokerBin = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.SystemBroker.exe'
$sandbox = 'C:\CloudOS-V23-TextSmoke'
$expectedSandbox = [IO.Path]::GetFullPath($sandbox).TrimEnd('\')
$evidenceDirectory = Join-Path $repoRoot 'TestResults\v23-text-smoke'
$evidencePath = Join-Path $evidenceDirectory 'text-files-v23-smoke.json'
$requestCounter = 0
$results = [ordered]@{
    schema = 231
    startedUtc = [DateTime]::UtcNow.ToString('o')
    readUtf8 = 'not-run'
    multiChunkAtomicWrite = 'not-run'
    abort = 'not-run'
    oversizedChunk = 'not-run'
    utf16Rejected = 'not-run'
    brokerResponsive = 'not-run'
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Remove-TextSandbox {
    if (-not (Test-Path -LiteralPath $sandbox)) { return }
    $resolved = [IO.Path]::GetFullPath($sandbox).TrimEnd('\')
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($resolved, $expectedSandbox)) {
        throw "Refusing cleanup outside text smoke sandbox: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Read-Exact {
    param(
        [Parameter(Mandatory)]$Stream,
        [Parameter(Mandatory)][byte[]]$Buffer,
        [Parameter(Mandatory)][int]$Count
    )
    $offset = 0
    while ($offset -lt $Count) {
        $read = $Stream.Read($Buffer, $offset, $Count - $offset)
        if ($read -le 0) { throw "Broker pipe closed with $($Count - $offset) bytes still expected." }
        $offset += $read
    }
}

function Invoke-BrokerRpc {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][hashtable]$Payload
    )
    $script:requestCounter++
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $session = (Get-Process -Id $PID).SessionId
    $pipeName = "CloudOS.SystemBroker.v21.$sid.$session"
    $client = [IO.Pipes.NamedPipeClientStream]::new('.', $pipeName, [IO.Pipes.PipeDirection]::InOut)
    try {
        $client.Connect(3000)
        $request = [ordered]@{
            protocol = 21
            type = 'request'
            id = "text-smoke-$script:requestCounter"
            method = $Method
            payload = $Payload
        } | ConvertTo-Json -Depth 12 -Compress
        $bytes = [Text.Encoding]::UTF8.GetBytes($request)
        Assert-True ($bytes.Length -le 1048576) "Text smoke request exceeded protocol frame: $Method"
        $header = [BitConverter]::GetBytes([uint32]$bytes.Length)
        $client.Write($header, 0, $header.Length)
        if ($bytes.Length -gt 0) { $client.Write($bytes, 0, $bytes.Length) }
        $client.Flush()

        $responseHeader = [byte[]]::new(4)
        Read-Exact -Stream $client -Buffer $responseHeader -Count 4
        $responseLength = [BitConverter]::ToUInt32($responseHeader, 0)
        Assert-True ($responseLength -le 1048576) "Broker returned oversized response for $Method"
        $responseBytes = [byte[]]::new([int]$responseLength)
        if ($responseLength -gt 0) {
            Read-Exact -Stream $client -Buffer $responseBytes -Count ([int]$responseLength)
        }
        $json = [Text.Encoding]::UTF8.GetString($responseBytes)
        return ($json | ConvertFrom-Json -Depth 30)
    }
    finally {
        $client.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $brokerBin)) { throw "System Broker missing: $brokerBin" }
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null

Get-Process -Name 'CloudOS.SystemBroker' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 250
$broker = Start-Process -FilePath $brokerBin -PassThru -WindowStyle Hidden

try {
    Start-Sleep -Milliseconds 700
    $ping = Invoke-BrokerRpc -Method 'health.ping' -Payload @{}
    Assert-True ($ping.ok -eq $true -and $ping.payload.pong -eq $true) 'Initial Broker ping failed.'

    Remove-TextSandbox
    New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

    # 1. Real UTF-8 read through the typed RPC.
    $readPath = Join-Path $sandbox 'read-ação-😀.txt'
    $readExpected = "CloudOS ação 😀`nlinha dois"
    [IO.File]::WriteAllText($readPath, $readExpected, [Text.UTF8Encoding]::new($false))
    $read = Invoke-BrokerRpc -Method 'files.text.readChunk' -Payload @{
        path = $readPath
        offsetBytes = 0
        maxBytes = 65536
    }
    Assert-True ($read.ok -eq $true) "Broker-level read request failed: $($read | ConvertTo-Json -Compress)"
    Assert-True ($read.payload.ok -eq $true) "Typed text read failed: $($read.payload.message)"
    Assert-True ([string]$read.payload.content -eq $readExpected) 'UTF-8 text read content mismatch.'
    Assert-True ($read.payload.eof -eq $true) 'Small UTF-8 text read should finish in one chunk.'
    $results.readUtf8 = 'pass'

    # 2. Existing target must remain untouched until final chunk commits.
    $atomicPath = Join-Path $sandbox 'atomic.txt'
    [IO.File]::WriteAllText($atomicPath, 'ORIGINAL', [Text.UTF8Encoding]::new($false))
    $tx = 'atomic-smoke-001'
    $chunk1 = ('ação🙂-' * 4500)
    $chunk2 = ('fim-你好-' * 2500)
    $chunk1Bytes = [Text.Encoding]::UTF8.GetByteCount($chunk1)
    Assert-True ($chunk1Bytes -le 65536) 'Smoke chunk1 unexpectedly exceeds native chunk cap.'

    $write1 = Invoke-BrokerRpc -Method 'files.text.writeChunk' -Payload @{
        path = $atomicPath
        transactionId = $tx
        offsetBytes = 0
        content = $chunk1
        finalChunk = $false
        createParents = $false
        overwrite = $true
    }
    Assert-True ($write1.ok -eq $true -and $write1.payload.ok -eq $true) 'First text write chunk failed.'
    Assert-True ($write1.payload.committed -eq $false) 'First chunk committed before finalChunk.'
    Assert-True ([IO.File]::ReadAllText($atomicPath) -eq 'ORIGINAL') 'Target changed before atomic commit.'
    $tempPath = "$atomicPath.cloudos-write-$tx.tmp"
    Assert-True (Test-Path -LiteralPath $tempPath) 'Expected transactional temp file is missing before final commit.'

    $write2 = Invoke-BrokerRpc -Method 'files.text.writeChunk' -Payload @{
        path = $atomicPath
        transactionId = $tx
        offsetBytes = $chunk1Bytes
        content = $chunk2
        finalChunk = $true
        createParents = $false
        overwrite = $true
    }
    Assert-True ($write2.ok -eq $true -and $write2.payload.ok -eq $true) 'Final text write chunk failed.'
    Assert-True ($write2.payload.committed -eq $true) 'Final text chunk did not confirm atomic commit.'
    Assert-True (-not (Test-Path -LiteralPath $tempPath)) 'Committed text write left its transaction temp file.'
    Assert-True ([IO.File]::ReadAllText($atomicPath) -eq ($chunk1 + $chunk2)) 'Committed multi-chunk UTF-8 content mismatch.'
    $results.multiChunkAtomicWrite = 'pass'

    # 3. Abort must remove temp and never create the target.
    $abortPath = Join-Path $sandbox 'aborted.txt'
    $abortTx = 'abort-smoke-001'
    $abortWrite = Invoke-BrokerRpc -Method 'files.text.writeChunk' -Payload @{
        path = $abortPath
        transactionId = $abortTx
        offsetBytes = 0
        content = 'temporary content'
        finalChunk = $false
        createParents = $false
        overwrite = $true
    }
    Assert-True ($abortWrite.ok -eq $true -and $abortWrite.payload.ok -eq $true) 'Abort setup write failed.'
    $abortTemp = "$abortPath.cloudos-write-$abortTx.tmp"
    Assert-True (Test-Path -LiteralPath $abortTemp) 'Abort setup did not create transaction temp.'
    $abort = Invoke-BrokerRpc -Method 'files.text.abortWrite' -Payload @{
        path = $abortPath
        transactionId = $abortTx
    }
    Assert-True ($abort.ok -eq $true -and $abort.payload.ok -eq $true) 'Text abort RPC failed.'
    Assert-True (-not (Test-Path -LiteralPath $abortTemp)) 'Text abort left transaction temp behind.'
    Assert-True (-not (Test-Path -LiteralPath $abortPath)) 'Text abort unexpectedly created target file.'
    $results.abort = 'pass'

    # 4. Native cap is enforced below the 1 MiB protocol frame.
    $oversized = 'x' * 65537
    $tooLarge = Invoke-BrokerRpc -Method 'files.text.writeChunk' -Payload @{
        path = (Join-Path $sandbox 'too-large.txt')
        transactionId = 'too-large-smoke'
        offsetBytes = 0
        content = $oversized
        finalChunk = $true
        createParents = $false
        overwrite = $true
    }
    Assert-True ($tooLarge.ok -eq $true) 'Oversized typed chunk should be a controlled service-level rejection.'
    Assert-True ($tooLarge.payload.ok -eq $false -and $tooLarge.payload.error -eq 'out_of_range') 'Oversized typed chunk was not rejected with out_of_range.'
    $results.oversizedChunk = 'pass'

    # 5. UTF-16 is rejected instead of being silently corrupted as UTF-8.
    $utf16Path = Join-Path $sandbox 'utf16.txt'
    [IO.File]::WriteAllText($utf16Path, 'texto utf16', [Text.Encoding]::Unicode)
    $utf16 = Invoke-BrokerRpc -Method 'files.text.readChunk' -Payload @{
        path = $utf16Path
        offsetBytes = 0
        maxBytes = 65536
    }
    Assert-True ($utf16.ok -eq $true) 'UTF-16 rejection should remain a controlled service response.'
    Assert-True ($utf16.payload.ok -eq $false -and $utf16.payload.error -eq 'unsupported_encoding') 'UTF-16 file was not explicitly rejected.'
    $results.utf16Rejected = 'pass'

    $finalPing = Invoke-BrokerRpc -Method 'health.ping' -Payload @{}
    Assert-True ($finalPing.ok -eq $true -and $finalPing.payload.pong -eq $true) 'Broker stopped responding after text-file smoke.'
    $results.brokerResponsive = 'pass'
    $results.completedUtc = [DateTime]::UtcNow.ToString('o')
    $results.verdict = 'pass'
    $results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $evidencePath -Encoding utf8
    Write-Host "[PASS] Typed text-file V23 smoke passed. Evidence: $evidencePath" -ForegroundColor Green
}
finally {
    if ($null -ne $broker -and -not $broker.HasExited) {
        Stop-Process -Id $broker.Id -Force -ErrorAction SilentlyContinue
        $null = $broker.WaitForExit(3000)
    }
    Remove-TextSandbox
}

exit 0
