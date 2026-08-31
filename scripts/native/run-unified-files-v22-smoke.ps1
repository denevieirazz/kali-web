# run-unified-files-v22-smoke.ps1
# Destructive operations are restricted to the two V22 bug-bash sandboxes.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$brokerBin = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.SystemBroker.exe'
$probeBin = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.BrokerProbe.exe'
$sandbox = 'C:\CloudOS-V22-BugBash'
$expectedSandbox = [IO.Path]::GetFullPath('C:\CloudOS-V22-BugBash').TrimEnd('\')
$evidenceDirectory = Join-Path $repoRoot 'TestResults\v22.1-bug-bash'
$results = [ordered]@{ schema = 221; startedUtc = [DateTime]::UtcNow.ToString('o'); singleInstance = 'not-run'; ipcFuzz = 'not-run'; windowsSandbox = 'not-run'; unicode = 'not-run'; longPath = 'not-run'; reparseBoundary = 'not-run'; copyMove = 'not-run'; conflicts = 'not-run'; cancellation = 'not-run'; openWith = 'not-run'; wslSandbox = 'not-tested'; windowsToLinux = 'not-tested'; linuxToWindows = 'not-tested' }

function Assert-True { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw $Message } }
function Remove-WindowsSandbox {
    if (-not (Test-Path -LiteralPath $sandbox)) { return }
    $resolved = [IO.Path]::GetFullPath($sandbox).TrimEnd('\')
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($resolved, $expectedSandbox)) { throw "Refusing recursive cleanup outside V22 sandbox: $resolved" }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
function Invoke-ProbeJson {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & $probeBin @Arguments
    if ($LASTEXITCODE -ne 0) { throw "BrokerProbe failed ($LASTEXITCODE): $($Arguments -join ' ')`n$output" }
    return ($output | Out-String | ConvertFrom-Json -Depth 40)
}
function Wait-CloudOSJob {
    param([Parameter(Mandatory)][string]$JobId, [ValidateSet('completed', 'failed', 'cancelled')][string]$Expected = 'completed', [int]$TimeoutSeconds = 30)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $response = Invoke-ProbeJson -Arguments @('job-status', $JobId)
        $state = [string]$response.payload.state
        if ($state -in @('completed', 'failed', 'cancelled')) {
            Assert-True ($state -eq $Expected) "Job $JobId ended as '$state', expected '$Expected': $($response.payload.error)"
            return $response.payload
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out waiting for job $JobId"
}
function Invoke-RawBrokerFrame {
    param([string]$Payload, [uint32]$DeclaredLength = [uint32]::MaxValue)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $session = (Get-Process -Id $PID).SessionId
    $pipeName = "CloudOS.SystemBroker.v21.$sid.$session"
    $client = [IO.Pipes.NamedPipeClientStream]::new('.', $pipeName, [IO.Pipes.PipeDirection]::InOut)
    try {
        $client.Connect(2000)
        $bytes = [Text.Encoding]::UTF8.GetBytes($Payload)
        $length = if ($DeclaredLength -eq [uint32]::MaxValue) { [uint32]$bytes.Length } else { $DeclaredLength }
        $header = [BitConverter]::GetBytes($length)
        $client.Write($header, 0, $header.Length)
        if ($DeclaredLength -eq [uint32]::MaxValue -and $bytes.Length -gt 0) { $client.Write($bytes, 0, $bytes.Length) }
        $client.Flush()
        if ($DeclaredLength -gt 1048576) { return }
        $responseHeader = [byte[]]::new(4); $offset = 0
        while ($offset -lt 4) { $read = $client.Read($responseHeader, $offset, 4 - $offset); if ($read -le 0) { throw 'Broker closed before controlled error response.' }; $offset += $read }
        $responseLength = [BitConverter]::ToUInt32($responseHeader, 0)
        Assert-True ($responseLength -le 1048576) 'Broker returned oversized fuzz response.'
        $responseBytes = [byte[]]::new($responseLength); $offset = 0
        while ($offset -lt $responseLength) { $read = $client.Read($responseBytes, $offset, $responseLength - $offset); if ($read -le 0) { throw 'Truncated fuzz response.' }; $offset += $read }
        return ([Text.Encoding]::UTF8.GetString($responseBytes) | ConvertFrom-Json -Depth 20)
    }
    finally { $client.Dispose() }
}

if (-not (Test-Path -LiteralPath $brokerBin)) { throw "System Broker missing: $brokerBin" }
if (-not (Test-Path -LiteralPath $probeBin)) { throw "BrokerProbe missing: $probeBin" }
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
Write-Host '[SMOKE-V22.1] Running System Broker self-test...' -ForegroundColor Cyan
& $brokerBin --self-test
if ($LASTEXITCODE -ne 0) { throw "SystemBroker --self-test failed: $LASTEXITCODE" }
Get-Process -Name 'CloudOS.SystemBroker' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300
$brokerProc = Start-Process -FilePath $brokerBin -PassThru -WindowStyle Hidden

try {
    Start-Sleep -Milliseconds 800
    Assert-True ((Invoke-ProbeJson -Arguments @('ping')).ok -eq $true) 'Broker ping failed.'
    $duplicateBroker = Start-Process -FilePath $brokerBin -PassThru -WindowStyle Hidden
    Assert-True ($duplicateBroker.WaitForExit(5000)) 'Second broker instance did not exit promptly.'
    Assert-True ($duplicateBroker.ExitCode -ne 0) 'Second broker instance unexpectedly acquired the singleton.'
    $results.singleInstance = 'pass'
    $fuzzPayloads = @(
        '',
        '{not-json',
        '{"protocol":21,"type":"request","id":"missing-method","payload":{}}',
        '{"protocol":"wrong","type":"request","id":"wrong-type","method":"health.ping","payload":[]}',
        ('{"protocol":21,"type":"request","id":"' + ('x' * 65536) + '","method":"health.ping","payload":{}}'),
        '{"protocol":21,"type":"request","id":"unicode-你好-😀","method":"unknown.ação","payload":{}}'
    )
    foreach ($payload in $fuzzPayloads) {
        $fuzzResponse = Invoke-RawBrokerFrame -Payload $payload
        Assert-True ($null -ne $fuzzResponse -and $fuzzResponse.ok -eq $false) 'Malformed IPC request was not rejected cleanly.'
        Assert-True ((Invoke-ProbeJson -Arguments @('ping')).ok -eq $true) 'Broker died after malformed IPC request.'
    }
    Invoke-RawBrokerFrame -Payload '' -DeclaredLength 1048577
    Start-Sleep -Milliseconds 100
    Assert-True ((Invoke-ProbeJson -Arguments @('ping')).ok -eq $true) 'Broker died after oversized IPC frame.'
    $results.ipcFuzz = 'pass'
    Remove-WindowsSandbox
    New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
    $source = Join-Path $sandbox 'Source'; $nested = Join-Path $source 'nested'; $copyTarget = Join-Path $sandbox 'CopyTarget'; $moveTarget = Join-Path $sandbox 'MoveTarget'; $linuxInbound = Join-Path $sandbox 'FromLinux'
    New-Item -ItemType Directory -Path $nested, $copyTarget, $moveTarget, $linuxInbound -Force | Out-Null
    1..100 | ForEach-Object { Set-Content -LiteralPath (Join-Path $source ("file-{0:D3}.txt" -f $_)) -Value "CloudOS $_" -Encoding utf8 }
    1..1000 | ForEach-Object { Set-Content -LiteralPath (Join-Path $nested ("bulk-{0:D4}.dat" -f $_)) -Value $_ -Encoding ascii }
    foreach ($name in @('ação.txt', 'coração.md', '你好.txt', '日本語.txt', '😀.txt', 'sem-extensão', 'muitos.pontos.no.nome.json')) { Set-Content -LiteralPath (Join-Path $source $name) -Value $name -Encoding utf8 }
    New-Item -ItemType Directory -Path (Join-Path $source 'Pasta ação'), (Join-Path $source '目录'), (Join-Path $source '😀 pasta') -Force | Out-Null
    $hidden = Get-Item -LiteralPath (Join-Path $source 'file-001.txt'); $hidden.Attributes = $hidden.Attributes -bor [IO.FileAttributes]::Hidden
    $readOnly = Get-Item -LiteralPath (Join-Path $source 'file-002.txt'); $readOnly.IsReadOnly = $true
    $listing = Invoke-ProbeJson -Arguments @('list', $source)
    Assert-True ($listing.payload.totalItems -ge 109) 'Sandbox listing item count is wrong.'
    foreach ($name in @('ação.txt', 'coração.md', '你好.txt', '日本語.txt', '😀.txt')) {
        $metadata = Invoke-ProbeJson -Arguments @('metadata', (Join-Path $source $name))
        Assert-True ($metadata.payload.name -eq $name) "UTF-8/UTF-16 roundtrip failed for $name"
    }
    $results.windowsSandbox = 'pass'; $results.unicode = 'pass'
    foreach ($invalidName in @('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'LPT1', 'bad:name')) {
        $invalid = Invoke-ProbeJson -Arguments @('create-folder', $sandbox, $invalidName)
        Assert-True ($invalid.payload.ok -eq $false -and $invalid.payload.error -eq 'invalid_name') "Invalid Windows name accepted: $invalidName"
    }
    $longPath = Join-Path $sandbox 'LongPath'; New-Item -ItemType Directory -Path $longPath -Force | Out-Null
    1..6 | ForEach-Object { $longPath = Join-Path $longPath (('segment-{0}-' -f $_) + ('x' * 42)); New-Item -ItemType Directory -Path $longPath -Force | Out-Null }
    $longFile = Join-Path $longPath 'ação-long-path.txt'; Set-Content -LiteralPath $longFile -Value 'long path' -Encoding utf8
    Assert-True ((Invoke-ProbeJson -Arguments @('metadata', $longFile)).payload.name -eq 'ação-long-path.txt') 'Long path metadata failed.'
    $results.longPath = 'pass'
    $junctionPath = Join-Path $nested 'junction-loop'
    try {
        New-Item -ItemType Junction -Path $junctionPath -Target $source -ErrorAction Stop | Out-Null
        $search = Invoke-ProbeJson -Arguments @('search', $source, 'never-match-this')
        $null = Wait-CloudOSJob -JobId ([string]$search.payload.jobId)
        $results.reparseBoundary = 'pass'
    } catch { $results.reparseBoundary = "not-tested: $($_.Exception.Message)" }
    if (Test-Path -LiteralPath $junctionPath) { Remove-Item -LiteralPath $junctionPath -Force }
    $copy = Invoke-ProbeJson -Arguments @('copy', $source, $copyTarget, 'ask')
    $null = Wait-CloudOSJob -JobId ([string]$copy.payload.jobId) -TimeoutSeconds 60
    Assert-True (Test-Path -LiteralPath (Join-Path $copyTarget 'Source\nested\bulk-1000.dat')) 'Recursive copy lost nested content.'
    $moveSource = Join-Path $sandbox 'move-me-ação.txt'; Set-Content -LiteralPath $moveSource -Value 'move' -Encoding utf8
    $move = Invoke-ProbeJson -Arguments @('move', $moveSource, $moveTarget, 'ask')
    $null = Wait-CloudOSJob -JobId ([string]$move.payload.jobId)
    Assert-True (-not (Test-Path -LiteralPath $moveSource)) 'Move left original file.'
    Assert-True (Test-Path -LiteralPath (Join-Path $moveTarget 'move-me-ação.txt')) 'Move destination missing.'
    $results.copyMove = 'pass'
    $conflict = Invoke-ProbeJson -Arguments @('copy', $source, $sandbox, 'ask')
    $null = Wait-CloudOSJob -JobId ([string]$conflict.payload.jobId) -Expected failed
    $results.conflicts = 'pass'
    $largeFile = Join-Path $sandbox 'cancel-source.bin'
    $stream = [IO.File]::Open($largeFile, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.SetLength(536870912) } finally { $stream.Dispose() }
    $cancelTarget = Join-Path $sandbox 'CancelTarget'; New-Item -ItemType Directory -Path $cancelTarget -Force | Out-Null
    $cancelCopy = Invoke-ProbeJson -Arguments @('copy', $largeFile, $cancelTarget, 'ask')
    $cancel = Invoke-ProbeJson -Arguments @('job-cancel', ([string]$cancelCopy.payload.jobId))
    Assert-True ($cancel.payload.cancelled -eq $true) 'Running copy job did not accept cancellation.'
    $null = Wait-CloudOSJob -JobId ([string]$cancelCopy.payload.jobId) -Expected cancelled
    Assert-True (@(Get-ChildItem -LiteralPath $cancelTarget -Filter '*.cloudos-copy-*' -Force).Count -eq 0) 'Cancelled copy left a temporary file.'
    $results.cancellation = 'pass'
    $openWith = Invoke-ProbeJson -Arguments @('open-with', (Join-Path $source 'ação.txt'))
    Assert-True ($openWith.payload.apps.Count -ge 1) 'Open With did not return Windows chooser.'
    $ubuntuPresent = (& wsl.exe --list --quiet 2>$null) -contains 'Ubuntu'
    if ($ubuntuPresent) {
        & wsl.exe -d Ubuntu -- which gimp *> $null; $gimpInstalled = $LASTEXITCODE -eq 0
        $advertisesGimp = @($openWith.payload.apps | Where-Object { $_.appId -eq 'wsl:Ubuntu:gimp' }).Count -gt 0
        Assert-True ($advertisesGimp -eq $gimpInstalled) 'GIMP advertisement differs from real Ubuntu installation.'
    }
    $results.openWith = 'pass'
    if ($ubuntuPresent) {
        & wsl.exe -d Ubuntu -- sh -lc 'rm -rf -- "$HOME/cloudos-v22-bugbash"; mkdir -p -- "$HOME/cloudos-v22-bugbash/inbound" "$HOME/cloudos-v22-bugbash/outbound"; printf linux > "$HOME/cloudos-v22-bugbash/outbound/ação-linux.txt"'
        if ($LASTEXITCODE -ne 0) { throw 'Failed to create Ubuntu V22 sandbox.' }
        $linuxHome = (& wsl.exe -d Ubuntu -- sh -lc 'printf %s "$HOME"').Trim()
        $linuxSandbox = "\\wsl.localhost\Ubuntu$($linuxHome.Replace('/', '\'))\cloudos-v22-bugbash"
        Assert-True ((Invoke-ProbeJson -Arguments @('list', $linuxSandbox)).payload.locationKind -eq 'wsl') 'WSL path classification failed.'
        $results.wslSandbox = 'pass'
        $windowsToLinuxSource = Join-Path $sandbox 'windows-to-linux-ação.txt'; Set-Content -LiteralPath $windowsToLinuxSource -Value 'windows' -Encoding utf8
        $toLinux = Invoke-ProbeJson -Arguments @('copy', $windowsToLinuxSource, (Join-Path $linuxSandbox 'inbound'), 'ask')
        $null = Wait-CloudOSJob -JobId ([string]$toLinux.payload.jobId) -TimeoutSeconds 60
        Assert-True (Test-Path -LiteralPath (Join-Path $linuxSandbox 'inbound\windows-to-linux-ação.txt')) 'Windows to Linux copy failed.'
        $results.windowsToLinux = 'pass'
        $toWindows = Invoke-ProbeJson -Arguments @('copy', (Join-Path $linuxSandbox 'outbound\ação-linux.txt'), $linuxInbound, 'ask')
        $null = Wait-CloudOSJob -JobId ([string]$toWindows.payload.jobId) -TimeoutSeconds 60
        Assert-True (Test-Path -LiteralPath (Join-Path $linuxInbound 'ação-linux.txt')) 'Linux to Windows copy failed.'
        $results.linuxToWindows = 'pass'
    }
    Write-Host '[SMOKE-V22.1] Heavy Windows/WSL file bug bash: PASS' -ForegroundColor Green
}
finally {
    if ($brokerProc -and -not $brokerProc.HasExited) { Stop-Process -Id $brokerProc.Id -Force -ErrorAction SilentlyContinue }
    if ((& wsl.exe --list --quiet 2>$null) -contains 'Ubuntu') { & wsl.exe -d Ubuntu -- sh -lc 'rm -rf -- "$HOME/cloudos-v22-bugbash"' 2>$null }
    Remove-WindowsSandbox
    $results.finishedUtc = [DateTime]::UtcNow.ToString('o')
    $results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'unified-files-v22.1-smoke.json') -Encoding utf8
}
