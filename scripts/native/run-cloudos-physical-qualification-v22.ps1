[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$Distribution = 'kali-linux',
    [switch]$RequireKali,
    [switch]$RunDestructiveWslTerminate,
    [switch]$SkipBuild,
    [ValidateRange(30, 172800)][int]$SoakSeconds = 300,
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$scriptRoot = Join-Path $rootPath 'scripts\native'
$build = Join-Path $rootPath 'desktop\CloudOS.NativeShell\bin\Release'
$artifactDir = Join-Path $rootPath 'desktop\CloudOS.NativeShell\artifacts\physical-v22'
New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null

if (-not $OutputPath) {
    $OutputPath = Join-Path $artifactDir 'cloudos-physical-qualification-v22.json'
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }

$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$steps = [Collections.Generic.List[object]]::new()
$failures = [Collections.Generic.List[string]]::new()
$started = [DateTime]::UtcNow

function Invoke-QualificationStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [string]$EvidencePath = ''
    )

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $status = 'pass'
    $errorText = $null
    try {
        & $Action
        if ($LASTEXITCODE -ne 0) {
            throw "Process exit code $LASTEXITCODE"
        }
    }
    catch {
        $status = 'fail'
        $errorText = $_.Exception.Message
        $failures.Add("${Name}:$errorText")
    }
    finally {
        $timer.Stop()
    }

    $steps.Add([pscustomobject][ordered]@{
        name = $Name
        status = $status
        elapsed_ms = [int64]$timer.ElapsedMilliseconds
        evidence = if ($EvidencePath) { [IO.Path]::GetFullPath($EvidencePath) } else { $null }
        error = $errorText
    })

    if ($status -eq 'fail') {
        throw "Physical qualification stopped at '$Name': $errorText"
    }
}

try {
    $contractSuite = Join-Path $scriptRoot 'test-native-contract-suite.ps1'
    Invoke-QualificationStep -Name 'structural_contracts' -Action {
        & $pwsh -NoLogo -NoProfile -File $contractSuite
    }

    if (-not $SkipBuild) {
        $buildCmd = Join-Path $scriptRoot 'build-cloudos-native.cmd'
        Invoke-QualificationStep -Name 'release_build' -Action {
            & $buildCmd Release
        }
    }

    foreach ($binary in @(
        'CloudOS.exe',
        'CloudOS.NativeRuntime.dll',
        'CloudOS.Supervisor.exe',
        'CloudOS.SystemBroker.exe',
        'CloudOS.BrokerProbe.exe'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $build $binary) -PathType Leaf)) {
            throw "Release build is missing $binary at $build"
        }
    }

    $verify = Join-Path $scriptRoot 'verify-native-build-manifest.ps1'
    Invoke-QualificationStep -Name 'build_integrity' -Action {
        & $pwsh -NoLogo -NoProfile -File $verify -Root $rootPath -Configuration Release -BuildDirectory $build -CheckSourceFingerprint
    }

    $supervisorEvidence = Join-Path $artifactDir 'supervisor-v22.json'
    $supervisorSmoke = Join-Path $scriptRoot 'run-native-supervisor-smoke-v22.ps1'
    Invoke-QualificationStep -Name 'supervisor_recovery' -EvidencePath $supervisorEvidence -Action {
        & $pwsh -NoLogo -NoProfile -File $supervisorSmoke -Root $rootPath -BuildDirectory $build -OutputPath $supervisorEvidence
    }

    $lifecycleEvidence = Join-Path $artifactDir 'lifecycle-v10.json'
    $lifecycleSmoke = Join-Path $scriptRoot 'run-native-lifecycle-smoke-v10.ps1'
    Invoke-QualificationStep -Name 'lifecycle_simulated' -EvidencePath $lifecycleEvidence -Action {
        & $pwsh -NoLogo -NoProfile -File $lifecycleSmoke -Root $rootPath -BuildDirectory $build -OutputPath $lifecycleEvidence
    }

    $packageScript = Join-Path $scriptRoot 'package-cloudos-native.ps1'
    Invoke-QualificationStep -Name 'portable_package' -Action {
        & $pwsh -NoLogo -NoProfile -File $packageScript -Root $rootPath -Configuration Release -BuildDirectory $build
    }
    $packageRoot = Join-Path $rootPath 'desktop\CloudOS.NativeShell\artifacts\CloudOS-Native-Release-x64'

    $installEvidence = Join-Path $artifactDir 'install-v22.json'
    $installSmoke = Join-Path $scriptRoot 'run-native-install-v22-smoke.ps1'
    Invoke-QualificationStep -Name 'clean_install_transaction' -EvidencePath $installEvidence -Action {
        & $pwsh -NoLogo -NoProfile -File $installSmoke -PackageRoot $packageRoot -OutputPath $installEvidence
    }

    $wslEvidence = Join-Path $artifactDir 'wsl-runtime-v22.json'
    $wslSmoke = Join-Path $scriptRoot 'run-wsl-runtime-smoke-v22.ps1'
    Invoke-QualificationStep -Name 'wsl_runtime' -EvidencePath $wslEvidence -Action {
        & $pwsh -NoLogo -NoProfile -File $wslSmoke -Distro $Distribution -Configuration Release -TimeoutMs 8000 -OutputPath $wslEvidence
    }

    $terminalEvidence = Join-Path $artifactDir 'terminal-wsl-v22.json'
    $terminalSmoke = Join-Path $scriptRoot 'run-terminal-wsl-physical-v22.ps1'
    Invoke-QualificationStep -Name 'terminal_conpty_wsl' -EvidencePath $terminalEvidence -Action {
        $args = @(
            '-NoLogo', '-NoProfile', '-File', $terminalSmoke,
            '-Root', $rootPath,
            '-BuildDirectory', $build,
            '-Distribution', $Distribution,
            '-TimeoutSeconds', '12',
            '-OutputPath', $terminalEvidence
        )
        if ($RequireKali) { $args += '-RequireKali' }
        if ($RunDestructiveWslTerminate) { $args += '-AllowTerminateDistribution' }
        & $pwsh @args
    }

    $soakEvidence = Join-Path $artifactDir 'soak-v9.json'
    $soak = Join-Path $scriptRoot 'run-native-soak-v9.ps1'
    Invoke-QualificationStep -Name 'stability_soak' -EvidencePath $soakEvidence -Action {
        & $pwsh -NoLogo -NoProfile -File $soak -Root $rootPath -BuildDirectory $build -OutputPath $soakEvidence -DurationSeconds $SoakSeconds -Launch
    }
}
catch {
    if ($failures.Count -eq 0) {
        $failures.Add(('Harness:' + $_.Exception.Message))
    }
}

$manualRequired = @(
    [pscustomobject]@{ gate = 'physical_sleep_resume'; reason = 'Requires actual Windows sleep/resume transition.' },
    [pscustomobject]@{ gate = 'physical_lock_unlock'; reason = 'Requires an interactive lock/unlock session.' },
    [pscustomobject]@{ gate = 'rdp_connect_disconnect'; reason = 'Requires a real RDP session transition.' },
    [pscustomobject]@{ gate = 'monitor_hotplug_dpi'; reason = 'Requires monitor/topology/DPI changes on physical or nested-display hardware.' },
    [pscustomobject]@{ gate = 'explorer_safe_mode_login'; reason = 'Requires real shell replacement/logon and Explorer fallback observation.' },
    [pscustomobject]@{ gate = 'production_authenticode'; reason = 'Requires the real production Code Signing private key/certificate and timestamp service.' },
    [pscustomobject]@{ gate = '72h_soak'; reason = 'Requires a dedicated 259200-second run; the current harness intentionally caps one invocation at 172800 seconds, so use consecutive evidence runs or extend only after review.' }
)

$report = [ordered]@{
    schema = 22
    test = 'CloudOS Physical Qualification V22'
    started_utc = $started.ToString('o')
    collected_utc = [DateTime]::UtcNow.ToString('o')
    verdict = if ($failures.Count -eq 0) { 'pass_automated_scope' } else { 'fail' }
    distro = $Distribution
    require_kali = [bool]$RequireKali
    destructive_wsl_terminate = [bool]$RunDestructiveWslTerminate
    requested_soak_seconds = $SoakSeconds
    steps = $steps.ToArray()
    failures = $failures.ToArray()
    manual_required = $manualRequired
    interpretation = 'pass_automated_scope means every gate executable on this Windows machine passed. It does not certify the manual_required physical/session/signing gates.'
}

$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8

if ($failures.Count -gt 0) {
    Write-Error "FAIL: CloudOS physical qualification failed. Report: $OutputPath"
    exit 1
}

Write-Host "PASS: CloudOS physical qualification automated scope passed. Report: $OutputPath"
Write-Host 'MANUAL GATES REMAIN: sleep/resume, lock/unlock, RDP, monitor hotplug/DPI, real shell-login Explorer fallback, production Authenticode and 72h endurance.'
