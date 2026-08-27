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
$windowRawReportPath = Join-Path $outputRoot 'fixture-window-wgc-smoke.json'
$windowProjectedReportPath = Join-Path $outputRoot 'fixture-window-projected-control.json'
$monitorRawReportPath = Join-Path $outputRoot 'fixture-monitor-wgc-control.json'
$logPath = Join-Path $outputRoot 'fixture-wgc-smoke.log'
$summaryPath = Join-Path $outputRoot 'fixture-wgc-matrix-summary.json'

function Resolve-DotNet {
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $localDotNet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
    if (Test-Path -LiteralPath $localDotNet -PathType Leaf) { return $localDotNet }
    throw 'dotnet não foi encontrado.'
}

function Invoke-ProbeLane {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [ValidateSet('window', 'monitor')] [string] $CaptureKind,
        [Parameter(Mandatory)] [ValidateSet('raw', 'projected')] [string] $ItemFactory,
        [Parameter(Mandatory)] [string] $ReportPath,
        [Parameter(Mandatory)] [int] $ProcessId
    )

    Remove-Item -LiteralPath $ReportPath -Force -ErrorAction SilentlyContinue
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    $output = & $dotnet $probeDll `
        --pid $ProcessId `
        --capture-kind $CaptureKind `
        --item-factory $ItemFactory `
        --seconds $CaptureSeconds `
        --min-frames $MinimumFrames `
        --output $ReportPath 2>&1
    $exitCode = $LASTEXITCODE
    Write-Host ($output | Out-String)

    $report = $null
    if (Test-Path -LiteralPath $ReportPath -PathType Leaf) {
        try { $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json }
        catch { Write-Warning "Relatório inválido em $ReportPath : $($_.Exception.Message)" }
    }

    return [pscustomobject]@{
        name = $Name
        captureKind = $CaptureKind
        itemFactory = $ItemFactory
        exitCode = $exitCode
        reportPath = $ReportPath
        report = $report
        output = ($output | Out-String).TrimEnd()
    }
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

    # One physical run, three deliberately isolated lanes:
    # 1. Product candidate: HWND through raw WinRT activation factory ABI.
    # 2. Legacy control: same HWND through the old projected/RCW factory path.
    # 3. Lower-layer control: monitor through the same raw activation factory and D3D/frame-pool path.
    $windowRaw = Invoke-ProbeLane `
        -Name 'WINDOW / RAW ACTIVATION FACTORY (PRODUCT GATE)' `
        -CaptureKind window `
        -ItemFactory raw `
        -ReportPath $windowRawReportPath `
        -ProcessId $fixture.Id

    $windowProjected = Invoke-ProbeLane `
        -Name 'WINDOW / PROJECTED FACTORY (LEGACY CONTROL)' `
        -CaptureKind window `
        -ItemFactory projected `
        -ReportPath $windowProjectedReportPath `
        -ProcessId $fixture.Id

    $monitorRaw = Invoke-ProbeLane `
        -Name 'MONITOR / RAW ACTIVATION FACTORY (LOWER-LAYER CONTROL)' `
        -CaptureKind monitor `
        -ItemFactory raw `
        -ReportPath $monitorRawReportPath `
        -ProcessId $fixture.Id

    $completedAt = [DateTimeOffset]::UtcNow

    function Lane-Summary($lane) {
        $report = $lane.report
        return [ordered]@{
            name = $lane.name
            captureKind = $lane.captureKind
            itemFactory = $lane.itemFactory
            exitCode = $lane.exitCode
            reportGenerated = ($null -ne $report)
            verdict = if ($null -ne $report) { $report.verdict } else { $null }
            frameCount = if ($null -ne $report -and $null -ne $report.capture) { [long]$report.capture.frameCount } else { 0 }
            width = if ($null -ne $report -and $null -ne $report.capture) { [int]$report.capture.width } else { 0 }
            height = if ($null -ne $report -and $null -ne $report.capture) { [int]$report.capture.height } else { 0 }
            stage = if ($null -ne $report -and $null -ne $report.error) { $report.error.stage } else { $null }
            nativeHResult = if ($null -ne $report -and $null -ne $report.error) { $report.error.nativeHResult } else { $null }
            itemWidth = if ($null -ne $report -and $null -ne $report.error) { [int]$report.error.itemWidth } elseif ($null -ne $report -and $null -ne $report.capture) { [int]$report.capture.initialItemWidth } else { 0 }
            itemHeight = if ($null -ne $report -and $null -ne $report.error) { [int]$report.error.itemHeight } elseif ($null -ne $report -and $null -ne $report.capture) { [int]$report.capture.initialItemHeight } else { 0 }
            bufferWidth = if ($null -ne $report -and $null -ne $report.error) { [int]$report.error.bufferWidth } elseif ($null -ne $report -and $null -ne $report.capture) { [int]$report.capture.initialBufferWidth } else { 0 }
            bufferHeight = if ($null -ne $report -and $null -ne $report.error) { [int]$report.error.bufferHeight } elseif ($null -ne $report -and $null -ne $report.capture) { [int]$report.capture.initialBufferHeight } else { 0 }
            initialSizeSource = if ($null -ne $report -and $null -ne $report.error) { $report.error.initialSizeSource } elseif ($null -ne $report -and $null -ne $report.capture) { $report.capture.initialSizeSource } else { $null }
            reportPath = $lane.reportPath
        }
    }

    $summary = [ordered]@{
        schemaVersion = 1
        probeMatrix = 'CloudOS Windows captured-surface factory isolation'
        startedAt = $startedAt.ToString('o')
        completedAt = $completedAt.ToString('o')
        branch = $branch
        head = $currentHead
        fixtureKind = 'winforms-overlapped-animated'
        fixturePid = $fixture.Id
        fixtureReportedMainWindowHwnd = ('0x{0:X}' -f $reportedMainWindowHwnd.ToInt64())
        minimumFrames = $MinimumFrames
        captureSeconds = $CaptureSeconds
        productGate = 'window/raw-activation-factory'
        productGatePassed = ($windowRaw.exitCode -eq 0 -and $null -ne $windowRaw.report -and $windowRaw.report.verdict -eq 'PASS')
        lanes = @(
            (Lane-Summary $windowRaw),
            (Lane-Summary $windowProjected),
            (Lane-Summary $monitorRaw)
        )
    }

    $summaryJson = $summary | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($summaryPath, $summaryJson + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

    $logLines = @(
        'CLOUDOS WINDOWS CAPTURE FULL FACTORY ISOLATION',
        "startedAt=$($startedAt.ToString('o'))",
        "completedAt=$($completedAt.ToString('o'))",
        "branch=$branch",
        "head=$currentHead",
        'fixtureKind=winforms-overlapped-animated',
        "fixturePid=$($fixture.Id)",
        "fixtureReportedMainWindowHwnd=0x$('{0:X}' -f $reportedMainWindowHwnd.ToInt64())",
        'targetSelection=probe-enumerated-largest-visible-top-level-window-for-pid',
        "captureSeconds=$CaptureSeconds",
        "minimumFrames=$MinimumFrames",
        "windowRawExitCode=$($windowRaw.exitCode)",
        "windowProjectedExitCode=$($windowProjected.exitCode)",
        "monitorRawExitCode=$($monitorRaw.exitCode)",
        "windowRawReport=$windowRawReportPath",
        "windowProjectedReport=$windowProjectedReportPath",
        "monitorRawReport=$monitorRawReportPath",
        "matrixSummary=$summaryPath",
        '',
        '=== WINDOW / RAW ACTIVATION FACTORY (PRODUCT GATE) ===',
        $windowRaw.output,
        '',
        '=== WINDOW / PROJECTED FACTORY (LEGACY CONTROL) ===',
        $windowProjected.output,
        '',
        '=== MONITOR / RAW ACTIVATION FACTORY (LOWER-LAYER CONTROL) ===',
        $monitorRaw.output,
        '',
        '=== MATRIX SUMMARY ===',
        $summaryJson
    )
    [System.IO.File]::WriteAllLines($logPath, $logLines, [System.Text.UTF8Encoding]::new($false))

    Write-Host ''
    Write-Host '=== FACTORY ISOLATION SUMMARY ===' -ForegroundColor Cyan
    Write-Host $summaryJson
    Write-Host "Summary: $summaryPath"
    Write-Host "Log:     $logPath"

    if (-not $summary.productGatePassed) {
        throw "Window/raw activation-factory product gate falhou. Evidence: $summaryPath ; $logPath"
    }

    Write-Host ''
    Write-Host 'CLOUDOS WINDOWS CAPTURE WINDOW/RAW PRODUCT GATE: PASS' -ForegroundColor Green
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
