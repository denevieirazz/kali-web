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
$hostTestsProject = Join-Path $repoRoot 'desktop\CloudOS.Host.Tests\CloudOS.Host.Tests.csproj'
$fixtureExe = Join-Path $repoRoot 'desktop\CloudOS.Host.Tests\bin\Release\net8.0\CloudOS.Host.Tests.exe'
$probeProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Probe\CloudOS.WindowsCapture.Probe.csproj'
$probeDll = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Probe\bin\Release\net8.0-windows10.0.19041.0\CloudOS.WindowsCapture.Probe.dll'
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$reportPath = Join-Path $outputRoot 'fixture-wgc-smoke.json'
$logPath = Join-Path $outputRoot 'fixture-wgc-smoke.log'

function Resolve-DotNet {
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $localDotNet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
    if (Test-Path -LiteralPath $localDotNet -PathType Leaf) { return $localDotNet }

    throw 'dotnet não foi encontrado no PATH nem em %LOCALAPPDATA%\Microsoft\dotnet\dotnet.exe.'
}

$currentHead = @(git rev-parse HEAD)
if ($LASTEXITCODE -ne 0 -or $currentHead.Count -ne 1) {
    throw 'Não foi possível determinar o HEAD atual.'
}
$currentHead = ([string]$currentHead[0]).Trim().ToLowerInvariant()
if ($currentHead -ne $ExpectedHeadSha.ToLowerInvariant()) {
    throw "HEAD incorreto. esperado=$ExpectedHeadSha atual=$currentHead"
}

$branch = @(git branch --show-current)
if ($LASTEXITCODE -ne 0 -or $branch.Count -ne 1) { throw 'Não foi possível determinar a branch atual.' }
$branch = ([string]$branch[0]).Trim()
if ($branch -ne $expectedBranch) {
    throw "Branch incorreta para a prova de captura. esperado=$expectedBranch atual=$branch"
}

$dotnet = Resolve-DotNet
[System.IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$fixture = $null
$startedAt = [DateTimeOffset]::UtcNow

try {
    Write-Host 'Compilando fixture Win32...' -ForegroundColor Cyan
    & $dotnet build $hostTestsProject -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "Build da fixture falhou com exit code $LASTEXITCODE." }
    if (-not (Test-Path -LiteralPath $fixtureExe -PathType Leaf)) { throw "Fixture não encontrada: $fixtureExe" }

    Write-Host 'Compilando CloudOS Windows capture probe...' -ForegroundColor Cyan
    & $dotnet build $probeProject -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "Build do capture probe falhou com exit code $LASTEXITCODE." }
    if (-not (Test-Path -LiteralPath $probeDll -PathType Leaf)) { throw "Probe não encontrado: $probeDll" }

    Write-Host 'Iniciando fixture Win32 real...' -ForegroundColor Cyan
    $fixture = Start-Process -FilePath $fixtureExe -ArgumentList '--native-contained-fixture-window' -PassThru
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
    $reportedMainWindowHwnd = [IntPtr]::Zero
    do {
        Start-Sleep -Milliseconds 100
        $fixture.Refresh()
        if ($fixture.HasExited) { throw "Fixture encerrou prematuramente com exit code $($fixture.ExitCode)." }
        $reportedMainWindowHwnd = $fixture.MainWindowHandle
    } while ($reportedMainWindowHwnd -eq [IntPtr]::Zero -and [DateTimeOffset]::UtcNow -lt $deadline)

    if ($reportedMainWindowHwnd -eq [IntPtr]::Zero) { throw 'Fixture não publicou nenhuma janela dentro do timeout.' }

    # IMPORTANT: Process.MainWindowHandle is not authoritative for a console-hosted test process.
    # It can identify a console/ConPTY window instead of the Win32 fixture HWND. The capture probe
    # owns target selection: given the fixture PID it enumerates visible top-level HWNDs belonging
    # to that process and selects the largest candidate by native window bounds.
    Write-Host "Fixture PID=$($fixture.Id) reported MainWindowHandle=0x$('{0:X}' -f $reportedMainWindowHwnd.ToInt64())" -ForegroundColor Cyan
    Write-Host 'Executando Windows.Graphics.Capture...' -ForegroundColor Cyan
    $probeOutput = & $dotnet $probeDll `
        --pid $fixture.Id `
        --seconds $CaptureSeconds `
        --min-frames $MinimumFrames `
        --output $reportPath 2>&1
    $probeExit = $LASTEXITCODE

    $logLines = @(
        'CLOUDOS WINDOWS CAPTURE PROBE LOCAL SMOKE',
        "startedAt=$($startedAt.ToString('o'))",
        "completedAt=$([DateTimeOffset]::UtcNow.ToString('o'))",
        "branch=$branch",
        "head=$currentHead",
        "fixturePid=$($fixture.Id)",
        "fixtureReportedMainWindowHwnd=0x$('{0:X}' -f $reportedMainWindowHwnd.ToInt64())",
        'targetSelection=probe-enumerated-largest-visible-top-level-window-for-pid',
        "captureSeconds=$CaptureSeconds",
        "minimumFrames=$MinimumFrames",
        "probeExitCode=$probeExit",
        "report=$reportPath",
        '',
        ($probeOutput | Out-String).TrimEnd()
    )
    [System.IO.File]::WriteAllLines($logPath, $logLines, [System.Text.UTF8Encoding]::new($false))

    if ($probeExit -ne 0) {
        Write-Host ($probeOutput | Out-String)
        throw "Windows capture probe falhou com exit code $probeExit. Log: $logPath"
    }

    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw 'Probe terminou sem gerar o relatório JSON.' }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($report.verdict -ne 'PASS') { throw "Probe reportou verdict=$($report.verdict)." }
    if ([long]$report.capture.frameCount -lt $MinimumFrames) {
        throw "Frames insuficientes. atual=$($report.capture.frameCount) mínimo=$MinimumFrames"
    }

    Write-Host ''
    Write-Host 'CLOUDOS WINDOWS CAPTURE PROBE LOCAL SMOKE: PASS' -ForegroundColor Green
    Write-Host "Target HWND: $($report.window.handle)"
    Write-Host "Target size: $($report.window.width)x$($report.window.height)"
    Write-Host "Frames: $($report.capture.frameCount)"
    Write-Host "Size:   $($report.capture.width)x$($report.capture.height)"
    Write-Host "Initial item:   $($report.capture.initialItemSize.width)x$($report.capture.initialItemSize.height)"
    Write-Host "Initial buffer: $($report.capture.initialBufferSize.width)x$($report.capture.initialBufferSize.height) via $($report.capture.initialBufferSize.source)"
    Write-Host "Empty frames:   $($report.capture.emptyFrameCount)"
    Write-Host "Report: $reportPath"
    Write-Host "Log:    $logPath"
}
finally {
    if ($null -ne $fixture) {
        try {
            if (-not $fixture.HasExited) {
                $fixture.Kill($true)
                [void]$fixture.WaitForExit(5000)
            }
        }
        catch {
            Write-Warning "Não foi possível encerrar a fixture automaticamente: $($_.Exception.Message)"
        }
        finally {
            $fixture.Dispose()
        }
    }
}
