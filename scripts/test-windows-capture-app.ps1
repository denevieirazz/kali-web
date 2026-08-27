[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string] $ExpectedHeadSha,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ExecutablePath,

    [string[]] $Arguments = @(),

    [ValidateRange(1, 60)]
    [int] $WindowTimeoutSeconds = 15,

    [ValidateRange(1, 30)]
    [int] $CaptureSeconds = 5,

    [ValidateRange(1, 1000)]
    [int] $MinimumFrames = 10,

    [switch] $RequireFrameHealth,

    [switch] $LeaveProcessRunning,

    [string] $OutputDirectory = (Join-Path (Get-Location) 'poc1-physical-evidence\windows-captured-surface\app-proof')
)

$ErrorActionPreference = 'Stop'
$expectedBranches = @('poc/cloudos-windows-captured-surface', 'integration/cloudos-unified-runtime')
$repoRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
$probeProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Probe\CloudOS.WindowsCapture.Probe.csproj'
$probeDll = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Probe\bin\Release\net8.0-windows10.0.19041.0\CloudOS.WindowsCapture.Probe.dll'
$healthProbeProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.HealthProbe\CloudOS.WindowsCapture.HealthProbe.csproj'
$healthProbeDll = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.HealthProbe\bin\Release\net8.0-windows10.0.19041.0\CloudOS.WindowsCapture.HealthProbe.dll'
$nativeProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.NativeReference\CloudOS.WindowsCapture.NativeReference.vcxproj'
$nativeExe = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.NativeReference\bin\Release\x64\CloudOS.WindowsCapture.NativeReference.exe'
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$productReportPath = Join-Path $outputRoot 'app-window-product-candidate.json'
$healthReportPath = Join-Path $outputRoot 'app-frame-health.json'
$nativeReportPath = Join-Path $outputRoot 'app-native-cpp-window-reference.json'
$summaryPath = Join-Path $outputRoot 'app-capture-qualification-summary.json'
$logPath = Join-Path $outputRoot 'app-capture-qualification.log'

function Resolve-DotNet {
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $localDotNet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
    if (Test-Path -LiteralPath $localDotNet -PathType Leaf) { return $localDotNet }
    throw 'dotnet não foi encontrado.'
}

function Resolve-Executable {
    param([Parameter(Mandatory)] [string] $PathOrCommand)

    if (Test-Path -LiteralPath $PathOrCommand -PathType Leaf) {
        return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PathOrCommand).Path)
    }

    $command = Get-Command $PathOrCommand -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
        return [System.IO.Path]::GetFullPath($command.Source)
    }

    throw "Executável não encontrado: $PathOrCommand"
}

function Resolve-MSBuildOptional {
    $command = Get-Command msbuild -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $roots = @()
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) { $roots += ${env:ProgramFiles(x86)} }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) { $roots += $env:ProgramFiles }

    foreach ($root in $roots | Select-Object -Unique) {
        $vswhere = Join-Path $root 'Microsoft Visual Studio\Installer\vswhere.exe'
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

function Read-JsonOptional {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { return $null }
}

function Invoke-NativeReference {
    param([Parameter(Mandatory)] [string] $WindowHandle)

    Remove-Item -LiteralPath $nativeReportPath -Force -ErrorAction SilentlyContinue
    $builder = Resolve-MSBuildOptional
    if ([string]::IsNullOrWhiteSpace($builder)) {
        return [pscustomobject]@{
            status = 'NOT_AVAILABLE'
            buildStatus = 'MSBUILD_NOT_FOUND'
            exitCode = $null
            report = $null
            output = 'MSBuild/C++ toolchain not available.'
        }
    }

    $build = Invoke-ExternalProcess `
        -FilePath $builder `
        -Arguments @(
            $nativeProject,
            '/m',
            '/p:Configuration=Release',
            '/p:Platform=x64',
            '/verbosity:minimal'
        )
    if ($build.exitCode -ne 0) {
        return [pscustomobject]@{
            status = 'BUILD_FAILED'
            buildStatus = 'FAILED'
            exitCode = $build.exitCode
            report = $null
            output = $build.output
        }
    }

    if (-not (Test-Path -LiteralPath $nativeExe -PathType Leaf)) {
        return [pscustomobject]@{
            status = 'BUILD_OUTPUT_MISSING'
            buildStatus = 'SUCCESS_BUT_EXE_MISSING'
            exitCode = $null
            report = $null
            output = "Native reference executable missing: $nativeExe"
        }
    }

    $run = Invoke-ExternalProcess `
        -FilePath $nativeExe `
        -Arguments @('--hwnd', $WindowHandle, '--output', $nativeReportPath)
    return [pscustomobject]@{
        status = 'EXECUTED'
        buildStatus = 'SUCCESS'
        exitCode = $run.exitCode
        report = (Read-JsonOptional $nativeReportPath)
        output = $run.output
    }
}

function Invoke-FrameHealth {
    param([Parameter(Mandatory)] [string] $WindowHandle)

    Remove-Item -LiteralPath $healthReportPath -Force -ErrorAction SilentlyContinue
    $run = Invoke-ExternalProcess `
        -FilePath $dotnet `
        -Arguments @(
            $healthProbeDll,
            '--hwnd', $WindowHandle,
            '--seconds', [string]$CaptureSeconds,
            '--min-frames', [string]$MinimumFrames,
            '--sample-every', '3',
            '--samples', '8',
            '--region', '256',
            '--grid', '32',
            '--output', $healthReportPath
        )
    return [pscustomobject]@{
        status = 'EXECUTED'
        exitCode = $run.exitCode
        report = (Read-JsonOptional $healthReportPath)
        output = $run.output
    }
}

function Write-SummaryAndThrow {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Summary,
        [Parameter(Mandatory)] [string] $FailureMessage,
        [string[]] $AdditionalLog = @()
    )

    $summaryJson = $Summary | ConvertTo-Json -Depth 18
    [System.IO.File]::WriteAllText($summaryPath, $summaryJson + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    $lines = @(
        'CLOUDOS GENERIC WINDOWS APP CAPTURE QUALIFICATION',
        $summaryJson,
        ''
    ) + $AdditionalLog
    [System.IO.File]::WriteAllLines($logPath, $lines, [System.Text.UTF8Encoding]::new($false))
    throw "$FailureMessage Evidence: $summaryPath ; $logPath"
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
$resolvedExecutable = Resolve-Executable $ExecutablePath
[System.IO.Directory]::CreateDirectory($outputRoot) | Out-Null
Remove-Item -LiteralPath $productReportPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $healthReportPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $nativeReportPath -Force -ErrorAction SilentlyContinue
$target = $null
$startedAt = [DateTimeOffset]::UtcNow

try {
    Write-Host 'Compilando CloudOS Windows capture probe...' -ForegroundColor Cyan
    & $dotnet build $probeProject -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "Build do capture probe falhou com exit code $LASTEXITCODE." }

    Write-Host 'Compilando frame-health probe...' -ForegroundColor Cyan
    & $dotnet build $healthProbeProject -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "Build do frame-health probe falhou com exit code $LASTEXITCODE." }

    $launchInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $launchInfo.FileName = $resolvedExecutable
    foreach ($argument in $Arguments) { [void]$launchInfo.ArgumentList.Add($argument) }
    $launchInfo.UseShellExecute = $false
    $launchInfo.WorkingDirectory = [System.IO.Path]::GetDirectoryName($resolvedExecutable)

    Write-Host "Iniciando app real: $resolvedExecutable" -ForegroundColor Cyan
    $target = [System.Diagnostics.Process]::Start($launchInfo)
    if ($null -eq $target) { throw 'Process.Start retornou null.' }

    $launchPid = $target.Id
    $launchStartTimeUtc = $null
    try { $launchStartTimeUtc = $target.StartTime.ToUniversalTime().ToString('o') } catch {}
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($WindowTimeoutSeconds)
    $readinessHwnd = [IntPtr]::Zero
    $targetExitedBeforeWindow = $false
    do {
        Start-Sleep -Milliseconds 100
        $target.Refresh()
        if ($target.HasExited) {
            $targetExitedBeforeWindow = $true
            break
        }
        $readinessHwnd = $target.MainWindowHandle
    } while ($readinessHwnd -eq [IntPtr]::Zero -and [DateTimeOffset]::UtcNow -lt $deadline)

    if ($targetExitedBeforeWindow) {
        $exitCode = $null
        try { $exitCode = $target.ExitCode } catch {}
        $summary = [ordered]@{
            schemaVersion = 2
            proof = 'CloudOS generic Windows app capture qualification'
            startedAt = $startedAt.ToString('o')
            completedAt = [DateTimeOffset]::UtcNow.ToString('o')
            branch = $branch
            head = $currentHead
            classification = 'BROKER_OR_SINGLETON_UNSAFE'
            frameHealthStatus = 'NOT_RUN_CAPTURE_GATE_FAILED'
            frameHealthRequired = [bool]$RequireFrameHealth
            executable = $resolvedExecutable
            arguments = @($Arguments)
            launch = [ordered]@{
                pid = $launchPid
                startTimeUtc = $launchStartTimeUtc
                exitedBeforeSamePidWindow = $true
                exitCode = $exitCode
            }
            productCandidate = $null
            frameHealth = $null
            nativeReference = $null
        }
        Write-SummaryAndThrow -Summary $summary -FailureMessage 'O processo lançado encerrou antes de publicar janela no mesmo PID; handoff/broker/singleton não é aceito pela POC.'
    }

    if ($readinessHwnd -eq [IntPtr]::Zero) {
        $summary = [ordered]@{
            schemaVersion = 2
            proof = 'CloudOS generic Windows app capture qualification'
            startedAt = $startedAt.ToString('o')
            completedAt = [DateTimeOffset]::UtcNow.ToString('o')
            branch = $branch
            head = $currentHead
            classification = 'CAPTURE_BLOCKED'
            frameHealthStatus = 'NOT_RUN_CAPTURE_GATE_FAILED'
            frameHealthRequired = [bool]$RequireFrameHealth
            executable = $resolvedExecutable
            arguments = @($Arguments)
            launch = [ordered]@{
                pid = $launchPid
                startTimeUtc = $launchStartTimeUtc
                exitedBeforeSamePidWindow = $false
                readinessTimedOut = $true
                readinessHwnd = $null
            }
            productCandidate = $null
            frameHealth = $null
            nativeReference = $null
        }
        Write-SummaryAndThrow -Summary $summary -FailureMessage 'Nenhuma janela top-level do processo ficou pronta dentro do timeout.'
    }

    $readinessHandleText = ('0x{0:X}' -f $readinessHwnd.ToInt64())
    Write-Host "PID=$launchPid readiness MainWindowHandle=$readinessHandleText" -ForegroundColor Cyan
    Write-Host 'Executando product candidate window/raw/marshal-interface/hold...' -ForegroundColor Cyan

    $productRun = Invoke-ExternalProcess `
        -FilePath $dotnet `
        -Arguments @(
            $probeDll,
            '--pid', [string]$launchPid,
            '--capture-kind', 'window',
            '--item-factory', 'raw',
            '--item-projection', 'marshal-interface',
            '--abi-lifetime', 'hold',
            '--seconds', [string]$CaptureSeconds,
            '--min-frames', [string]$MinimumFrames,
            '--output', $productReportPath
        )
    Write-Host $productRun.output

    $productReport = Read-JsonOptional $productReportPath
    $canonicalWindowHwnd = if ($null -ne $productReport -and $null -ne $productReport.window -and -not [string]::IsNullOrWhiteSpace($productReport.window.handle)) {
        [string]$productReport.window.handle
    } else {
        $readinessHandleText
    }

    Write-Host "Executando NATIVE C++/WINRT REFERENCE no mesmo HWND $canonicalWindowHwnd..." -ForegroundColor Cyan
    $native = Invoke-NativeReference -WindowHandle $canonicalWindowHwnd
    Write-Host $native.output

    $productVerdict = if ($null -ne $productReport) { [string]$productReport.verdict } else { $null }
    $productStage = if ($null -ne $productReport -and $null -ne $productReport.error) { [string]$productReport.error.stage } else { $null }
    $productHResult = if ($null -ne $productReport -and $null -ne $productReport.error) { [string]$productReport.error.nativeHResult } else { $null }
    $productFrameCount = if ($null -ne $productReport -and $null -ne $productReport.capture) { [long]$productReport.capture.frameCount } else { 0 }
    $productWidth = if ($null -ne $productReport -and $null -ne $productReport.capture) { [int]$productReport.capture.width } else { 0 }
    $productHeight = if ($null -ne $productReport -and $null -ne $productReport.capture) { [int]$productReport.capture.height } else { 0 }
    $productPassed = ($productRun.exitCode -eq 0 -and $null -ne $productReport -and $productVerdict -eq 'PASS' -and $productFrameCount -ge $MinimumFrames)

    $classification = if ($productPassed) {
        'CAPTURE_SUPPORTED'
    } elseif ($null -ne $productReport -and $productVerdict -eq 'FAIL') {
        'RENDER_FAILED'
    } else {
        'CAPTURE_BLOCKED'
    }

    $health = $null
    $healthReport = $null
    $healthStatus = 'NOT_RUN_CAPTURE_GATE_FAILED'
    if ($productPassed) {
        Write-Host "Executando FRAME HEALTH no mesmo HWND $canonicalWindowHwnd..." -ForegroundColor Cyan
        $health = Invoke-FrameHealth -WindowHandle $canonicalWindowHwnd
        Write-Host $health.output
        $healthReport = $health.report
        if ($null -eq $healthReport -or $health.exitCode -ne 0 -or $healthReport.verdict -ne 'PASS') {
            $healthStatus = 'UNAVAILABLE'
        } elseif ($null -ne $healthReport.interpretation -and (
            $healthReport.interpretation.staticSequenceSuspect -eq $true -or
            $healthReport.interpretation.flatNeutralSequenceSuspect -eq $true)) {
            $healthStatus = 'SUSPECT_STATIC_OR_NEUTRAL'
        } else {
            $healthStatus = 'PASS'
        }
    }

    $healthGatePassed = (-not $RequireFrameHealth) -or ($healthStatus -eq 'PASS')
    $nativeReport = $native.report
    $summary = [ordered]@{
        schemaVersion = 2
        proof = 'CloudOS generic Windows app capture qualification'
        startedAt = $startedAt.ToString('o')
        completedAt = [DateTimeOffset]::UtcNow.ToString('o')
        branch = $branch
        head = $currentHead
        classification = $classification
        frameHealthStatus = $healthStatus
        frameHealthRequired = [bool]$RequireFrameHealth
        frameHealthGatePassed = $healthGatePassed
        executable = $resolvedExecutable
        arguments = @($Arguments)
        productGate = 'window/raw/marshal-interface/hold'
        productGatePassed = $productPassed
        launch = [ordered]@{
            pid = $launchPid
            startTimeUtc = $launchStartTimeUtc
            readinessHwnd = $readinessHandleText
            canonicalWindowHwnd = $canonicalWindowHwnd
            samePidWindowRequired = $true
        }
        productCandidate = [ordered]@{
            exitCode = $productRun.exitCode
            reportGenerated = ($null -ne $productReport)
            verdict = $productVerdict
            stage = $productStage
            nativeHResult = $productHResult
            frameCount = $productFrameCount
            width = $productWidth
            height = $productHeight
            className = if ($null -ne $productReport -and $null -ne $productReport.window) { $productReport.window.className } else { $null }
            visible = if ($null -ne $productReport -and $null -ne $productReport.window) { $productReport.window.visible } else { $null }
            iconic = if ($null -ne $productReport -and $null -ne $productReport.window) { $productReport.window.iconic } else { $null }
            cloaked = if ($null -ne $productReport -and $null -ne $productReport.window) { $productReport.window.cloaked } else { $null }
            reportPath = $productReportPath
        }
        frameHealth = [ordered]@{
            status = $healthStatus
            executed = ($null -ne $health)
            exitCode = if ($null -ne $health) { $health.exitCode } else { $null }
            reportGenerated = ($null -ne $healthReport)
            verdict = if ($null -ne $healthReport) { $healthReport.verdict } else { $null }
            distinctFrameHashes = if ($null -ne $healthReport -and $null -ne $healthReport.frameHealth) { [int]$healthReport.frameHealth.distinctFrameHashes } else { 0 }
            changedSamples = if ($null -ne $healthReport -and $null -ne $healthReport.frameHealth) { [int]$healthReport.frameHealth.changedSamples } else { 0 }
            successfulSamples = if ($null -ne $healthReport -and $null -ne $healthReport.frameHealth) { [int]$healthReport.frameHealth.successfulSamples } else { 0 }
            failedSamples = if ($null -ne $healthReport -and $null -ne $healthReport.frameHealth) { [int]$healthReport.frameHealth.failedSamples } else { 0 }
            meanLuma = if ($null -ne $healthReport -and $null -ne $healthReport.frameHealth) { [double]$healthReport.frameHealth.meanLuma } else { $null }
            meanLumaVariance = if ($null -ne $healthReport -and $null -ne $healthReport.frameHealth) { [double]$healthReport.frameHealth.meanLumaVariance } else { $null }
            meanChannelSpread = if ($null -ne $healthReport -and $null -ne $healthReport.frameHealth) { [double]$healthReport.frameHealth.meanChannelSpread } else { $null }
            staticSequenceSuspect = if ($null -ne $healthReport -and $null -ne $healthReport.interpretation) { [bool]$healthReport.interpretation.staticSequenceSuspect } else { $null }
            flatNeutralSequenceSuspect = if ($null -ne $healthReport -and $null -ne $healthReport.interpretation) { [bool]$healthReport.interpretation.flatNeutralSequenceSuspect } else { $null }
            reportPath = $healthReportPath
        }
        nativeReference = [ordered]@{
            status = $native.status
            buildStatus = $native.buildStatus
            exitCode = $native.exitCode
            reportGenerated = ($null -ne $nativeReport)
            verdict = if ($null -ne $nativeReport) { $nativeReport.verdict } else { $null }
            stage = if ($null -ne $nativeReport) { $nativeReport.stage } else { $null }
            itemWidth = if ($null -ne $nativeReport) { [int]$nativeReport.itemWidth } else { 0 }
            itemHeight = if ($null -ne $nativeReport) { [int]$nativeReport.itemHeight } else { 0 }
            hresult = if ($null -ne $nativeReport) { $nativeReport.hresult } else { $null }
            reportPath = $nativeReportPath
        }
    }

    $summaryJson = $summary | ConvertTo-Json -Depth 18
    [System.IO.File]::WriteAllText($summaryPath, $summaryJson + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    $healthLogOutput = if ($null -ne $health) { $health.output } else { 'NOT_RUN_CAPTURE_GATE_FAILED' }
    $logLines = @(
        'CLOUDOS GENERIC WINDOWS APP CAPTURE QUALIFICATION',
        "head=$currentHead",
        "executable=$resolvedExecutable",
        "pid=$launchPid",
        "readinessHwnd=$readinessHandleText",
        "canonicalWindowHwnd=$canonicalWindowHwnd",
        "classification=$classification",
        "frameHealthStatus=$healthStatus",
        "frameHealthRequired=$([bool]$RequireFrameHealth)",
        "productExitCode=$($productRun.exitCode)",
        "nativeStatus=$($native.status)",
        '',
        '=== PRODUCT CANDIDATE ===',
        $productRun.output,
        '',
        '=== FRAME HEALTH ===',
        $healthLogOutput,
        '',
        '=== NATIVE C++/WINRT REFERENCE ===',
        $native.output,
        '',
        '=== SUMMARY ===',
        $summaryJson
    )
    [System.IO.File]::WriteAllLines($logPath, $logLines, [System.Text.UTF8Encoding]::new($false))

    Write-Host ''
    Write-Host '=== GENERIC APP CAPTURE QUALIFICATION SUMMARY ===' -ForegroundColor Cyan
    Write-Host $summaryJson
    Write-Host "Summary: $summaryPath"
    Write-Host "Log:     $logPath"

    if (-not $productPassed) {
        throw "Generic app capture qualification falhou com classificação $classification. Evidence: $summaryPath ; $logPath"
    }
    if (-not $healthGatePassed) {
        throw "Generic app frame-health gate falhou com status $healthStatus. Evidence: $summaryPath ; $logPath"
    }

    Write-Host 'CLOUDOS GENERIC WINDOWS APP CAPTURE QUALIFICATION: PASS' -ForegroundColor Green
}
finally {
    if ($null -ne $target) {
        try {
            $target.Refresh()
            if (-not $LeaveProcessRunning -and -not $target.HasExited) {
                $target.Kill($true)
                [void]$target.WaitForExit(5000)
            }
        }
        catch { Write-Warning "Falha ao encerrar processo de qualificação: $($_.Exception.Message)" }
        finally { $target.Dispose() }
    }
}
