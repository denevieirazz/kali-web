param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [switch]$ProbeReadyOnce
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Start-ExplorerFallback {
    $windows = [Environment]::GetFolderPath('Windows')
    if ([string]::IsNullOrWhiteSpace($windows)) { return }
    $explorer = Join-Path $windows 'explorer.exe'
    if (Test-Path -LiteralPath $explorer -PathType Leaf) {
        Start-Process -FilePath $explorer | Out-Null
    }
}

try {
    $module = Join-Path $PSScriptRoot 'CloudOS.Deployment.V13.psm1'
    if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
        throw "Stable V13 deployment module is missing: $module"
    }
    Import-Module -Name $module -Force

    $status = Get-CloudOSDeploymentStatus -InstallRoot $InstallRoot
    if (-not $status.installed -or -not $status.active_valid -or [string]::IsNullOrWhiteSpace([string]$status.active_version)) {
        throw 'Installed CloudOS deployment is not valid enough to become the logon shell.'
    }

    $paths = Get-CloudOSDeploymentPaths -InstallRoot $InstallRoot
    $activeRoot = Join-Path $paths.Versions ([string]$status.active_version)
    [void](Test-CloudOSPayload -PackageRoot $activeRoot -SkipSupervisorSelfTest)
    $supervisor = Join-Path $activeRoot 'CloudOS.Supervisor.exe'
    if (-not (Test-Path -LiteralPath $supervisor -PathType Leaf)) {
        throw "Active CloudOS Supervisor is missing: $supervisor"
    }

    if ($ProbeReadyOnce) {
        $process = Start-Process -FilePath $supervisor `
            -ArgumentList @('--probe-ready-once', '--probe-no-explorer') `
            -WorkingDirectory $activeRoot -PassThru -Wait -WindowStyle Hidden
        exit $process.ExitCode
    }

    $process = Start-Process -FilePath $supervisor -WorkingDirectory $activeRoot -PassThru -Wait
    # The external Supervisor already falls back to Explorer on readiness/crash-loop failure.
    # Starting Explorer again after Supervisor exits is an independent final recovery path.
    Start-ExplorerFallback
    exit 0
}
catch {
    Write-Error $_
    if (-not $ProbeReadyOnce) {
        Start-ExplorerFallback
    }
    exit 20
}
