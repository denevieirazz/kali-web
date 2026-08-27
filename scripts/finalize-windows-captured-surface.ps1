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
            skipped = $false
            reason = $null
        }
    }
    finally {
        $process.Dispose()
    }
}

function New-SkippedGate {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Reason
    )

    Add-Content -LiteralPath $logPath -Encoding utf8 -Value "=== $Name ===`nSKIPPED: $Reason"
    return [PSCustomObject]@{
        name = $Name
        exitCode = $null
        passed = $false
        skipped = $true
        reason = $Reason
    }
}

function Read-JsonOptional {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { return $null }
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

# Keep presentation independent from the matrix so one failure never masks the other.
$presenter = Invoke-Gate `
    -Name 'HOST_OWNED_PRESENTER' `
    -Script (Join-Path $PSScriptRoot 'test-windows-capture-presenter.ps1') `
    -Arguments @(
        '-ExpectedHeadSha', $ExpectedHeadSha,
        '-Seconds', [string]$CaptureSeconds,
        '-MinimumFrames', [string]$MinimumFrames
    )

# Input is intentionally independent from WGC. It proves the targeted non-global injector,
# child routing and generation/replay gate even while HWND capture itself is blocked.
$input = Invoke-Gate `
    -Name 'TARGETED_INPUT' `
    -Script (Join-Path $PSScriptRoot 'test-windows-capture-input.ps1') `
    -Arguments @(
        '-ExpectedHeadSha', $ExpectedHeadSha,
        '-OutputDirectory', (Join-Path $evidenceDir 'input')
    )

# Source isolation is useful only after the ordinary visible HWND product candidate captures.
# Skip it when the matrix is blocked instead of wasting time on cloak/hide/minimize states.
$sourceIsolation = if ($matrix.passed) {
    Invoke-Gate `
        -Name 'SOURCE_ISOLATION' `
        -Script (Join-Path $PSScriptRoot 'test-windows-capture-source-isolation.ps1') `
        -Arguments @(
            '-ExpectedHeadSha', $ExpectedHeadSha,
            '-CaptureSeconds', [string]$CaptureSeconds,
            '-MinimumFrames', [string]$MinimumFrames,
            '-OutputDirectory', (Join-Path $evidenceDir 'source-isolation')
        )
} else {
    New-SkippedGate `
        -Name 'SOURCE_ISOLATION' `
        -Reason 'Visible HWND product candidate is not green; isolation modes would not be product-decision evidence.'
}

$matrixSummary = Read-JsonOptional (Join-Path $evidenceDir 'fixture-wgc-matrix-summary.json')
$presenterReport = Read-JsonOptional (Join-Path $evidenceDir 'fixture-presenter-smoke.json')
$inputReport = Read-JsonOptional (Join-Path $evidenceDir 'input\fixture-targeted-input.json')
$sourceIsolationSummary = Read-JsonOptional (Join-Path $evidenceDir 'source-isolation\source-isolation-summary.json')

$physicalReady = $matrix.passed -and $presenter.passed -and $input.passed -and $sourceIsolation.passed
$nextAction = if (-not $matrix.passed) {
    'Diagnosticar primeiro o lane HWND/item/session usando matrix + C++ reference; não culpar presenter/input.'
} elseif (-not $presenter.passed) {
    'WGC entregou frames; diagnosticar exclusivamente Host-owned D3D11/DXGI presentation.'
} elseif (-not $input.passed) {
    'Captura/apresentação chegaram ao gate; diagnosticar targeted input/focus sem SendInput global.'
} elseif (-not $sourceIsolation.passed) {
    'Captura/apresentação/input passaram; revisar somente o experimento de source isolation e seus logs.'
} else {
    'Foundation física completa: avançar para app Win32 real, Brave GPU, frame-health, Alt+Tab/desktop UX e integração candidate do bridge.'
}

$summary = [ordered]@{
    schemaVersion = 2
    branch = $actualBranch
    head = $actualHead
    startedAtUtc = $startedAt.ToString('O')
    completedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
    gates = @($matrix, $presenter, $input, $sourceIsolation)
    matrix = $matrixSummary
    presenter = $presenterReport
    targetedInput = $inputReport
    sourceIsolation = $sourceIsolationSummary
    physicalReady = $physicalReady
    nextAction = $nextAction
}

$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryPath -Encoding utf8
Write-Host "FINALIZATION_SUMMARY=$summaryPath"
Write-Host "FINALIZATION_LOG=$logPath"

if ($summary.physicalReady) {
    Write-Host 'WINDOWS_CAPTURED_SURFACE_FOUNDATION=PASS'
    exit 0
}

Write-Host 'WINDOWS_CAPTURED_SURFACE_FOUNDATION=NOT_READY'
exit 2
