[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'Enable', Mandatory = $true)]
    [switch]$Enable,

    [Parameter(ParameterSetName = 'Disable', Mandatory = $true)]
    [switch]$Disable,

    [Parameter(ParameterSetName = 'Status')]
    [switch]$Status,

    [Parameter(ParameterSetName = 'Enable')]
    [ValidateSet('Mini', 'Full')]
    [string]$DumpType = 'Mini',

    [Parameter(ParameterSetName = 'Enable')]
    [ValidateRange(1, 20)]
    [int]$DumpCount = 5
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$werRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps'
$dumpFolder = '%LOCALAPPDATA%\CloudOS\CrashDumps'
$executables = @(
    'CloudOS.exe',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'cloudos_flutter_shell.exe'
)

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CloudOSWerStatus {
    $records = foreach ($exe in $executables) {
        $key = Join-Path $werRoot $exe
        if (-not (Test-Path -LiteralPath $key)) {
            [pscustomobject]@{
                executable = $exe
                configured = $false
                dump_type = $null
                dump_count = $null
                folder = $null
            }
            continue
        }

        $values = Get-ItemProperty -LiteralPath $key
        [pscustomobject]@{
            executable = $exe
            configured = $true
            dump_type = if ($null -ne $values.DumpType) { [int]$values.DumpType } else { $null }
            dump_count = if ($null -ne $values.DumpCount) { [int]$values.DumpCount } else { $null }
            folder = if ($null -ne $values.DumpFolder) { [string]$values.DumpFolder } else { $null }
        }
    }

    [pscustomobject]@{
        schema = 22
        component = 'CloudOS.WER.LocalDumps'
        configured_count = @($records | Where-Object configured).Count
        requires_admin_to_change = $true
        privacy_warning = 'Crash dumps can contain process memory, file paths, tokens or other sensitive runtime data. They remain local and are never uploaded by this tool.'
        applications = @($records)
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Status') {
    Get-CloudOSWerStatus
    return
}

if (-not (Test-IsAdministrator)) {
    throw 'Changing WER LocalDumps requires an elevated PowerShell session. Status mode does not require elevation.'
}

if ($PSCmdlet.ParameterSetName -eq 'Enable') {
    $expandedDumpFolder = [Environment]::ExpandEnvironmentVariables($dumpFolder)
    New-Item -ItemType Directory -Path $expandedDumpFolder -Force | Out-Null

    # Microsoft documents LocalDumps under HKLM and supports per-application
    # overrides. CloudOS intentionally configures only its own executable names;
    # it never changes the global LocalDumps defaults for unrelated software.
    New-Item -Path $werRoot -Force | Out-Null
    $typeValue = if ($DumpType -eq 'Full') { 2 } else { 1 }

    foreach ($exe in $executables) {
        $key = Join-Path $werRoot $exe
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -LiteralPath $key -Name DumpFolder -PropertyType ExpandString -Value $dumpFolder -Force | Out-Null
        New-ItemProperty -LiteralPath $key -Name DumpCount -PropertyType DWord -Value $DumpCount -Force | Out-Null
        New-ItemProperty -LiteralPath $key -Name DumpType -PropertyType DWord -Value $typeValue -Force | Out-Null
    }

    Write-Warning 'CloudOS crash dumps are now enabled locally. Dump files may contain sensitive process memory. Do not share them without reviewing the privacy impact.'
    Get-CloudOSWerStatus
    return
}

if ($PSCmdlet.ParameterSetName -eq 'Disable') {
    foreach ($exe in $executables) {
        $key = Join-Path $werRoot $exe
        if (Test-Path -LiteralPath $key) {
            # Remove only the CloudOS per-application override. Never delete the
            # WER LocalDumps root or settings owned by other applications.
            Remove-Item -LiteralPath $key -Recurse -Force
        }
    }

    Get-CloudOSWerStatus
}
