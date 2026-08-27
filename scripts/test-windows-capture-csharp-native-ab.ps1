[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string] $ExpectedHeadSha,

    [ValidateRange(1, 30)]
    [int] $CaptureSeconds = 5,

    [ValidateRange(1, 1000)]
    [int] $MinimumFrames = 10,

    [string] $OutputDirectory = (Join-Path (Get-Location) 'poc1-physical-evidence\windows-captured-surface')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedBranches = @('poc/cloudos-windows-captured-surface', 'integration/cloudos-unified-runtime')
$repoRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$fixtureProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Fixture\CloudOS.WindowsCapture.Fixture.csproj'
$fixtureExe = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Fixture\bin\Release\net8.0-windows\CloudOS.WindowsCapture.Fixture.exe'
$csharpProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Probe\CloudOS.WindowsCapture.Probe.csproj'
$csharpProbe = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Probe\bin\Release\net8.0-windows10.0.19041.0\CloudOS.WindowsCapture.Probe.dll'
$nativeProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.NativeSessionReference\CloudOS.WindowsCapture.NativeSessionReference.vcxproj'
$nativeProbe = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.NativeSessionReference\bin\Release\x64\CloudOS.WindowsCapture.NativeSessionReference.exe'
$csharpReportPath = Join-Path $outputRoot 'same-hwnd-csharp-product-candidate.json'
$nativeReportPath = Join-Path $outputRoot 'same-hwnd-native-session-reference.json'
$summaryPath = Join-Path $outputRoot 'same-hwnd-csharp-native-ab-summary.json'
$logPath = Join-Path $outputRoot 'same-hwnd-csharp-native-ab.log'

function Resolve-DotNet {
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $localDotNet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
    if (Test-Path -LiteralPath $localDotNet -PathType Leaf) { return $localDotNet }
    throw 'dotnet não foi encontrado.'
}

function Resolve-MSBuild {
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

    throw 'MSBuild/Visual Studio Build Tools não foi encontrado.'
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
            output = (($stdout + [Environment]::NewLine + $stderr).Trim())
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

function Get-CSharpStage {
    param($Report)
    if ($null -eq $Report) { return $null }
    if ($null -ne $Report.error) { return [string]$Report.error.stage }
    if ([string]$Report.verdict -eq 'PASS') { return 'complete' }
    return 'frame-wait'
}

function Get-CSharpHResult {
    param($Report)
    if ($null -eq $Report -or $null -eq $Report.error) { return $null }
    if (-not [string]::IsNullOrWhiteSpace([string]$Report.error.nativeHResult)) { return [string]$Report.error.nativeHResult }
    if (-not [string]::IsNullOrWhiteSpace([string]$Report.error.hResult)) { return [string]$Report.error.hResult }
    return $null
}

function Get-CSharpItemWidth {
    param($Report)
    if ($null -eq $Report) { return $null }
    if ($null -ne $Report.error) { return [int]$Report.error.itemWidth }
    if ($null -ne $Report.capture) { return [int]$Report.capture.initialItemWidth }
    return $null
}

function Get-CSharpItemHeight {
    param($Report)
    if ($null -eq $Report) { return $null }
    if ($null -ne $Report.error) { return [int]$Report.error.itemHeight }
    if ($null -ne $Report.capture) { return [int]$Report.capture.initialItemHeight }
    return $null
}

$actualBranch = (git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Falha ao ler branch atual.' }
$actualHead = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Falha ao ler HEAD atual.' }
if ($expectedBranches -notcontains $actualBranch) { throw "Branch incorreta. expected=$($expectedBranches -join ',') actual=$actualBranch" }
if ($actualHead -ne $ExpectedHeadSha) { throw "HEAD incorreto. expected=$ExpectedHeadSha actual=$actualHead" }

$dotnet = Resolve-DotNet
$msbuild = Resolve-MSBuild
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
Remove-Item -LiteralPath $csharpReportPath, $nativeReportPath, $summaryPath, $logPath -Force -ErrorAction SilentlyContinue

$buildLog = [System.Collections.Generic.List[string]]::new()

$csharpBuild = Invoke-ExternalProcess -FilePath $dotnet -Arguments @('build', $csharpProject, '-c', 'Release', '--nologo')
$buildLog.Add("=== BUILD CSHARP PROBE ===`n$($csharpBuild.output)")
if ($csharpBuild.exitCode -ne 0) { throw "C# capture probe build failed.`n$($csharpBuild.output)" }

$fixtureBuild = Invoke-ExternalProcess -FilePath $dotnet -Arguments @('build', $fixtureProject, '-c', 'Release', '--nologo')
$buildLog.Add("=== BUILD FIXTURE ===`n$($fixtureBuild.output)")
if ($fixtureBuild.exitCode -ne 0) { throw "Fixture build failed.`n$($fixtureBuild.output)" }

$nativeBuild = Invoke-ExternalProcess -FilePath $msbuild -Arguments @(
    $nativeProject,
    '/m',
    '/p:Configuration=Release',
    '/p:Platform=x64',
    '/verbosity:minimal'
)
$buildLog.Add("=== BUILD NATIVE SESSION REFERENCE ===`n$($nativeBuild.output)")
if ($nativeBuild.exitCode -ne 0) { throw "Native session reference build failed.`n$($nativeBuild.output)" }

$fixtureProcess = Start-Process -FilePath $fixtureExe -PassThru
try {
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
    $windowHandle = [IntPtr]::Zero
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if ($fixtureProcess.HasExited) { throw "Fixture exited early with code $($fixtureProcess.ExitCode)." }
        $fixtureProcess.Refresh()
        if ($fixtureProcess.MainWindowHandle -ne [IntPtr]::Zero) {
            $windowHandle = $fixtureProcess.MainWindowHandle
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if ($windowHandle -eq [IntPtr]::Zero) { throw 'Fixture did not expose MainWindowHandle in time.' }

    $hwndHex = ('0x{0:X}' -f $windowHandle.ToInt64())
    $header = "BRANCH=$actualBranch`nHEAD=$actualHead`nFIXTURE_PID=$($fixtureProcess.Id)`nSAME_HWND=$hwndHex"
    Write-Host $header

    $csharpRun = Invoke-ExternalProcess -FilePath $dotnet -Arguments @(
        $csharpProbe,
        '--hwnd', $hwndHex,
        '--capture-kind', 'window',
        '--item-factory', 'raw',
        '--item-projection', 'marshal-interface',
        '--abi-lifetime', 'hold',
        '--seconds', [string]$CaptureSeconds,
        '--min-frames', [string]$MinimumFrames,
        '--output', $csharpReportPath
    )

    $nativeRun = Invoke-ExternalProcess -FilePath $nativeProbe -Arguments @(
        '--hwnd', $hwndHex,
        '--seconds', [string]$CaptureSeconds,
        '--min-frames', [string]$MinimumFrames,
        '--output', $nativeReportPath
    )

    $csharpReport = Read-JsonOptional -Path $csharpReportPath
    $nativeReport = Read-JsonOptional -Path $nativeReportPath
    $csharpPassed = $csharpRun.exitCode -eq 0 -and $null -ne $csharpReport -and [string]$csharpReport.verdict -eq 'PASS'
    $nativePassed = $nativeRun.exitCode -eq 0 -and $null -ne $nativeReport -and [string]$nativeReport.verdict -eq 'PASS'
    $csharpStage = Get-CSharpStage -Report $csharpReport
    $nativeStage = if ($null -ne $nativeReport) { [string]$nativeReport.stage } else { $null }
    $csharpHResult = Get-CSharpHResult -Report $csharpReport
    $nativeHResult = if ($null -ne $nativeReport) { [string]$nativeReport.hresult } else { $null }
    $csharpItemWidth = Get-CSharpItemWidth -Report $csharpReport
    $csharpItemHeight = Get-CSharpItemHeight -Report $csharpReport
    $nativeItemWidth = if ($null -ne $nativeReport) { [int]$nativeReport.itemWidth } else { $null }
    $nativeItemHeight = if ($null -ne $nativeReport) { [int]$nativeReport.itemHeight } else { $null }
    $sameSessionFailure = (
        -not $csharpPassed -and
        -not $nativePassed -and
        $csharpStage -eq 'capture-session' -and
        $nativeStage -eq 'capture-session' -and
        -not [string]::IsNullOrWhiteSpace($csharpHResult) -and
        $csharpHResult -eq $nativeHResult
    )
    $bothItemsEmpty = (
        $null -ne $csharpItemWidth -and $null -ne $csharpItemHeight -and
        $null -ne $nativeItemWidth -and $null -ne $nativeItemHeight -and
        $csharpItemWidth -eq 0 -and $csharpItemHeight -eq 0 -and
        $nativeItemWidth -eq 0 -and $nativeItemHeight -eq 0
    )

    $classification = if ($csharpPassed -and $nativePassed) {
        'BOTH_PASS'
    } elseif (-not $csharpPassed -and $nativePassed) {
        'CSHARP_PATH_DIVERGES_FROM_NATIVE'
    } elseif ($csharpPassed -and -not $nativePassed) {
        'NATIVE_REFERENCE_DIVERGES_FROM_CSHARP'
    } elseif ($sameSessionFailure) {
        'BOTH_FAIL_SAME_CAPTURE_SESSION_HRESULT'
    } elseif ($bothItemsEmpty) {
        'BOTH_CREATE_FOR_WINDOW_ITEMS_EMPTY_OR_UNUSABLE'
    } else {
        'BOTH_FAIL_DIFFERENTLY'
    }

    $summary = [ordered]@{
        schemaVersion = 1
        branch = $actualBranch
        head = $actualHead
        fixturePid = $fixtureProcess.Id
        sameHwnd = $hwndHex
        sameHwndGuaranteed = $true
        csharp = [ordered]@{
            exitCode = $csharpRun.exitCode
            verdict = if ($null -ne $csharpReport) { [string]$csharpReport.verdict } else { $null }
            stage = $csharpStage
            hresult = $csharpHResult
            itemWidth = $csharpItemWidth
            itemHeight = $csharpItemHeight
            reportPath = $csharpReportPath
        }
        native = [ordered]@{
            exitCode = $nativeRun.exitCode
            verdict = if ($null -ne $nativeReport) { [string]$nativeReport.verdict } else { $null }
            stage = $nativeStage
            hresult = $nativeHResult
            itemWidth = $nativeItemWidth
            itemHeight = $nativeItemHeight
            frameCount = if ($null -ne $nativeReport) { [long]$nativeReport.frameCount } else { $null }
            bufferSource = if ($null -ne $nativeReport) { [string]$nativeReport.bufferSource } else { $null }
            reportPath = $nativeReportPath
        }
        sameCaptureSessionFailure = $sameSessionFailure
        bothItemsEmpty = $bothItemsEmpty
        classification = $classification
        automaticProductDecision = 'NONE'
        interpretation = switch ($classification) {
            'BOTH_PASS' { 'C# e C++/WinRT independente entregaram frames no mesmo HWND; avançar para presenter/frame-health/isolation.' }
            'CSHARP_PATH_DIVERGES_FROM_NATIVE' { 'O caminho nativo funciona no mesmo HWND; investigar exclusivamente projection/ABI/runtime C#.' }
            'NATIVE_REFERENCE_DIVERGES_FROM_CSHARP' { 'O C# funciona, mas o probe nativo diverge; revisar apenas o reference probe antes de inferir causa de produto.' }
            'BOTH_FAIL_SAME_CAPTURE_SESSION_HRESULT' { 'C# e C++ falharam no mesmo CreateCaptureSession/HRESULT no mesmo HWND; CsWinRT deixa de ser suspeito principal.' }
            'BOTH_CREATE_FOR_WINDOW_ITEMS_EMPTY_OR_UNUSABLE' { 'Ambos os caminhos CreateForWindow produziram metadata vazia/inutilizável; investigar estado/compatibilidade HWND/WGC.' }
            default { 'As implementações falharam de modos diferentes; usar os dois relatórios sem mascarar a divergência.' }
        }
    }

    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding utf8
    @(
        $buildLog,
        "=== SAME HWND ===`n$header",
        "=== CSHARP PRODUCT CANDIDATE ===`n$($csharpRun.output)",
        "=== NATIVE SESSION REFERENCE ===`n$($nativeRun.output)",
        "=== SUMMARY ===`n$($summary | ConvertTo-Json -Depth 12)"
    ) | Set-Content -LiteralPath $logPath -Encoding utf8

    Write-Host "CSHARP_REPORT=$csharpReportPath"
    Write-Host "NATIVE_REPORT=$nativeReportPath"
    Write-Host "AB_SUMMARY=$summaryPath"
    Write-Host "AB_LOG=$logPath"
    Write-Host "AB_CLASSIFICATION=$classification"

    if ($csharpPassed -and $nativePassed) { exit 0 }
    exit 2
}
finally {
    if ($null -ne $fixtureProcess -and -not $fixtureProcess.HasExited) {
        Stop-Process -Id $fixtureProcess.Id -Force -ErrorAction SilentlyContinue
        try { $fixtureProcess.WaitForExit(5000) | Out-Null } catch {}
    }
    if ($null -ne $fixtureProcess) { $fixtureProcess.Dispose() }
}
