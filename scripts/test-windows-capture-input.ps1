[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string] $ExpectedHeadSha,

    [string] $OutputDirectory = (Join-Path (Get-Location) 'poc1-physical-evidence\windows-captured-surface\input')
)

$ErrorActionPreference = 'Stop'
$expectedBranches = @('poc/cloudos-windows-captured-surface', 'integration/cloudos-unified-runtime')
$repoRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
$fixtureProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Fixture\CloudOS.WindowsCapture.Fixture.csproj'
$fixtureExe = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.Fixture\bin\Release\net8.0-windows\CloudOS.WindowsCapture.Fixture.exe'
$inputProbeProject = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.InputProbe\CloudOS.WindowsCapture.InputProbe.csproj'
$inputProbeDll = Join-Path $repoRoot 'desktop\CloudOS.WindowsCapture.InputProbe\bin\Release\net8.0-windows10.0.19041.0\CloudOS.WindowsCapture.InputProbe.dll'
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$reportPath = Join-Path $outputRoot 'fixture-targeted-input.json'
$logPath = Join-Path $outputRoot 'fixture-targeted-input.log'

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
    if ($expectedBranches -notcontains $branch) { throw "Branch incorreto. esperado=$($expectedBranches -join ',') atual=$branch" }
    if ($head -ne $ExpectedHeadSha) { throw "HEAD incorreto. esperado=$ExpectedHeadSha atual=$head" }
    return [pscustomobject]@{ branch = $branch; head = $head }
}

function Wait-MainWindow {
    param([Parameter(Mandatory)] [System.Diagnostics.Process] $Process)
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if ($Process.HasExited) { throw "Fixture encerrou antes do input probe. exit=$($Process.ExitCode)" }
        $Process.Refresh()
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) { return $Process.MainWindowHandle }
        Start-Sleep -Milliseconds 100
    }
    throw 'Fixture não expôs MainWindowHandle em 10 segundos.'
}

$repo = Assert-RepositoryState
$dotnet = Resolve-DotNet
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
Remove-Item -LiteralPath $reportPath, $logPath -Force -ErrorAction SilentlyContinue

Write-Host "INPUT_HARNESS_BRANCH=$($repo.branch)"
Write-Host "INPUT_HARNESS_HEAD=$($repo.head)"

& $dotnet build $fixtureProject -c Release --nologo
if ($LASTEXITCODE -ne 0) { throw 'Fixture build failed.' }
& $dotnet build $inputProbeProject -c Release --nologo
if ($LASTEXITCODE -ne 0) { throw 'Input probe build failed.' }

$fixture = $null
try {
    $fixture = Start-Process -FilePath $fixtureExe -PassThru
    $hwnd = Wait-MainWindow -Process $fixture
    Write-Host ('FIXTURE_PID={0}' -f $fixture.Id)
    Write-Host ('FIXTURE_HWND=0x{0:X}' -f $hwnd.ToInt64())

    $output = & $dotnet $inputProbeDll --pid $fixture.Id --output $reportPath 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).TrimEnd()
    $text | Set-Content -LiteralPath $logPath -Encoding utf8NoBOM
    Write-Host $text

    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        throw "Input probe did not write report: $reportPath"
    }

    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    Write-Host '=== TARGETED INPUT REPORT ==='
    Write-Host ($report | ConvertTo-Json -Depth 10)
    Write-Host "REPORT=$reportPath"
    Write-Host "LOG=$logPath"

    if ($exitCode -ne 0 -or $report.verdict -ne 'PASS') {
        Write-Error "INPUT_GATE=FAIL exit=$exitCode verdict=$($report.verdict)"
        exit 2
    }

    Write-Host 'INPUT_GATE=PASS targeted pointer+keyboard observed; replay/stale generation rejected.'
    exit 0
}
finally {
    if ($null -ne $fixture) {
        try {
            if (-not $fixture.HasExited) { $fixture.Kill($true) }
            $fixture.WaitForExit(5000)
        } catch { }
        $fixture.Dispose()
    }
}
