[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string] $ExpectedHeadSha,

    [ValidateRange(1, 30)]
    [int] $CaptureSeconds = 3,

    [ValidateRange(1, 1000)]
    [int] $MinimumFrames = 10,

    [string] $OutputDirectory = (Join-Path (Get-Location) 'poc1-physical-evidence\windows-captured-surface\source-isolation')
)

$ErrorActionPreference = 'Stop'
$expectedBranches = @('poc/cloudos-windows-captured-surface', 'integration/cloudos-unified-runtime')
$repoRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
$fixtureProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Fixture\CloudOS.WindowsCapture.Fixture.csproj'
$fixtureExe = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Fixture\bin\Release\net8.0-windows\CloudOS.WindowsCapture.Fixture.exe'
$probeProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Probe\CloudOS.WindowsCapture.Probe.csproj'
$probeDll = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Probe\bin\Release\net8.0-windows10.0.19041.0\CloudOS.WindowsCapture.Probe.dll'
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$summaryPath = Join-Path $outputRoot 'source-isolation-summary.json'
$logPath = Join-Path $outputRoot 'source-isolation.log'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CloudOSCaptureIsolationNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int X,
        int Y,
        int cx,
        int cy,
        uint uFlags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, uint dwAttribute, ref int pvAttribute, uint cbAttribute);
}
'@

function Resolve-DotNet {
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $localDotNet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
    if (Test-Path -LiteralPath $localDotNet -PathType Leaf) { return $localDotNet }
    throw 'dotnet não foi encontrado.'
}

function Assert-RepositoryState {
    $branch = (git branch --show-current).Trim()
    $head = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível ler o HEAD do Git.' }
    if ($expectedBranches -notcontains $branch) {
        throw "Branch incorreto. esperado=$($expectedBranches -join ',') atual=$branch"
    }
    if ($head -ne $ExpectedHeadSha) {
        throw "HEAD incorreto. esperado=$ExpectedHeadSha atual=$head"
    }
    return [pscustomobject]@{ branch = $branch; head = $head }
}

function Invoke-DotNetBuild {
    param([Parameter(Mandatory)] [string] $Project)
    & $dotnet build $Project -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "Build falhou: $Project" }
}

function Wait-FixtureWindow {
    param([Parameter(Mandatory)] [System.Diagnostics.Process] $Process)

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if ($Process.HasExited) { throw "Fixture encerrou antes de expor HWND. exit=$($Process.ExitCode)" }
        $Process.Refresh()
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) { return $Process.MainWindowHandle }
        Start-Sleep -Milliseconds 100
    }
    throw 'Fixture não expôs MainWindowHandle em 10 segundos.'
}

function Set-Cloak {
    param([IntPtr] $WindowHandle, [bool] $Enabled)
    $value = if ($Enabled) { 1 } else { 0 }
    $result = [CloudOSCaptureIsolationNative]::DwmSetWindowAttribute(
        $WindowHandle,
        13,
        [ref] $value,
        4)
    if ($result -ne 0) { throw ('DwmSetWindowAttribute(DWMWA_CLOAK) falhou: 0x{0:X8}' -f ($result -band 0xffffffff)) }
}

function Restore-Window {
    param(
        [IntPtr] $WindowHandle,
        [CloudOSCaptureIsolationNative+RECT] $OriginalRect
    )

    if (-not [CloudOSCaptureIsolationNative]::IsWindow($WindowHandle)) {
        throw 'HWND da fixture deixou de existir durante a matriz.'
    }

    Set-Cloak -WindowHandle $WindowHandle -Enabled $false
    [void][CloudOSCaptureIsolationNative]::ShowWindow($WindowHandle, 9) # SW_RESTORE
    $flags = 0x0004 -bor 0x0010 -bor 0x0001 # SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOSIZE
    if (-not [CloudOSCaptureIsolationNative]::SetWindowPos(
        $WindowHandle,
        [IntPtr]::Zero,
        $OriginalRect.Left,
        $OriginalRect.Top,
        0,
        0,
        $flags)) {
        throw "SetWindowPos(restore) falhou: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    Start-Sleep -Milliseconds 350
}

function Set-IsolationState {
    param(
        [Parameter(Mandatory)] [ValidateSet('visible', 'offscreen', 'cloaked', 'hidden', 'minimized')] [string] $State,
        [IntPtr] $WindowHandle,
        [CloudOSCaptureIsolationNative+RECT] $OriginalRect
    )

    Restore-Window -WindowHandle $WindowHandle -OriginalRect $OriginalRect

    switch ($State) {
        'visible' { }
        'offscreen' {
            $flags = 0x0004 -bor 0x0010 -bor 0x0001 # SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOSIZE
            if (-not [CloudOSCaptureIsolationNative]::SetWindowPos(
                $WindowHandle,
                [IntPtr]::Zero,
                -32000,
                -32000,
                0,
                0,
                $flags)) {
                throw "SetWindowPos(offscreen) falhou: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            }
        }
        'cloaked' {
            Set-Cloak -WindowHandle $WindowHandle -Enabled $true
        }
        'hidden' {
            [void][CloudOSCaptureIsolationNative]::ShowWindow($WindowHandle, 0) # SW_HIDE
        }
        'minimized' {
            [void][CloudOSCaptureIsolationNative]::ShowWindow($WindowHandle, 6) # SW_MINIMIZE
        }
    }

    Start-Sleep -Milliseconds 350
}

function Invoke-CandidateProbe {
    param(
        [Parameter(Mandatory)] [string] $State,
        [Parameter(Mandatory)] [IntPtr] $WindowHandle
    )

    $reportPath = Join-Path $outputRoot ("source-isolation-{0}.json" -f $State)
    Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue

    $hexHwnd = '0x{0:X}' -f $WindowHandle.ToInt64()
    $output = & $dotnet $probeDll `
        --hwnd $hexHwnd `
        --capture-kind window `
        --item-factory raw `
        --item-projection marshal-interface `
        --abi-lifetime hold `
        --seconds $CaptureSeconds `
        --min-frames $MinimumFrames `
        --output $reportPath 2>&1
    $exitCode = $LASTEXITCODE

    $report = $null
    if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
        try { $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json }
        catch { }
    }

    return [pscustomobject]@{
        state = $State
        exitCode = $exitCode
        reportPath = $reportPath
        verdict = if ($null -ne $report) { $report.Verdict } else { 'NO_REPORT' }
        frameCount = if ($null -ne $report -and $null -ne $report.Capture) { [long]$report.Capture.FrameCount } else { 0 }
        width = if ($null -ne $report -and $null -ne $report.Capture) { [int]$report.Capture.Width } else { 0 }
        height = if ($null -ne $report -and $null -ne $report.Capture) { [int]$report.Capture.Height } else { 0 }
        stage = if ($null -ne $report -and $null -ne $report.Error) { $report.Error.Stage } else { $null }
        nativeHResult = if ($null -ne $report -and $null -ne $report.Error) { $report.Error.NativeHResult } else { $null }
        output = ($output | Out-String).TrimEnd()
    }
}

$repo = Assert-RepositoryState
$dotnet = Resolve-DotNet
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
Remove-Item -LiteralPath $summaryPath, $logPath -Force -ErrorAction SilentlyContinue

Write-Host "SOURCE_ISOLATION_BRANCH=$($repo.branch)"
Write-Host "SOURCE_ISOLATION_HEAD=$($repo.head)"
Write-Host 'OBSERVATION_ONLY=These modes are experiments, never automatic containment fallbacks.'

Invoke-DotNetBuild -Project $fixtureProject
Invoke-DotNetBuild -Project $probeProject

$fixture = $null
$originalRect = [CloudOSCaptureIsolationNative+RECT]::new()
$lanes = [System.Collections.Generic.List[object]]::new()
$startedAt = [DateTimeOffset]::UtcNow

try {
    $fixture = Start-Process -FilePath $fixtureExe -PassThru
    $hwnd = Wait-FixtureWindow -Process $fixture
    if (-not [CloudOSCaptureIsolationNative]::GetWindowRect($hwnd, [ref] $originalRect)) {
        throw "GetWindowRect falhou: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }

    Write-Host ('FIXTURE_PID={0}' -f $fixture.Id)
    Write-Host ('FIXTURE_HWND=0x{0:X}' -f $hwnd.ToInt64())

    foreach ($state in @('visible', 'offscreen', 'cloaked', 'hidden', 'minimized')) {
        Write-Host "=== SOURCE STATE: $state ===" -ForegroundColor Cyan
        Set-IsolationState -State $state -WindowHandle $hwnd -OriginalRect $originalRect
        $lane = Invoke-CandidateProbe -State $state -WindowHandle $hwnd
        $lanes.Add($lane)
        Write-Host $lane.output
    }
}
finally {
    if ($null -ne $fixture) {
        try {
            if (-not $fixture.HasExited -and $fixture.MainWindowHandle -ne [IntPtr]::Zero) {
                Restore-Window -WindowHandle $fixture.MainWindowHandle -OriginalRect $originalRect
            }
        } catch { }
        try {
            if (-not $fixture.HasExited) { $fixture.Kill($true) }
            $fixture.WaitForExit(5000)
        } catch { }
        $fixture.Dispose()
    }
}

$completedAt = [DateTimeOffset]::UtcNow
function Lane-Passed([string] $name) {
    $lane = $lanes | Where-Object { $_.state -eq $name } | Select-Object -First 1
    return $null -ne $lane -and $lane.exitCode -eq 0 -and $lane.verdict -eq 'PASS' -and $lane.frameCount -ge $MinimumFrames
}

$summary = [ordered]@{
    schemaVersion = 1
    experiment = 'CloudOS Windows capture source-isolation matrix'
    observationOnly = $true
    startedAt = $startedAt
    completedAt = $completedAt
    branch = $repo.branch
    head = $repo.head
    productCandidate = 'window/raw/marshal-interface/hold'
    minimumFrames = $MinimumFrames
    captureSeconds = $CaptureSeconds
    visibleBaselinePassed = (Lane-Passed 'visible')
    offscreenCaptureSurvives = (Lane-Passed 'offscreen')
    cloakCaptureSurvives = (Lane-Passed 'cloaked')
    hideCaptureSurvives = (Lane-Passed 'hidden')
    minimizeCaptureSurvives = (Lane-Passed 'minimized')
    automaticContainmentDecision = 'NONE'
    manualUxStillRequired = @('desktop visibility', 'Alt+Tab visibility', 'focus', 'input', 'multi-window behavior')
    lanes = @($lanes | ForEach-Object {
        [ordered]@{
            state = $_.state
            exitCode = $_.exitCode
            verdict = $_.verdict
            frameCount = $_.frameCount
            width = $_.width
            height = $_.height
            stage = $_.stage
            nativeHResult = $_.nativeHResult
            reportPath = $_.reportPath
        }
    })
}

$summaryJson = $summary | ConvertTo-Json -Depth 8
$summaryJson | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
@($lanes | ForEach-Object { "=== $($_.state.ToUpperInvariant()) ===`n$($_.output)" }) -join "`n`n" |
    Set-Content -LiteralPath $logPath -Encoding utf8NoBOM

Write-Host '=== SOURCE ISOLATION SUMMARY ==='
Write-Host $summaryJson
Write-Host "SUMMARY=$summaryPath"
Write-Host "LOG=$logPath"

if (-not (Lane-Passed 'visible')) {
    Write-Error 'SOURCE_ISOLATION_GATE=BLOCKED: visible HWND product candidate did not capture. Isolation results are diagnostic only.'
    exit 2
}

Write-Host 'SOURCE_ISOLATION_GATE=BASELINE_PASS; isolation modes remain experimental until manual UX gates pass.'
exit 0
