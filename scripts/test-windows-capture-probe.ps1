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
$expectedBranches = @('poc/cloudos-windows-captured-surface', 'integration/cloudos-unified-runtime')
$repoRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
$fixtureProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Fixture\CloudOS.WindowsCapture.Fixture.csproj'
$fixtureExe = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Fixture\bin\Release\net8.0-windows\CloudOS.WindowsCapture.Fixture.exe'
$probeProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Probe\CloudOS.WindowsCapture.Probe.csproj'
$probeDll = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Probe\bin\Release\net8.0-windows10.0.19041.0\CloudOS.WindowsCapture.Probe.dll'
$nativeProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.NativeReference\CloudOS.WindowsCapture.NativeReference.vcxproj'
$nativeExe = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.NativeReference\bin\Release\x64\CloudOS.WindowsCapture.NativeReference.exe'
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$productReportPath = Join-Path $outputRoot 'fixture-window-product-candidate.json'
$lifetimeControlPath = Join-Path $outputRoot 'fixture-window-release-control.json'
$projectionControlPath = Join-Path $outputRoot 'fixture-window-projected-type-control.json'
$factoryControlPath = Join-Path $outputRoot 'fixture-window-projected-factory-control.json'
$monitorControlPath = Join-Path $outputRoot 'fixture-monitor-lower-layer-control.json'
$nativeReferencePath = Join-Path $outputRoot 'fixture-native-cpp-window-reference.json'
$logPath = Join-Path $outputRoot 'fixture-wgc-smoke.log'
$summaryPath = Join-Path $outputRoot 'fixture-wgc-matrix-summary.json'

function Resolve-DotNet {
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $localDotNet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
    if (Test-Path -LiteralPath $localDotNet -PathType Leaf) { return $localDotNet }
    throw 'dotnet não foi encontrado.'
}

function Resolve-MSBuildOptional {
    $command = Get-Command msbuild -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $vswhereCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($vswhere in $vswhereCandidates) {
        if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) { continue }
        $candidate = & $vswhere `
            -latest `
            -products '*' `
            -requires Microsoft.Component.MSBuild `
            -find 'MSBuild\**\Bin\MSBuild.exe' 2>$null | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [string]$candidate
        }
    }

    return $null
}

function Invoke-ExternalProcess {
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] [string[]] $Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add($argument) }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        return [pscustomobject]@{
            exitCode = $process.ExitCode
            stdout = $stdout.TrimEnd()
            stderr = $stderr.TrimEnd()
            output = (($stdout + $stderr).TrimEnd())
        }
    }
    finally {
        $process.Dispose()
    }
}

function Invoke-ProbeLane {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [ValidateSet('window', 'monitor')] [string] $CaptureKind,
        [Parameter(Mandatory)] [ValidateSet('raw', 'projected')] [string] $ItemFactory,
        [Parameter(Mandatory)] [ValidateSet('projected', 'marshal-interface')] [string] $ItemProjection,
        [Parameter(Mandatory)] [ValidateSet('release', 'hold')] [string] $AbiLifetime,
        [Parameter(Mandatory)] [string] $ReportPath,
        [Parameter(Mandatory)] [int] $ProcessId
    )

    Remove-Item -LiteralPath $ReportPath -Force -ErrorAction SilentlyContinue
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    $output = & $dotnet $probeDll `
        --pid $ProcessId `
        --capture-kind $CaptureKind `
        --item-factory $ItemFactory `
        --item-projection $ItemProjection `
        --abi-lifetime $AbiLifetime `
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
        itemProjection = $ItemProjection
        abiLifetime = $AbiLifetime
        exitCode = $exitCode
        reportPath = $ReportPath
        report = $report
        output = ($output | Out-String).TrimEnd()
    }
}

function Invoke-NativeReference {
    param([Parameter(Mandatory)] [string] $WindowHandle)

    Remove-Item -LiteralPath $nativeReferencePath -Force -ErrorAction SilentlyContinue
    $builder = Resolve-MSBuildOptional
    if ([string]::IsNullOrWhiteSpace($builder)) {
        return [pscustomobject]@{
            status = 'NOT_AVAILABLE'
            buildStatus = 'MSBUILD_NOT_FOUND'
            executionStatus = 'NOT_RUN'
            exitCode = $null
            reportPath = $nativeReferencePath
            report = $null
            output = 'MSBuild/C++ toolchain not available on this machine.'
        }
    }

    Write-Host '=== NATIVE C++/WINRT REFERENCE BUILD ===' -ForegroundColor Cyan
    $build = Invoke-ExternalProcess `
        -FilePath $builder `
        -Arguments @(
            $nativeProject,
            '/m',
            '/p:Configuration=Release',
            '/p:Platform=x64',
            '/verbosity:minimal'
        )
    Write-Host $build.output

    if ($build.exitCode -ne 0) {
        return [pscustomobject]@{
            status = 'BUILD_FAILED'
            buildStatus = 'FAILED'
            executionStatus = 'NOT_RUN'
            exitCode = $build.exitCode
            reportPath = $nativeReferencePath
            report = $null
            output = $build.output
        }
    }

    if (-not (Test-Path -LiteralPath $nativeExe -PathType Leaf)) {
        return [pscustomobject]@{
            status = 'BUILD_OUTPUT_MISSING'
            buildStatus = 'SUCCESS_BUT_EXE_MISSING'
            executionStatus = 'NOT_RUN'
            exitCode = $null
            reportPath = $nativeReferencePath
            report = $null
            output = "Native reference executable missing after successful MSBuild: $nativeExe"
        }
    }

    Write-Host '=== NATIVE C++/WINRT REFERENCE EXECUTION ===' -ForegroundColor Cyan
    $run = Invoke-ExternalProcess `
        -FilePath $nativeExe `
        -Arguments @('--hwnd', $WindowHandle, '--output', $nativeReferencePath)
    Write-Host $run.output

    $report = $null
    if (Test-Path -LiteralPath $nativeReferencePath -PathType Leaf) {
        try { $report = Get-Content -LiteralPath $nativeReferencePath -Raw | ConvertFrom-Json }
        catch { Write-Warning "Relatório C++ inválido em $nativeReferencePath : $($_.Exception.Message)" }
    }

    return [pscustomobject]@{
        status = 'EXECUTED'
        buildStatus = 'SUCCESS'
        executionStatus = if ($null -ne $report) { 'REPORT_GENERATED' } else { 'NO_REPORT' }
        exitCode = $run.exitCode
        reportPath = $nativeReferencePath
        report = $report
        output = $run.output
    }
}

function Lane-Summary($lane) {
    $report = $lane.report
    $window = if ($null -ne $report) { $report.window } else { $null }
    return [ordered]@{
        name = $lane.name
        captureKind = $lane.captureKind
        itemFactory = $lane.itemFactory
        itemProjection = $lane.itemProjection
        abiLifetime = $lane.abiLifetime
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
        hwnd = if ($null -ne $window) { $window.handle } else { $null }
        className = if ($null -ne $window) { $window.className } else { $null }
        visible = if ($null -ne $window) { $window.visible } else { $null }
        iconic = if ($null -ne $window) { $window.iconic } else { $null }
        cloaked = if ($null -ne $window) { $window.cloaked } else { $null }
        displayAffinity = if ($null -ne $window) { $window.displayAffinity } else { $null }
        reportPath = $lane.reportPath
    }
}

function Get-LaneItemHealthy($lane) {
    if ($null -eq $lane.report) { return $false }
    if ($null -ne $lane.report.capture) {
        return ([int]$lane.report.capture.initialItemWidth -gt 0 -and [int]$lane.report.capture.initialItemHeight -gt 0)
    }
    if ($null -ne $lane.report.error) {
        return ([int]$lane.report.error.itemWidth -gt 0 -and [int]$lane.report.error.itemHeight -gt 0)
    }
    return $false
}

function Native-Summary($native) {
    $report = $native.report
    return [ordered]@{
        status = $native.status
        buildStatus = $native.buildStatus
        executionStatus = $native.executionStatus
        exitCode = $native.exitCode
        reportGenerated = ($null -ne $report)
        verdict = if ($null -ne $report) { $report.verdict } else { $null }
        stage = if ($null -ne $report) { $report.stage } else { $null }
        hwnd = if ($null -ne $report) { $report.hwnd } else { $null }
        itemWidth = if ($null -ne $report) { [int]$report.itemWidth } else { 0 }
        itemHeight = if ($null -ne $report) { [int]$report.itemHeight } else { 0 }
        displayName = if ($null -ne $report) { $report.displayName } else { $null }
        hresult = if ($null -ne $report) { $report.hresult } else { $null }
        message = if ($null -ne $report) { $report.message } else { $null }
        reportPath = $native.reportPath
    }
}

$currentHead = ([string](git rev-parse HEAD)).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $currentHead -ne $ExpectedHeadSha.ToLowerInvariant()) {
    throw "HEAD incorreto. esperado=$ExpectedHeadSha atual=$currentHead"
}
$branch = ([string](git branch --show-current)).Trim()
if ($LASTEXITCODE -ne 0 -or $expectedBranches -notcontains $branch) {
    throw "Branch incorreta. esperado=$($expectedBranches -join ',') atual=$branch"
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

    $reportedHandleText = ('0x{0:X}' -f $reportedMainWindowHwnd.ToInt64())
    Write-Host "Fixture PID=$($fixture.Id) reported MainWindowHandle=$reportedHandleText" -ForegroundColor Cyan

    # Five C# lanes isolate factory, projection, ABI lifetime, and the WGC/D3D lower layer.
    # Only lane 1 is allowed to approve the product gate.
    $product = Invoke-ProbeLane `
        -Name 'WINDOW / RAW / MARSHAL-INTERFACE / HOLD (PRODUCT CANDIDATE)' `
        -CaptureKind window `
        -ItemFactory raw `
        -ItemProjection marshal-interface `
        -AbiLifetime hold `
        -ReportPath $productReportPath `
        -ProcessId $fixture.Id

    $lifetimeControl = Invoke-ProbeLane `
        -Name 'WINDOW / RAW / MARSHAL-INTERFACE / RELEASE (LIFETIME CONTROL)' `
        -CaptureKind window `
        -ItemFactory raw `
        -ItemProjection marshal-interface `
        -AbiLifetime release `
        -ReportPath $lifetimeControlPath `
        -ProcessId $fixture.Id

    $projectionControl = Invoke-ProbeLane `
        -Name 'WINDOW / RAW / PROJECTED-TYPE / HOLD (PROJECTION CONTROL)' `
        -CaptureKind window `
        -ItemFactory raw `
        -ItemProjection projected `
        -AbiLifetime hold `
        -ReportPath $projectionControlPath `
        -ProcessId $fixture.Id

    $factoryControl = Invoke-ProbeLane `
        -Name 'WINDOW / PROJECTED-FACTORY / MARSHAL-INTERFACE / HOLD (FACTORY CONTROL)' `
        -CaptureKind window `
        -ItemFactory projected `
        -ItemProjection marshal-interface `
        -AbiLifetime hold `
        -ReportPath $factoryControlPath `
        -ProcessId $fixture.Id

    $monitorControl = Invoke-ProbeLane `
        -Name 'MONITOR / RAW / MARSHAL-INTERFACE / HOLD (LOWER-LAYER CONTROL)' `
        -CaptureKind monitor `
        -ItemFactory raw `
        -ItemProjection marshal-interface `
        -AbiLifetime hold `
        -ReportPath $monitorControlPath `
        -ProcessId $fixture.Id

    # The native C++/WinRT reference must use the exact HWND selected by the C# probe.
    # If the C# report is unavailable, fall back to the fixture's published HWND and record it.
    $canonicalWindowHandle = if ($null -ne $product.report -and $null -ne $product.report.window -and -not [string]::IsNullOrWhiteSpace($product.report.window.handle)) {
        [string]$product.report.window.handle
    } else {
        $reportedHandleText
    }
    $nativeReference = Invoke-NativeReference -WindowHandle $canonicalWindowHandle

    $completedAt = [DateTimeOffset]::UtcNow
    $productGatePassed = ($product.exitCode -eq 0 -and $null -ne $product.report -and $product.report.verdict -eq 'PASS')
    $lowerLayerHealthy = ($monitorControl.exitCode -eq 0 -and $null -ne $monitorControl.report -and $monitorControl.report.verdict -eq 'PASS')
    $allWindowLanesFailed = (@($product, $lifetimeControl, $projectionControl, $factoryControl) | Where-Object { $_.exitCode -eq 0 }).Count -eq 0
    $csharpProductItemHealthy = Get-LaneItemHealthy $product
    $nativeItemHealthy = ($null -ne $nativeReference.report -and $nativeReference.report.verdict -eq 'PASS' -and [int]$nativeReference.report.itemWidth -gt 0 -and [int]$nativeReference.report.itemHeight -gt 0)
    $nativeExecutedWithReport = ($nativeReference.status -eq 'EXECUTED' -and $null -ne $nativeReference.report)

    $summary = [ordered]@{
        schemaVersion = 3
        probeMatrix = 'CloudOS Windows captured-surface C#/native HWND isolation'
        startedAt = $startedAt.ToString('o')
        completedAt = $completedAt.ToString('o')
        branch = $branch
        head = $currentHead
        fixtureKind = 'winforms-overlapped-animated'
        fixturePid = $fixture.Id
        fixtureReportedMainWindowHwnd = $reportedHandleText
        canonicalWindowHwnd = $canonicalWindowHandle
        minimumFrames = $MinimumFrames
        captureSeconds = $CaptureSeconds
        productGate = 'window/raw/marshal-interface/hold'
        productGatePassed = $productGatePassed
        interpretation = [ordered]@{
            lifetimeSuspect = ($product.exitCode -eq 0 -and $lifetimeControl.exitCode -ne 0)
            projectionSuspect = ($product.exitCode -eq 0 -and $projectionControl.exitCode -ne 0)
            factorySuspect = ($product.exitCode -eq 0 -and $factoryControl.exitCode -ne 0)
            lowerLayerHealthy = $lowerLayerHealthy
            allWindowLanesFailed = $allWindowLanesFailed
            csharpProductItemHealthy = $csharpProductItemHealthy
            nativeReferenceAvailable = ($nativeReference.status -ne 'NOT_AVAILABLE')
            nativeReferenceProducedReport = $nativeExecutedWithReport
            nativeItemHealthy = $nativeItemHealthy
            nativeDisagreesWithCsharpItemMetadata = ($nativeExecutedWithReport -and ($nativeItemHealthy -ne $csharpProductItemHealthy))
            nativeAndCsharpBothReportUnusableWindowItem = ($nativeExecutedWithReport -and -not $nativeItemHealthy -and -not $csharpProductItemHealthy)
            nativeHealthyWhileCsharpWindowFails = ($nativeItemHealthy -and -not $productGatePassed)
        }
        lanes = @(
            (Lane-Summary $product),
            (Lane-Summary $lifetimeControl),
            (Lane-Summary $projectionControl),
            (Lane-Summary $factoryControl),
            (Lane-Summary $monitorControl)
        )
        nativeReference = (Native-Summary $nativeReference)
    }

    $summaryJson = $summary | ConvertTo-Json -Depth 16
    [System.IO.File]::WriteAllText($summaryPath, $summaryJson + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

    $logLines = @(
        'CLOUDOS WINDOWS CAPTURE FULL C#/NATIVE HWND ISOLATION',
        "startedAt=$($startedAt.ToString('o'))",
        "completedAt=$($completedAt.ToString('o'))",
        "branch=$branch",
        "head=$currentHead",
        'fixtureKind=winforms-overlapped-animated',
        "fixturePid=$($fixture.Id)",
        "fixtureReportedMainWindowHwnd=$reportedHandleText",
        "canonicalWindowHwnd=$canonicalWindowHandle",
        'targetSelection=probe-enumerated-largest-visible-top-level-window-for-pid',
        "captureSeconds=$CaptureSeconds",
        "minimumFrames=$MinimumFrames",
        "productExitCode=$($product.exitCode)",
        "lifetimeControlExitCode=$($lifetimeControl.exitCode)",
        "projectionControlExitCode=$($projectionControl.exitCode)",
        "factoryControlExitCode=$($factoryControl.exitCode)",
        "monitorControlExitCode=$($monitorControl.exitCode)",
        "nativeReferenceStatus=$($nativeReference.status)",
        "nativeReferenceBuildStatus=$($nativeReference.buildStatus)",
        "nativeReferenceExecutionStatus=$($nativeReference.executionStatus)",
        "nativeReferenceExitCode=$($nativeReference.exitCode)",
        "matrixSummary=$summaryPath",
        '',
        '=== WINDOW / RAW / MARSHAL-INTERFACE / HOLD (PRODUCT CANDIDATE) ===',
        $product.output,
        '',
        '=== WINDOW / RAW / MARSHAL-INTERFACE / RELEASE (LIFETIME CONTROL) ===',
        $lifetimeControl.output,
        '',
        '=== WINDOW / RAW / PROJECTED-TYPE / HOLD (PROJECTION CONTROL) ===',
        $projectionControl.output,
        '',
        '=== WINDOW / PROJECTED-FACTORY / MARSHAL-INTERFACE / HOLD (FACTORY CONTROL) ===',
        $factoryControl.output,
        '',
        '=== MONITOR / RAW / MARSHAL-INTERFACE / HOLD (LOWER-LAYER CONTROL) ===',
        $monitorControl.output,
        '',
        '=== NATIVE C++/WINRT REFERENCE ===',
        $nativeReference.output,
        '',
        '=== MATRIX SUMMARY ===',
        $summaryJson
    )
    [System.IO.File]::WriteAllLines($logPath, $logLines, [System.Text.UTF8Encoding]::new($false))

    Write-Host ''
    Write-Host '=== C#/NATIVE HWND MATRIX SUMMARY ===' -ForegroundColor Cyan
    Write-Host $summaryJson
    Write-Host "Summary: $summaryPath"
    Write-Host "Log:     $logPath"

    if (-not $productGatePassed) {
        throw "Window/raw/marshal-interface/hold product gate falhou. Evidence: $summaryPath ; $logPath"
    }

    Write-Host ''
    Write-Host 'CLOUDOS WINDOWS CAPTURE PRODUCT CANDIDATE GATE: PASS' -ForegroundColor Green
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
