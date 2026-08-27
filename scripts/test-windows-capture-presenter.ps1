param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedHeadSha,

    [ValidateRange(1, 30)]
    [int]$Seconds = 5,

    [ValidateRange(1, 600)]
    [int]$MinimumFrames = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$expectedBranch = 'poc/cloudos-windows-captured-surface'
$actualBranch = (git branch --show-current).Trim()
$actualHead = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve git HEAD.' }
if ($actualBranch -ne $expectedBranch) {
    throw "Wrong branch. expected=$expectedBranch actual=$actualBranch"
}
if ($actualHead -ne $ExpectedHeadSha) {
    throw "Wrong HEAD. expected=$ExpectedHeadSha actual=$actualHead"
}

$evidenceDir = Join-Path $repoRoot 'poc1-physical-evidence\windows-captured-surface'
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$reportPath = Join-Path $evidenceDir 'fixture-presenter-smoke.json'
$logPath = Join-Path $evidenceDir 'fixture-presenter-smoke.log'
Remove-Item -LiteralPath $reportPath, $logPath -Force -ErrorAction SilentlyContinue

$fixtureProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Fixture\CloudOS.WindowsCapture.Fixture.csproj'
$fixtureExe = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Fixture\bin\Release\net8.0-windows\CloudOS.WindowsCapture.Fixture.exe'
$probeProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Presenter.Probe\CloudOS.WindowsCapture.Presenter.Probe.csproj'
$probeDll = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Presenter.Probe\bin\Release\net8.0-windows10.0.19041.0\CloudOS.WindowsCapture.Presenter.Probe.dll'

$fixture = $null
try {
    @(
        "branch=$actualBranch",
        "head=$actualHead",
        'fixtureKind=winforms-overlapped-animated',
        'pipeline=WGC->IDirect3DSurface->ID3D11Texture2D->DXGI swapchain->Host-owned tool HWND'
    ) | Set-Content -LiteralPath $logPath -Encoding utf8

    dotnet build $fixtureProject -c Release --nologo 2>&1 | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) { throw "Fixture build failed with exit $LASTEXITCODE." }

    dotnet build $probeProject -c Release --nologo 2>&1 | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) { throw "Presenter probe build failed with exit $LASTEXITCODE." }

    if (-not (Test-Path -LiteralPath $fixtureExe -PathType Leaf)) { throw "Fixture executable not found: $fixtureExe" }
    if (-not (Test-Path -LiteralPath $probeDll -PathType Leaf)) { throw "Presenter probe not found: $probeDll" }

    $fixture = Start-Process -FilePath $fixtureExe -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    $hwnd = [IntPtr]::Zero
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($fixture.HasExited) { throw "Fixture exited before presenting a window. exit=$($fixture.ExitCode)" }
        $fixture.Refresh()
        $hwnd = $fixture.MainWindowHandle
        if ($hwnd -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 50
    }
    if ($hwnd -eq [IntPtr]::Zero) { throw 'Fixture did not expose a MainWindowHandle within 10 seconds.' }

    @(
        "fixturePid=$($fixture.Id)",
        ('fixtureHwnd=0x{0:X}' -f $hwnd.ToInt64()),
        "seconds=$Seconds",
        "minimumFrames=$MinimumFrames"
    ) | Add-Content -LiteralPath $logPath -Encoding utf8

    $arguments = @(
        $probeDll,
        '--hwnd', ('0x{0:X}' -f $hwnd.ToInt64()),
        '--seconds', [string]$Seconds,
        '--minimum-frames', [string]$MinimumFrames,
        '--output', $reportPath
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'dotnet'
    foreach ($argument in $arguments) { $startInfo.ArgumentList.Add($argument) }
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $probe = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $stdout = $probe.StandardOutput.ReadToEndAsync()
        $stderr = $probe.StandardError.ReadToEndAsync()
        $probe.WaitForExit()
        $combined = (($stdout.GetAwaiter().GetResult()) + [Environment]::NewLine + ($stderr.GetAwaiter().GetResult())).Trim()
        $combined | Add-Content -LiteralPath $logPath -Encoding utf8
        Write-Host $combined
        if ($probe.ExitCode -ne 0) {
            throw "Presenter smoke failed with exit $($probe.ExitCode). See $reportPath and $logPath"
        }
    }
    finally {
        $probe.Dispose()
    }

    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "Presenter probe did not write report: $reportPath" }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($report.schemaVersion -ne 1) { throw "Unexpected presenter report schema: $($report.schemaVersion)" }
    if ($report.verdict -ne 'PASS') { throw "Presenter report verdict is $($report.verdict), expected PASS." }
    if ([int64]$report.capture.frameCount -lt $MinimumFrames) { throw "Insufficient capture frames: $($report.capture.frameCount)" }
    if ([int64]$report.presentation.acceptedFrames -lt $MinimumFrames) { throw "Insufficient presented frames: $($report.presentation.acceptedFrames)" }
    if ([int64]$report.presentation.presentation.presentedFrameCount -lt $MinimumFrames) { throw "Lifecycle recorded insufficient presented frames: $($report.presentation.presentation.presentedFrameCount)" }
    if ([string]::IsNullOrWhiteSpace([string]$report.presentationHwnd) -or $report.presentationHwnd -eq '0x0') { throw 'Presenter report has no Host-owned presentation HWND.' }

    Write-Host 'PRESENTER_SMOKE=PASS'
    Write-Host "REPORT=$reportPath"
    Write-Host "LOG=$logPath"
}
finally {
    if ($null -ne $fixture) {
        try {
            if (-not $fixture.HasExited) { Stop-Process -Id $fixture.Id -Force -ErrorAction SilentlyContinue }
        } finally {
            $fixture.Dispose()
        }
    }
}
