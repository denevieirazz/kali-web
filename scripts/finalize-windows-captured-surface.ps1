[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string] $ExpectedHeadSha,

    [ValidateRange(1, 30)]
    [int] $CaptureSeconds = 5,

    [ValidateRange(1, 600)]
    [int] $MinimumFrames = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$expectedBranch = 'poc/cloudos-windows-captured-surface'
$actualBranch = (git branch --show-current).Trim()
$actualHead = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível resolver o HEAD do Git.' }
if ($actualBranch -ne $expectedBranch) { throw "Branch incorreta. expected=$expectedBranch actual=$actualBranch" }
if ($actualHead -ne $ExpectedHeadSha) { throw "HEAD incorreto. expected=$ExpectedHeadSha actual=$actualHead" }

$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$evidenceDir = Join-Path $repoRoot 'poc1-physical-evidence\windows-captured-surface'
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$summaryPath = Join-Path $evidenceDir 'physical-finalization-summary.json'
$logPath = Join-Path $evidenceDir 'physical-finalization.log'
Remove-Item -LiteralPath $summaryPath, $logPath -Force -ErrorAction SilentlyContinue

function Invoke-Gate {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Script,
        [Parameter(Mandatory)] [string[]] $Arguments
    )

    Add-Content -LiteralPath $logPath -Encoding utf8 -Value "=== $Name ==="
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pwsh
    foreach ($argument in @('-NoProfile', '-File', $Script) + $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $combined = ($stdout + [Environment]::NewLine + $stderr).Trim()
        if ($combined) {
            Add-Content -LiteralPath $logPath -Encoding utf8 -Value $combined
            Write-Host $combined
        }
        return [PSCustomObject]@{
            name = $Name
            exitCode = $process.ExitCode
            passed = ($process.ExitCode -eq 0)
        }
    }
    finally {
        $process.Dispose()
    }
}

$startedAt = [DateTimeOffset]::UtcNow
$matrix = Invoke-Gate `
    -Name 'HWND_WGC_MATRIX' `
    -Script (Join-Path $PSScriptRoot 'test-windows-capture-probe.ps1') `
    -Arguments @(
        '-ExpectedHeadSha', $ExpectedHeadSha,
        '-CaptureSeconds', [string]$CaptureSeconds,
        '-MinimumFrames', [string]$MinimumFrames,
        '-OutputDirectory', $evidenceDir
    )

# Run the presenter independently even when the HWND matrix fails. This preserves a
# separate diagnostic boundary between WGC item/session setup and native presentation.
$presenter = Invoke-Gate `
    -Name 'HOST_OWNED_PRESENTER' `
    -Script (Join-Path $PSScriptRoot 'test-windows-capture-presenter.ps1') `
    -Arguments @(
        '-ExpectedHeadSha', $ExpectedHeadSha,
        '-Seconds', [string]$CaptureSeconds,
        '-MinimumFrames', [string]$MinimumFrames
    )

$matrixSummaryPath = Join-Path $evidenceDir 'fixture-wgc-matrix-summary.json'
$presenterReportPath = Join-Path $evidenceDir 'fixture-presenter-smoke.json'
$matrixSummary = if (Test-Path -LiteralPath $matrixSummaryPath -PathType Leaf) {
    Get-Content -LiteralPath $matrixSummaryPath -Raw | ConvertFrom-Json
} else { $null }
$presenterReport = if (Test-Path -LiteralPath $presenterReportPath -PathType Leaf) {
    Get-Content -LiteralPath $presenterReportPath -Raw | ConvertFrom-Json
} else { $null }

$summary = [ordered]@{
    schemaVersion = 1
    branch = $actualBranch
    head = $actualHead
    startedAtUtc = $startedAt.ToString('O')
    completedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
    gates = @($matrix, $presenter)
    matrix = $matrixSummary
    presenter = $presenterReport
    physicalReady = ($matrix.passed -and $presenter.passed)
    nextAction = if (-not $matrix.passed) {
        'Diagnosticar primeiro o lane HWND/item/session usando matrix + C++ reference; não culpar o presenter.'
    } elseif (-not $presenter.passed) {
        'WGC entregou frames; diagnosticar exclusivamente Host-owned D3D11/DXGI presentation.'
    } else {
        'Avançar para app Win32 real, Brave GPU habilitada, frame-health, source isolation e input/UX.'
    }
}

$summary | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $summaryPath -Encoding utf8
Write-Host "FINALIZATION_SUMMARY=$summaryPath"
Write-Host "FINALIZATION_LOG=$logPath"

if ($summary.physicalReady) {
    Write-Host 'WINDOWS_CAPTURED_SURFACE_FOUNDATION=PASS'
    exit 0
}

Write-Host 'WINDOWS_CAPTURED_SURFACE_FOUNDATION=NOT_READY'
exit 2
