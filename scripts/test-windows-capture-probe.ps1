[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string] $ExpectedHeadSha,

    [ValidateRange(1, 30)]
    [int] $CaptureSeconds = 3,

    [ValidateRange(1, 1000)]
    [int] $MinimumFrames = 10,

    [string] $OutputDirectory = (Join-Path (Get-Location) 'poc1-physical-evidence\windows-captured-surface')
)

$ErrorActionPreference = 'Stop'
$expectedBranch = 'poc/cloudos-windows-captured-surface'
$repoRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
$fixtureProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Fixture\CloudOS.WindowsCapture.Fixture.csproj'
$fixtureExe = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Fixture\bin\Release\net8.0-windows\CloudOS.WindowsCapture.Fixture.exe'
$probeProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Probe\CloudOS.WindowsCapture.Probe.csproj'
$probeDll = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Probe\bin\Release\net8.0-windows10.0.19041.0\CloudOS.WindowsCapture.Probe.dll'
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$windowReportPath = Join-Path $outputRoot 'fixture-window-wgc-smoke.json'
$monitorReportPath = Join-Path $outputRoot 'fixture-monitor-wgc-control.json'
$logPath = Join-Path $outputRoot 'fixture-wgc-smoke.log'

function Resolve-DotNet {
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $localDotNet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
    if (Test-Path -LiteralPath $localDotNet -PathType Leaf) { return $localDotNet }
    throw 'dotnet não foi encontrado.'
}

$currentHead = ([string](git rev-parse HEAD)).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $currentHead -ne $ExpectedHeadSha.ToLowerInvariant()) {
    throw "HEAD incorreto. esperado=$ExpectedHeadSha atual=$currentHead"
}
$branch = ([string](git branch --show-current)).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne $expectedBranch) {
    throw "Branch incorreta. esperado=$expectedBranch atual=$branch"
}

$dotnet = Resolve-DotNet
[System.IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$fixture = $null
$startedAt = [DateTimeOffset]::UtcNow

try {
    Write-Host 'Compilando fixture Windows convencional...' -ForegroundColor Cyan
    & $dotnet build $fixtureProject -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "Build da fixture falhou com exit code $LASTEXITCODE." }

    Write-Host 'Compilando CloudOS Windows capture probe...' -ForegroundColor Cyan
    & $dotnet build $probeProject -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "Build do capture probe falhou com exit code $LASTEXITCODE." }

    Write-Host 'Iniciando fixture WinForms animada...' -ForegroundColor Cyan
    $fixture = Start-Process -FilePath $fixtureExe -PassThru
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
    $reportedMainWindowHwnd = [IntPtr]::Zero
    do {
        Start-Sleep -Milliseconds 100
        $fixture.Refresh()
        if ($fixture.HasExited) { throw "Fixture encerrou prematuramente com exit code $($fixture.ExitCode)." }
        $reportedMainWindowHwnd = $fixture.MainWindowHandle
    } while ($reportedMainWindowHwnd -eq [IntPtr]::Zero -and [DateTimeOffset]::UtcNow -lt $deadline)
    if ($reportedMainWindowHwnd -eq [IntPtr]::Zero) { throw 'Fixture não publicou janela dentro do timeout.' }

    Write-Host "Fixture PID=$($fixture.Id) reported MainWindowHandle=0x$('{0:X}' -f $reportedMainWindowHwnd.ToInt64())" -ForegroundColor Cyan

    Write-Host '=== WINDOW TARGET ===' -ForegroundColor Cyan
    $windowOutput = & $dotnet $probeDll `
        --pid $fixture.Id `
        --capture-kind window `
        --seconds $CaptureSeconds `
        --min-frames $MinimumFrames `
        --output $windowReportPath 2>&1
    $windowExit = $LASTEXITCODE
    Write-Host ($windowOutput | Out-String)

    Write-Host '=== MONITOR CONTROL TARGET ===' -ForegroundColor Cyan
    $monitorOutput = & $dotnet $probeDll `
        --pid $fixture.Id `
        --capture-kind monitor `
        --seconds $CaptureSeconds `
        --min-frames $MinimumFrames `
        --output $monitorReportPath 2>&1
    $monitorExit = $LASTEXITCODE
    Write-Host ($monitorOutput | Out-String)

    $logLines = @(
        'CLOUDOS WINDOWS CAPTURE PROBE LOCAL SMOKE',
        "startedAt=$($startedAt.ToString('o'))",
        "completedAt=$([DateTimeOffset]::UtcNow.ToString('o'))",
        "branch=$branch",
        "head=$currentHead",
        'fixtureKind=winforms-overlapped-animated',
        "fixturePid=$($fixture.Id)",
        "fixtureReportedMainWindowHwnd=0x$('{0:X}' -f $reportedMainWindowHwnd.ToInt64())",
        'targetSelection=probe-enumerated-largest-visible-top-level-window-for-pid',
        "captureSeconds=$CaptureSeconds",
        "minimumFrames=$MinimumFrames",
        "windowProbeExitCode=$windowExit",
        "windowReport=$windowReportPath",
        "monitorProbeExitCode=$monitorExit",
        "monitorReport=$monitorReportPath",
        '',
        '=== WINDOW TARGET ===',
        ($windowOutput | Out-String).TrimEnd(),
        '',
        '=== MONITOR CONTROL TARGET ===',
        ($monitorOutput | Out-String).TrimEnd()
    )
    [System.IO.File]::WriteAllLines($logPath, $logLines, [System.Text.UTF8Encoding]::new($false))

    if ($windowExit -ne 0) {
        throw "Window capture gate falhou com exit code $windowExit. Monitor control exit=$monitorExit. Log: $logPath"
    }

    if (-not (Test-Path -LiteralPath $windowReportPath -PathType Leaf)) { throw 'Window probe terminou sem relatório JSON.' }
    $report = Get-Content -LiteralPath $windowReportPath -Raw | ConvertFrom-Json
    if ($report.verdict -ne 'PASS') { throw "Window probe reportou verdict=$($report.verdict)." }
    if ([long]$report.capture.frameCount -lt $MinimumFrames) { throw 'Frames insuficientes no window target.' }

    Write-Host ''
    Write-Host 'CLOUDOS WINDOWS CAPTURE WINDOW GATE: PASS' -ForegroundColor Green
    Write-Host "Frames: $($report.capture.frameCount)"
    Write-Host "Size:   $($report.capture.width)x$($report.capture.height)"
    Write-Host "Monitor control exit: $monitorExit"
    Write-Host "Window report:  $windowReportPath"
    Write-Host "Monitor report: $monitorReportPath"
    Write-Host "Log:            $logPath"
}
finally {
    if ($null -ne $fixture) {
        try {
            if (-not $fixture.HasExited) {
                $fixture.Kill($true)
                [void]$fixture.WaitForExit(5000)
            }
        }
        catch { Write-Warning "Falha ao encerrar fixture: $($_.Exception.Message)" }
        finally { $fixture.Dispose() }
    }
}
