[CmdletBinding()]
param(
    [string] $MatrixDirectory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$ProductSha = 'ad9639f1ce8d808d2d532404fd9ca6673244052e'
$ExpectedPrBranch = 'fix/cloudos-runtime-launch-rebind'
$ExpectedEvidenceBranch = 'evidence/pr16-physical-ad9639f'
$AllowedCaseVerdicts = @(
    'PENDING',
    'PASS',
    'PASS_EXPECTED_FAIL_CLOSED',
    'FAIL',
    'BLOCKED_NO_LOCAL_REPRESENTATIVE',
    'NOT_APPLICABLE'
)
$MandatoryCases = @(
    'win32-simple',
    'splash-bootstrap',
    'child-gui',
    'electron-chromium',
    'shortcut-args',
    'dual-instance',
    'close-reopen',
    'multiwindow-limit',
    'stress'
)
$CorePassCases = @('win32-simple','child-gui','close-reopen')

$reportPath = Join-Path $MatrixDirectory 'PHYSICAL_MATRIX_REPORT.json'
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    throw "Missing physical matrix JSON report: $reportPath"
}

try {
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 32
} catch {
    throw "Invalid physical matrix JSON: $($_.Exception.Message)"
}

function Assert-Equal {
    param([string] $Name, $Actual, $Expected)
    if ($Actual -ne $Expected) { throw "$Name mismatch. expected=$Expected actual=$Actual" }
}

Assert-Equal 'productTestedSha' ([string]$report.productTestedSha) $ProductSha
Assert-Equal 'pr' ([int]$report.pr) 16
Assert-Equal 'prBranch' ([string]$report.prBranch) $ExpectedPrBranch
Assert-Equal 'evidenceBranch' ([string]$report.evidenceBranch) $ExpectedEvidenceBranch

if ($report.automatedCi.cloudOsCiBaseline.runId -ne 33168545780 -or $report.automatedCi.cloudOsCiBaseline.conclusion -ne 'success') {
    throw 'CloudOS CI Baseline evidence is not pinned to successful run 33168545780.'
}
if ($report.automatedCi.windowsInstallerCapability.runId -ne 33168545789 -or $report.automatedCi.windowsInstallerCapability.conclusion -ne 'success') {
    throw 'Windows Installer Capability evidence is not pinned to successful run 33168545789.'
}

$cases = @($report.cases)
if ($cases.Count -ne $MandatoryCases.Count) {
    throw "Expected exactly $($MandatoryCases.Count) matrix cases, found $($cases.Count)."
}

$caseNames = @($cases | ForEach-Object { [string]$_.case })
foreach ($caseName in $MandatoryCases) {
    if (@($caseNames | Where-Object { $_ -eq $caseName }).Count -ne 1) {
        throw "Matrix case must appear exactly once: $caseName"
    }
}

foreach ($case in $cases) {
    $verdict = [string]$case.verdict
    if ($AllowedCaseVerdicts -notcontains $verdict) {
        throw "Invalid verdict '$verdict' for case '$($case.case)'."
    }
}

$totals = $report.totals
foreach ($name in @('runs','pass','fail','expectedFailClosed')) {
    $value = [int]$totals.$name
    if ($value -lt 0) { throw "totals.$name cannot be negative." }
}
if ([int]$totals.pass + [int]$totals.fail + [int]$totals.expectedFailClosed -gt [int]$totals.runs) {
    throw 'Report totals are internally inconsistent.'
}

$gate = [string]$report.physicalRuntimeGate
if ($gate -notin @('PENDING','PASS','FAIL')) {
    throw "Invalid physicalRuntimeGate: $gate"
}

if ($gate -eq 'PASS') {
    if ([int]$totals.runs -le 0) { throw 'PASS is impossible with zero physical runs.' }
    if ([int]$totals.fail -ne 0) { throw 'PASS is impossible with physical failures.' }
    if ($report.externalWindowLeak -ne $false) { throw 'PASS requires externalWindowLeak=false.' }
    if ($report.altTabLeak -ne $false) { throw 'PASS requires altTabLeak=false.' }
    if ($report.crossJobAdoption -ne $false) { throw 'PASS requires crossJobAdoption=false.' }
    if ($report.orphanProcess -ne $false) { throw 'PASS requires orphanProcess=false.' }

    foreach ($caseName in $CorePassCases) {
        $case = @($cases | Where-Object { $_.case -eq $caseName })[0]
        if ([string]$case.verdict -ne 'PASS') {
            throw "Core physical case '$caseName' must be PASS before the runtime gate can pass."
        }
    }

    foreach ($case in $cases) {
        if ([string]$case.verdict -in @('PENDING','FAIL')) {
            throw "PASS gate cannot contain case '$($case.case)' with verdict '$($case.verdict)'."
        }
        if ([string]$case.verdict -eq 'BLOCKED_NO_LOCAL_REPRESENTATIVE') {
            $reason = [string]$case.reason
            if ([string]::IsNullOrWhiteSpace($reason)) {
                throw "Blocked case '$($case.case)' needs an explicit reason before PASS is allowed."
            }
        }
    }
}

if ($gate -eq 'FAIL' -and [int]$totals.fail -le 0) {
    throw 'FAIL gate requires at least one recorded physical failure.'
}

Write-Host 'PHYSICAL MATRIX REPORT VALIDATION: PASS' -ForegroundColor Green
Write-Host "productTestedSha=$ProductSha"
Write-Host "physicalRuntimeGate=$gate"
Write-Host "runs=$($totals.runs) pass=$($totals.pass) fail=$($totals.fail) expectedFailClosed=$($totals.expectedFailClosed)"
