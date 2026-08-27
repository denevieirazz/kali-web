param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedHeadSha,

    [ValidateRange(1, 30)]
    [int]$CaptureSeconds = 5,

    [ValidateRange(1, 600)]
    [int]$MinimumFrames = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot

$branch = (git branch --show-current).Trim()
$head = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve repository HEAD.' }
if ($branch -ne 'poc/cloudos-windows-captured-surface') {
    throw "Wrong branch. Expected poc/cloudos-windows-captured-surface, got '$branch'."
}
if ($head -ne $ExpectedHeadSha) {
    throw "Wrong HEAD. Expected $ExpectedHeadSha, got $head."
}

$evidenceDir = Join-Path $repoRoot 'poc1-physical-evidence/windows-captured-surface'
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$reportPath = Join-Path $evidenceDir 'fixture-presenter-smoke.json'
$logPath = Join-Path $evidenceDir 'fixture-presenter-smoke.log'
Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

$logLines = [System.Collections.Generic.List[string]]::new()
function Add-Log([string]$Text) {
    $logLines.Add($Text)
    Write-Host $Text
}

$startedAt = [DateTimeOffset]::UtcNow
Add-Log 'CLOUDOS CAPTURED-SURFACE PRESENTER PHYSICAL SMOKE'
Add-Log "startedAt=$($startedAt.ToString('O'))"
Add-Log "branch=$branch"
Add-Log "head=$head"
Add-Log "captureSeconds=$CaptureSeconds"
Add-Log "minimumFrames=$MinimumFrames"

$fixtureProject = Join-Path $repoRoot 'desktop/CloudOS.WindowsCapture.Fixture/CloudOS.WindowsCapture.Fixture.csproj'
$probeProject = Join-Path $repoRoot 'desktop/CloudOS.WindowsCapture.Presenter.Probe/CloudOS.WindowsCapture.Presenter.Probe.csproj'

Add-Log 'buildingFixture=true'
dotnet build $fixtureProject -c Release --nologo
if ($LASTEXITCODE -ne 0) { throw "Fixture build failed with exit code $LASTEXITCODE." }

Add-Log 'buildingPresenterProbe=true'
dotnet build $probeProject -c Release --nologo
if ($LASTEXITCODE -ne 0) { throw "Presenter probe build failed with exit code $LASTEXITCODE." }

$fixtureExe = Join-Path $repoRoot 'desktop/CloudOS.WindowsCapture.Fixture/bin/Release/net8.0-windows/CloudOS.WindowsCapture.Fixture.exe'
$probeDll = Join-Path $repoRoot 'desktop/CloudOS.WindowsCapture.Presenter.Probe/bin/Release/net8.0-windows10.0.19041.0/CloudOS.WindowsCapture.Presenter.Probe.dll'
if (-not (Test-Path -LiteralPath $fixtureExe -PathType Leaf)) { throw "Fixture executable not found: $fixtureExe" }
if (-not (Test-Path -LiteralPath $probeDll -PathType Leaf)) { throw "Presenter probe not found: $probeDll" }

$fixture = $null
try {
    $fixtureStart = [System.Diagnostics.ProcessStartInfo]::new()
    $fixtureStart.FileName = $fixtureExe
    $fixtureStart.UseShellExecute = $false
    $fixture = [System.Diagnostics.Process]::Start($fixtureStart)
    if ($null -eq $fixture) { throw 'Failed to start capture fixture.' }
    Add-Log "fixturePid=$($fixture.Id)"

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(8)
    $fixtureHwnd = [IntPtr]::Zero
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if ($fixture.HasExited) { throw "Fixture exited before HWND discovery with code $($fixture.ExitCode)." }
        $fixture.Refresh()
        $fixtureHwnd = $fixture.MainWindowHandle
        if ($fixtureHwnd -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 50
    }
    if ($fixtureHwnd -eq [IntPtr]::Zero) { throw 'Fixture did not expose a top-level HWND before timeout.' }
    $fixtureHwndHex = '0x{0:X}' -f $fixtureHwnd.ToInt64()
    Add-Log "fixtureHwnd=$fixtureHwndHex"

    $probeStart = [System.Diagnostics.ProcessStartInfo]::new()
    $probeStart.FileName = 'dotnet'
    foreach ($argument in @(
        $probeDll,
        '--hwnd', $fixtureHwndHex,
        '--seconds', $CaptureSeconds.ToString([Globalization.CultureInfo]::InvariantCulture),
        '--minimum-frames', $MinimumFrames.ToString([Globalization.CultureInfo]::InvariantCulture),
        '--output', $reportPath
    )) {
        $probeStart.ArgumentList.Add($argument)
    }
    $probeStart.UseShellExecute = $false
    $probeStart.CreateNoWindow = $true
    $probeStart.RedirectStandardOutput = $true
    $probeStart.RedirectStandardError = $true

    $probe = [System.Diagnostics.Process]::Start($probeStart)
    if ($null -eq $probe) { throw 'Failed to start presenter probe.' }
    try {
        $stdout = $probe.StandardOutput.ReadToEnd()
        $stderr = $probe.StandardError.ReadToEnd()
        $probe.WaitForExit()
        Add-Log "probeExitCode=$($probe.ExitCode)"
        if (-not [string]::IsNullOrWhiteSpace($stdout)) { $logLines.Add($stdout.TrimEnd()) }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) { $logLines.Add($stderr.TrimEnd()) }

        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
            throw "Presenter probe did not generate report: $reportPath"
        }
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        Add-Log "verdict=$($report.verdict)"
        Add-Log "presentationHwnd=$($report.presentationHwnd)"
        if ($null -ne $report.capture) {
            Add-Log "captureFrameCount=$($report.capture.frameCount)"
            Add-Log "sinkDeliveredFrames=$($report.capture.frameSink.deliveredFrames)"
        }
        if ($null -ne $report.presentation) {
            Add-Log "presentedFrames=$($report.presentation.presentation.presentedFrameCount)"
            Add-Log "presenterAcceptedFrames=$($report.presentation.acceptedFrames)"
        }

        if ($probe.ExitCode -ne 0) {
            throw "Captured-surface presenter smoke failed with exit code $($probe.ExitCode). Report: $reportPath"
        }
        if ($report.verdict -ne 'PASS') { throw "Presenter report verdict is '$($report.verdict)', expected PASS." }
    }
    finally {
        $probe.Dispose()
    }
}
finally {
    if ($null -ne $fixture) {
        try {
            if (-not $fixture.HasExited) { $fixture.Kill($true) }
            $fixture.WaitForExit(5000) | Out-Null
        }
        catch {}
        $fixture.Dispose()
    }
    Add-Log "completedAt=$([DateTimeOffset]::UtcNow.ToString('O'))"
    [IO.File]::WriteAllLines($logPath, $logLines)
}

Write-Host "Presenter report: $reportPath"
Write-Host "Presenter log: $logPath"
