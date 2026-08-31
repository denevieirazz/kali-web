Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ActivationSchema = 14
$script:ProductName = 'CloudOS Native Shell'
$script:ProviderName = 'HKCU Winlogon per-user override'
$script:DefaultRegistrySubKey = 'Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
$script:RegistryValueName = 'Shell'
$script:TestRegistryPrefix = 'Software\CloudOS\Tests\ShellActivationV14\'

function Import-CloudOSDeploymentV13 {
    [CmdletBinding()]
    param()

    $module = Join-Path $PSScriptRoot 'CloudOS.Deployment.V13.psm1'
    if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
        throw "CloudOS Deployment V13 module missing beside Shell Activation V14: $module"
    }
    Import-Module -Name $module -Force
}

function Get-CloudOSShellActivationPaths {
    [CmdletBinding()]
    param([string]$InstallRoot)

    Import-CloudOSDeploymentV13
    if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
        $InstallRoot = Get-CloudOSDefaultInstallRoot
    }
    $deployment = Get-CloudOSDeploymentPaths -InstallRoot $InstallRoot
    return [pscustomobject]@{
        Root = $deployment.Root
        Versions = $deployment.Versions
        StateDir = $deployment.StateDir
        ActivationState = Join-Path $deployment.StateDir 'shell-activation-v14.json'
        ActivationJournal = Join-Path $deployment.StateDir 'shell-activation-v14.journal.json'
        ShellDir = Join-Path $deployment.Root 'shell-v14'
        EntryScript = Join-Path (Join-Path $deployment.Root 'shell-v14') 'CloudOS.ShellEntry.V14.ps1'
        EntryCommand = Join-Path (Join-Path $deployment.Root 'shell-v14') 'CloudOS.ShellEntry.V14.cmd'
    }
}

function Write-CloudOSShellJsonAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $json = $Value | ConvertTo-Json -Depth 16
        [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-CloudOSShellJson {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Assert-CloudOSShellState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$State)

    if ([int]$State.schema -ne $script:ActivationSchema -or [string]$State.product -ne $script:ProductName) {
        throw 'CloudOS shell activation state is not a V14 managed state.'
    }
}

function Assert-CloudOSRegistryScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RegistrySubKey,
        [switch]$AllowTestRegistryOverride
    )

    if ($RegistrySubKey.Equals($script:DefaultRegistrySubKey, [StringComparison]::OrdinalIgnoreCase)) {
        return
    }
    if ($AllowTestRegistryOverride -and
        $RegistrySubKey.StartsWith($script:TestRegistryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        return
    }
    throw "Shell Activation V14 only permits the production HKCU Winlogon key or the dedicated CI test subtree. Refused: $RegistrySubKey"
}

function Open-CloudOSCurrentUserRegistryKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RegistrySubKey,
        [switch]$Writable,
        [switch]$Create
    )

    if ($Create) {
        return [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($RegistrySubKey, $true)
    }
    return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($RegistrySubKey, [bool]$Writable)
}

function Get-CloudOSRegistryValueSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RegistrySubKey,
        [string]$ValueName = $script:RegistryValueName
    )

    $key = Open-CloudOSCurrentUserRegistryKey -RegistrySubKey $RegistrySubKey
    if ($null -eq $key) {
        return [ordered]@{ present = $false; kind = $null; encoding = 'none'; data = $null }
    }
    try {
        $present = @($key.GetValueNames()) | Where-Object { $_.Equals($ValueName, [StringComparison]::OrdinalIgnoreCase) }
        if (@($present).Count -eq 0) {
            return [ordered]@{ present = $false; kind = $null; encoding = 'none'; data = $null }
        }
        $kind = $key.GetValueKind($ValueName)
        $value = $key.GetValue(
            $ValueName,
            $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        switch ($kind) {
            ([Microsoft.Win32.RegistryValueKind]::Binary) {
                return [ordered]@{ present = $true; kind = 'Binary'; encoding = 'base64'; data = [Convert]::ToBase64String([byte[]]$value) }
            }
            ([Microsoft.Win32.RegistryValueKind]::MultiString) {
                return [ordered]@{ present = $true; kind = 'MultiString'; encoding = 'string-array'; data = @([string[]]$value) }
            }
            ([Microsoft.Win32.RegistryValueKind]::DWord) {
                return [ordered]@{ present = $true; kind = 'DWord'; encoding = 'integer'; data = [Int64]$value }
            }
            ([Microsoft.Win32.RegistryValueKind]::QWord) {
                return [ordered]@{ present = $true; kind = 'QWord'; encoding = 'integer'; data = [Int64]$value }
            }
            ([Microsoft.Win32.RegistryValueKind]::ExpandString) {
                return [ordered]@{ present = $true; kind = 'ExpandString'; encoding = 'string'; data = [string]$value }
            }
            default {
                return [ordered]@{ present = $true; kind = 'String'; encoding = 'string'; data = [string]$value }
            }
        }
    }
    finally {
        $key.Dispose()
    }
}

function Restore-CloudOSRegistryValueSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RegistrySubKey,
        [Parameter(Mandatory = $true)]$Snapshot,
        [string]$ValueName = $script:RegistryValueName
    )

    if (-not [bool]$Snapshot.present) {
        $key = Open-CloudOSCurrentUserRegistryKey -RegistrySubKey $RegistrySubKey -Writable
        if ($null -eq $key) { return }
        try { $key.DeleteValue($ValueName, $false) }
        finally { $key.Dispose() }
        return
    }

    $kind = [Microsoft.Win32.RegistryValueKind]::String
    if (-not [Enum]::TryParse([Microsoft.Win32.RegistryValueKind], [string]$Snapshot.kind, $true, [ref]$kind)) {
        throw "Unsupported prior registry value kind in V14 snapshot: $($Snapshot.kind)"
    }
    switch ([string]$Snapshot.encoding) {
        'base64' { $value = [Convert]::FromBase64String([string]$Snapshot.data) }
        'string-array' { $value = [string[]]@($Snapshot.data) }
        'integer' {
            if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { $value = [int][Int64]$Snapshot.data }
            else { $value = [Int64]$Snapshot.data }
        }
        default { $value = [string]$Snapshot.data }
    }

    $key = Open-CloudOSCurrentUserRegistryKey -RegistrySubKey $RegistrySubKey -Writable -Create
    try { $key.SetValue($ValueName, $value, $kind) }
    finally { $key.Dispose() }
}

function Test-CloudOSRegistrySnapshotsEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Left,
        [Parameter(Mandatory = $true)]$Right
    )
    return (($Left | ConvertTo-Json -Depth 8 -Compress) -ceq ($Right | ConvertTo-Json -Depth 8 -Compress))
}

function Set-CloudOSShellRegistryCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RegistrySubKey,
        [Parameter(Mandatory = $true)][string]$Command
    )

    $key = Open-CloudOSCurrentUserRegistryKey -RegistrySubKey $RegistrySubKey -Writable -Create
    try { $key.SetValue($script:RegistryValueName, $Command, [Microsoft.Win32.RegistryValueKind]::String) }
    finally { $key.Dispose() }
}

function Get-CloudOSShellCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Paths)

    $windows = [Environment]::GetFolderPath('Windows')
    if ([string]::IsNullOrWhiteSpace($windows)) { throw 'Windows directory is unavailable.' }
    $cmd = Join-Path $windows 'System32\cmd.exe'
    $explorer = Join-Path $windows 'explorer.exe'
    if (-not (Test-Path -LiteralPath $cmd -PathType Leaf) -or -not (Test-Path -LiteralPath $explorer -PathType Leaf)) {
        throw 'Windows cmd.exe or explorer.exe is unavailable; refusing shell activation.'
    }
    return ('"{0}" /d /s /c ""{1}" || start "" "{2}""' -f $cmd, $Paths.EntryCommand, $explorer)
}

function Install-CloudOSShellActivationFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Paths)

    New-Item -ItemType Directory -Path $Paths.ShellDir -Force | Out-Null
    foreach ($name in @(
        'CloudOS.ShellActivation.V14.psm1',
        'CloudOS.Deployment.V13.psm1',
        'CloudOS.ShellEntry.V14.ps1',
        'rollback-cloudos-shell-v14.ps1',
        'repair-cloudos-shell-v14.ps1',
        'get-cloudos-shell-status-v14.ps1'
    )) {
        $source = Join-Path $PSScriptRoot $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Required V14 stable recovery file missing: $source"
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $Paths.ShellDir $name) -Force
    }

    $entry = @'
@echo off
setlocal EnableExtensions
set "SHELLDIR=%~dp0"
for %%I in ("%SHELLDIR%..") do set "INSTALL_ROOT=%%~fI"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SHELLDIR%CloudOS.ShellEntry.V14.ps1" -InstallRoot "%INSTALL_ROOT%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" start "" "%WINDIR%\explorer.exe"
exit /b %RC%
'@
    [IO.File]::WriteAllText($Paths.EntryCommand, $entry, [Text.Encoding]::ASCII)

    $rollback = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%shell-v14\rollback-cloudos-shell-v14.ps1" -InstallRoot "%ROOT%"
exit /b %ERRORLEVEL%
'@
    [IO.File]::WriteAllText((Join-Path $Paths.Root 'Restaurar Explorer.cmd'), $rollback, [Text.Encoding]::ASCII)

    $repair = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%shell-v14\repair-cloudos-shell-v14.ps1" -InstallRoot "%ROOT%"
exit /b %ERRORLEVEL%
'@
    [IO.File]::WriteAllText((Join-Path $Paths.Root 'Reparar Ativacao do Shell.cmd'), $repair, [Text.Encoding]::ASCII)

    $status = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%shell-v14\get-cloudos-shell-status-v14.ps1" -InstallRoot "%ROOT%"
exit /b %ERRORLEVEL%
'@
    [IO.File]::WriteAllText((Join-Path $Paths.Root 'Status do Shell CloudOS.cmd'), $status, [Text.Encoding]::ASCII)
}

function Get-CloudOSShellActivationStatus {
    [CmdletBinding()]
    param(
        [string]$InstallRoot,
        [string]$RegistrySubKey,
        [switch]$AllowTestRegistryOverride
    )

    $paths = Get-CloudOSShellActivationPaths -InstallRoot $InstallRoot
    $state = Read-CloudOSShellJson -Path $paths.ActivationState
    if ($null -ne $state) { Assert-CloudOSShellState -State $state }

    if ([string]::IsNullOrWhiteSpace($RegistrySubKey)) {
        if ($null -ne $state -and -not [string]::IsNullOrWhiteSpace([string]$state.registry_subkey)) {
            $RegistrySubKey = [string]$state.registry_subkey
        }
        else {
            $RegistrySubKey = $script:DefaultRegistrySubKey
        }
    }
    Assert-CloudOSRegistryScope -RegistrySubKey $RegistrySubKey -AllowTestRegistryOverride:$AllowTestRegistryOverride
    $current = Get-CloudOSRegistryValueSnapshot -RegistrySubKey $RegistrySubKey
    $desiredSnapshot = $null
    $matches = $false
    if ($null -ne $state -and -not [string]::IsNullOrWhiteSpace([string]$state.desired_command)) {
        $desiredSnapshot = [ordered]@{ present = $true; kind = 'String'; encoding = 'string'; data = [string]$state.desired_command }
        $matches = Test-CloudOSRegistrySnapshotsEqual -Left $current -Right $desiredSnapshot
    }

    return [pscustomobject]@{
        schema = $script:ActivationSchema
        product = $script:ProductName
        provider = $script:ProviderName
        install_root = $paths.Root
        registry_subkey = $RegistrySubKey
        state_present = ($null -ne $state)
        activated = ($null -ne $state -and [bool]$state.active)
        registry_matches = $matches
        journal_present = Test-Path -LiteralPath $paths.ActivationJournal
        rollback_available = ($null -ne $state -and $null -ne $state.previous_value)
        current_value = $current
        desired_command = if ($null -ne $state) { [string]$state.desired_command } else { $null }
        status = if ($null -ne $state) { [string]$state.status } else { 'not-managed' }
    }
}

function Invoke-CloudOSShellActivation {
    [CmdletBinding()]
    param(
        [string]$InstallRoot,
        [string]$RegistrySubKey = $script:DefaultRegistrySubKey,
        [switch]$AllowTestRegistryOverride,
        [switch]$ProbeInterruptAfterRegistryWrite
    )

    Assert-CloudOSRegistryScope -RegistrySubKey $RegistrySubKey -AllowTestRegistryOverride:$AllowTestRegistryOverride
    if ($ProbeInterruptAfterRegistryWrite -and $RegistrySubKey.Equals($script:DefaultRegistrySubKey, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The interruption probe is forbidden against the production Winlogon key.'
    }

    $paths = Get-CloudOSShellActivationPaths -InstallRoot $InstallRoot
    New-Item -ItemType Directory -Path $paths.StateDir -Force | Out-Null
    Import-CloudOSDeploymentV13
    $deploymentStatus = Get-CloudOSDeploymentStatus -InstallRoot $paths.Root
    if (-not $deploymentStatus.installed -or -not $deploymentStatus.active_valid) {
        throw 'CloudOS V14 activation requires a valid V13 managed deployment with a verified active version.'
    }
    $activeRoot = Join-Path $paths.Versions ([string]$deploymentStatus.active_version)
    [void](Test-CloudOSPayload -PackageRoot $activeRoot)

    Install-CloudOSShellActivationFiles -Paths $paths
    $desired = Get-CloudOSShellCommand -Paths $paths
    $desiredSnapshot = [ordered]@{ present = $true; kind = 'String'; encoding = 'string'; data = $desired }

    $existing = Read-CloudOSShellJson -Path $paths.ActivationState
    if ($null -ne $existing) {
        Assert-CloudOSShellState -State $existing
        if ([bool]$existing.active) {
            if (-not ([string]$existing.registry_subkey).Equals($RegistrySubKey, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'CloudOS V14 is already active against a different registry subkey. Roll it back first.'
            }
            $currentExisting = Get-CloudOSRegistryValueSnapshot -RegistrySubKey $RegistrySubKey
            if (-not (Test-CloudOSRegistrySnapshotsEqual -Left $currentExisting -Right $desiredSnapshot)) {
                throw 'CloudOS V14 activation state is active but the Shell value drifted. Use status/repair/rollback instead of overwriting another change.'
            }
            return Get-CloudOSShellActivationStatus -InstallRoot $paths.Root -RegistrySubKey $RegistrySubKey -AllowTestRegistryOverride:$AllowTestRegistryOverride
        }
    }

    if (Test-Path -LiteralPath $paths.ActivationJournal) {
        throw 'An unfinished CloudOS V14 shell activation journal exists. Run repair before activating again.'
    }

    $previous = Get-CloudOSRegistryValueSnapshot -RegistrySubKey $RegistrySubKey
    $journal = [ordered]@{
        schema = $script:ActivationSchema
        product = $script:ProductName
        operation = 'activate'
        phase = 'prepared'
        install_root = $paths.Root
        registry_subkey = $RegistrySubKey
        value_name = $script:RegistryValueName
        previous_value = $previous
        desired_command = $desired
        updated_utc = [DateTime]::UtcNow.ToString('o')
    }
    Write-CloudOSShellJsonAtomic -Path $paths.ActivationJournal -Value $journal

    Set-CloudOSShellRegistryCommand -RegistrySubKey $RegistrySubKey -Command $desired
    $journal.phase = 'registry-written'
    $journal.updated_utc = [DateTime]::UtcNow.ToString('o')
    Write-CloudOSShellJsonAtomic -Path $paths.ActivationJournal -Value $journal

    $readBack = Get-CloudOSRegistryValueSnapshot -RegistrySubKey $RegistrySubKey
    if (-not (Test-CloudOSRegistrySnapshotsEqual -Left $readBack -Right $desiredSnapshot)) {
        Restore-CloudOSRegistryValueSnapshot -RegistrySubKey $RegistrySubKey -Snapshot $previous
        throw 'CloudOS V14 Shell value failed read-back validation; the prior value was restored.'
    }

    if ($ProbeInterruptAfterRegistryWrite) {
        throw 'V14 deterministic interruption probe after registry write.'
    }

    $state = [ordered]@{
        schema = $script:ActivationSchema
        product = $script:ProductName
        provider = $script:ProviderName
        status = 'active'
        active = $true
        install_root = $paths.Root
        registry_subkey = $RegistrySubKey
        value_name = $script:RegistryValueName
        previous_value = $previous
        desired_command = $desired
        active_version_at_activation = [string]$deploymentStatus.active_version
        shell_entry = $paths.EntryCommand
        activated_utc = [DateTime]::UtcNow.ToString('o')
        updated_utc = [DateTime]::UtcNow.ToString('o')
    }
    Write-CloudOSShellJsonAtomic -Path $paths.ActivationState -Value $state
    Remove-Item -LiteralPath $paths.ActivationJournal -Force

    return Get-CloudOSShellActivationStatus -InstallRoot $paths.Root -RegistrySubKey $RegistrySubKey -AllowTestRegistryOverride:$AllowTestRegistryOverride
}

function Invoke-CloudOSShellRollback {
    [CmdletBinding()]
    param(
        [string]$InstallRoot,
        [string]$RegistrySubKey,
        [switch]$AllowTestRegistryOverride,
        [switch]$ForceRestoreSnapshot
    )

    $paths = Get-CloudOSShellActivationPaths -InstallRoot $InstallRoot
    if (Test-Path -LiteralPath $paths.ActivationJournal) {
        throw 'CloudOS V14 has an unfinished activation journal. Run repair before rollback.'
    }
    $state = Read-CloudOSShellJson -Path $paths.ActivationState
    if ($null -eq $state) { throw 'CloudOS V14 rollback requires a managed activation state.' }
    Assert-CloudOSShellState -State $state

    if ([string]::IsNullOrWhiteSpace($RegistrySubKey)) { $RegistrySubKey = [string]$state.registry_subkey }
    Assert-CloudOSRegistryScope -RegistrySubKey $RegistrySubKey -AllowTestRegistryOverride:$AllowTestRegistryOverride
    if (-not ([string]$state.registry_subkey).Equals($RegistrySubKey, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Requested registry subkey does not match the V14 activation state.'
    }

    if (-not [bool]$state.active) {
        return Get-CloudOSShellActivationStatus -InstallRoot $paths.Root -RegistrySubKey $RegistrySubKey -AllowTestRegistryOverride:$AllowTestRegistryOverride
    }

    $current = Get-CloudOSRegistryValueSnapshot -RegistrySubKey $RegistrySubKey
    $desired = [ordered]@{ present = $true; kind = 'String'; encoding = 'string'; data = [string]$state.desired_command }
    if (-not $ForceRestoreSnapshot -and -not (Test-CloudOSRegistrySnapshotsEqual -Left $current -Right $desired)) {
        throw 'Current Shell value no longer matches the CloudOS-managed value. Refusing to overwrite an external change; use -ForceRestoreSnapshot only after inspecting status.'
    }

    $journal = [ordered]@{
        schema = $script:ActivationSchema
        product = $script:ProductName
        operation = 'rollback'
        phase = 'restoring-previous'
        install_root = $paths.Root
        registry_subkey = $RegistrySubKey
        value_name = $script:RegistryValueName
        previous_value = $state.previous_value
        desired_command = [string]$state.desired_command
        updated_utc = [DateTime]::UtcNow.ToString('o')
    }
    Write-CloudOSShellJsonAtomic -Path $paths.ActivationJournal -Value $journal
    Restore-CloudOSRegistryValueSnapshot -RegistrySubKey $RegistrySubKey -Snapshot $state.previous_value
    $restored = Get-CloudOSRegistryValueSnapshot -RegistrySubKey $RegistrySubKey
    if (-not (Test-CloudOSRegistrySnapshotsEqual -Left $restored -Right $state.previous_value)) {
        throw 'CloudOS V14 rollback could not verify restoration of the exact previous Shell value.'
    }

    $state.active = $false
    $state.status = 'rolled-back'
    $state.rolled_back_utc = [DateTime]::UtcNow.ToString('o')
    $state.updated_utc = [DateTime]::UtcNow.ToString('o')
    Write-CloudOSShellJsonAtomic -Path $paths.ActivationState -Value $state
    Remove-Item -LiteralPath $paths.ActivationJournal -Force

    return Get-CloudOSShellActivationStatus -InstallRoot $paths.Root -RegistrySubKey $RegistrySubKey -AllowTestRegistryOverride:$AllowTestRegistryOverride
}

function Invoke-CloudOSShellRepair {
    [CmdletBinding()]
    param(
        [string]$InstallRoot,
        [switch]$AllowTestRegistryOverride
    )

    $paths = Get-CloudOSShellActivationPaths -InstallRoot $InstallRoot
    $journal = Read-CloudOSShellJson -Path $paths.ActivationJournal
    if ($null -ne $journal) {
        if ([int]$journal.schema -ne $script:ActivationSchema -or [string]$journal.product -ne $script:ProductName) {
            throw 'Unknown shell activation journal found; refusing repair.'
        }
        $subKey = [string]$journal.registry_subkey
        Assert-CloudOSRegistryScope -RegistrySubKey $subKey -AllowTestRegistryOverride:$AllowTestRegistryOverride
        Restore-CloudOSRegistryValueSnapshot -RegistrySubKey $subKey -Snapshot $journal.previous_value
        $restored = Get-CloudOSRegistryValueSnapshot -RegistrySubKey $subKey
        if (-not (Test-CloudOSRegistrySnapshotsEqual -Left $restored -Right $journal.previous_value)) {
            throw 'V14 repair could not verify restoration of the pre-transaction Shell value.'
        }
        Remove-Item -LiteralPath $paths.ActivationJournal -Force
        $state = Read-CloudOSShellJson -Path $paths.ActivationState
        if ($null -ne $state) {
            Assert-CloudOSShellState -State $state
            $state.active = $false
            $state.status = 'repaired-to-previous'
            $state.updated_utc = [DateTime]::UtcNow.ToString('o')
            Write-CloudOSShellJsonAtomic -Path $paths.ActivationState -Value $state
        }
        return [pscustomobject]@{ repaired = $true; action = 'restored-pre-transaction'; registry_subkey = $subKey }
    }

    $state = Read-CloudOSShellJson -Path $paths.ActivationState
    if ($null -eq $state) {
        return [pscustomobject]@{ repaired = $true; action = 'no-managed-state'; registry_subkey = $null }
    }
    Assert-CloudOSShellState -State $state
    $subKey = [string]$state.registry_subkey
    Assert-CloudOSRegistryScope -RegistrySubKey $subKey -AllowTestRegistryOverride:$AllowTestRegistryOverride
    if (-not [bool]$state.active) {
        return [pscustomobject]@{ repaired = $true; action = 'inactive'; registry_subkey = $subKey }
    }

    $current = Get-CloudOSRegistryValueSnapshot -RegistrySubKey $subKey
    $desired = [ordered]@{ present = $true; kind = 'String'; encoding = 'string'; data = [string]$state.desired_command }
    if (Test-CloudOSRegistrySnapshotsEqual -Left $current -Right $desired) {
        return [pscustomobject]@{ repaired = $true; action = 'healthy'; registry_subkey = $subKey }
    }
    return [pscustomobject]@{
        repaired = $false
        action = 'drift-detected-no-write'
        registry_subkey = $subKey
        message = 'Shell value changed outside CloudOS. V14 does not overwrite external changes during repair.'
    }
}

Export-ModuleMember -Function @(
    'Get-CloudOSShellActivationPaths',
    'Get-CloudOSShellActivationStatus',
    'Invoke-CloudOSShellActivation',
    'Invoke-CloudOSShellRollback',
    'Invoke-CloudOSShellRepair'
)
