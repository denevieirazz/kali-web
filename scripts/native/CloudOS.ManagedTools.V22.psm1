Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ManagedTools = @(
    'CloudOS.HealthGate.V22.psm1',
    'repair-cloudos-native-v22.ps1',
    'get-cloudos-recovery-status-v22.ps1',
    'configure-cloudos-wer-v22.ps1'
)

function Assert-CloudOSManagedRootV22 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InstallRoot)

    $root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $state = Join-Path $root 'state\deployment-v13.json'
    if (-not (Test-Path -LiteralPath $state -PathType Leaf)) {
        throw "Refusing V22 tool sync for unmanaged root: $root"
    }
    $record = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
    if ([int]$record.schema -ne 13 -or [string]$record.product -ne 'CloudOS Native Shell') {
        throw "Refusing V22 tool sync for incompatible managed state: $state"
    }
    return $root
}

function Install-CloudOSManagedToolsV22 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$InstallRoot
    )

    $source = (Resolve-Path -LiteralPath $SourceRoot).Path
    $root = Assert-CloudOSManagedRootV22 -InstallRoot $InstallRoot
    $tools = Join-Path $root 'tools'
    New-Item -ItemType Directory -Path $tools -Force | Out-Null

    foreach ($name in $script:ManagedTools) {
        $from = Join-Path $source $name
        if (-not (Test-Path -LiteralPath $from -PathType Leaf)) {
            throw "CloudOS V22 managed tool missing from source package: $name"
        }
        Copy-Item -LiteralPath $from -Destination (Join-Path $tools $name) -Force
    }

    $repair = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\repair-cloudos-native-v22.ps1" -InstallRoot "%ROOT%"
exit /b %ERRORLEVEL%
'@
    [IO.File]::WriteAllText(
        (Join-Path $root 'Reparar CloudOS.cmd'),
        $repair,
        [Text.Encoding]::ASCII)

    $recoveryStatus = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\get-cloudos-recovery-status-v22.ps1" | more
exit /b %ERRORLEVEL%
'@
    [IO.File]::WriteAllText(
        (Join-Path $root 'Status Recuperacao V22.cmd'),
        $recoveryStatus,
        [Text.Encoding]::ASCII)

    $werStatus = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\configure-cloudos-wer-v22.ps1" -Status | more
exit /b %ERRORLEVEL%
'@
    [IO.File]::WriteAllText(
        (Join-Path $root 'Status Crash Dumps V22.cmd'),
        $werStatus,
        [Text.Encoding]::ASCII)

    return [pscustomobject]@{
        schema = 22
        installed = $true
        install_root = $root
        tools_root = $tools
        tools = @($script:ManagedTools)
    }
}

Export-ModuleMember -Function @(
    'Assert-CloudOSManagedRootV22',
    'Install-CloudOSManagedToolsV22'
)
