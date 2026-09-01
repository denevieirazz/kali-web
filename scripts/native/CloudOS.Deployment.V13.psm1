Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:DeploymentSchema = 13
$script:ProductName = 'CloudOS Native Shell'
$script:RecoveryAuthority = 'CloudOS.Supervisor.exe V11'
$script:BrokerAuthority = 'CloudOS.SystemBroker.exe V21'
$script:RequiredPayloadFiles = @(
    'CloudOS.exe',
    'CloudOS.NativeRuntime.dll',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe'
)

function Get-CloudOSDefaultInstallRoot {
    [CmdletBinding()]
    param()
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is unavailable; specify -InstallRoot explicitly.'
    }
    return [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'CloudOS\NativeShell'))
}

function Resolve-CloudOSInstallRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InstallRoot)

    $full = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $root = [System.IO.Path]::GetPathRoot($full).TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($full) -or $full -eq $root) {
        throw "Unsafe CloudOS install root: $InstallRoot"
    }

    $windows = [Environment]::GetFolderPath('Windows')
    if (-not [string]::IsNullOrWhiteSpace($windows)) {
        $windowsFull = [System.IO.Path]::GetFullPath($windows).TrimEnd('\')
        if ($full.Equals($windowsFull, [StringComparison]::OrdinalIgnoreCase) -or
            $windowsFull.StartsWith($full + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "CloudOS install root cannot own the Windows directory: $full"
        }
    }
    return $full
}

function Get-CloudOSDeploymentPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InstallRoot)

    $root = Resolve-CloudOSInstallRoot -InstallRoot $InstallRoot
    $stateDir = Join-Path $root 'state'
    return [ordered]@{
        Root = $root
        Versions = Join-Path $root 'versions'
        Staging = Join-Path $root 'staging'
        StateDir = $stateDir
        State = Join-Path $stateDir 'deployment-v13.json'
        Journal = Join-Path $stateDir 'deployment-v13.journal.json'
        Lock = Join-Path $stateDir 'deployment-v13.lock'
        Tools = Join-Path $root 'tools'
    }
}

function New-CloudOSDirectoryLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Paths)

    foreach ($path in @($Paths.Root, $Paths.Versions, $Paths.Staging, $Paths.StateDir, $Paths.Tools)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

function Enter-CloudOSDeploymentLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [int]$TimeoutSeconds = 15
    )

    New-Item -ItemType Directory -Path $Paths.StateDir -Force | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(1, $TimeoutSeconds))
    while ($true) {
        try {
            return [System.IO.File]::Open(
                $Paths.Lock,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None)
        }
        catch [System.IO.IOException] {
            if ([DateTime]::UtcNow -ge $deadline) {
                throw "Timed out waiting for the CloudOS V13 deployment lock: $($Paths.Lock)"
            }
            Start-Sleep -Milliseconds 150
        }
    }
}

function Write-CloudOSJsonAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $json = $Value | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-CloudOSJson {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function New-CloudOSDeploymentState {
    [CmdletBinding()]
    param()
    return [ordered]@{
        schema = $script:DeploymentSchema
        product = $script:ProductName
        status = 'empty'
        active_version = $null
        last_known_good = $null
        installed_versions = @()
        updated_utc = [DateTime]::UtcNow.ToString('o')
    }
}

function Assert-CloudOSState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$State)

    if ([int]$State.schema -ne $script:DeploymentSchema -or
        [string]$State.product -ne $script:ProductName) {
        throw 'CloudOS deployment state is not a V13 managed state.'
    }
}

function Get-CloudOSPayloadIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PackageRoot)

    $root = (Resolve-Path -LiteralPath $PackageRoot).Path
    $manifestPath = Join-Path $root 'cloudos-native-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "CloudOS package manifest missing: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([int]$manifest.schema -ne 1 -or
        [string]$manifest.product -ne $script:ProductName -or
        [string]$manifest.shell_authority -ne 'C++/Win32' -or
        [string]$manifest.recovery_authority -ne $script:RecoveryAuthority -or
        [string]$manifest.broker_authority -ne $script:BrokerAuthority -or
        [string]$manifest.configuration -ne 'Release' -or
        [string]$manifest.platform -ne 'x64' -or
        $manifest.legacy_react_desktop -ne $false) {
        throw 'CloudOS package manifest failed V13 authority validation.'
    }

    $fingerprint = ([string]$manifest.source_fingerprint_sha256).ToLowerInvariant()
    if ($fingerprint -notmatch '^[0-9a-f]{64}$') {
        throw 'CloudOS package source fingerprint is invalid.'
    }

    $gitHead = ([string]$manifest.git_head).ToLowerInvariant()
    if ($gitHead -notmatch '^[0-9a-f]{40}$') {
        throw 'CloudOS package git_head must be an exact 40-character commit SHA.'
    }

    foreach ($name in $script:RequiredPayloadFiles) {
        $record = @($manifest.files | Where-Object { [string]$_.name -eq $name })
        if ($record.Count -ne 1) {
            throw "CloudOS package must contain exactly one manifest record for $name."
        }
        $path = Join-Path $root $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "CloudOS package payload missing: $name"
        }
        $item = Get-Item -LiteralPath $path
        if ($item.Length -le 0 -or [Int64]$record[0].size -ne [Int64]$item.Length) {
            throw "CloudOS package size mismatch: $name"
        }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne ([string]$record[0].sha256).ToLowerInvariant()) {
            throw "CloudOS package SHA256 mismatch: $name"
        }
    }

    if (Test-Path -LiteralPath (Join-Path $root 'ui')) {
        throw 'Legacy web desktop payload is forbidden in a V13 deployment.'
    }

    $version = 'g' + $gitHead.Substring(0, 12) + '-f' + $fingerprint.Substring(0, 12)
    return [pscustomobject]@{
        Root = $root
        Manifest = $manifest
        GitHead = $gitHead
        Fingerprint = $fingerprint
        Version = $version
    }
}

function Test-CloudOSPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [switch]$SkipSupervisorSelfTest
    )

    $identity = Get-CloudOSPayloadIdentity -PackageRoot $PackageRoot
    if (-not $SkipSupervisorSelfTest) {
        $supervisor = Join-Path $identity.Root 'CloudOS.Supervisor.exe'
        $process = Start-Process -FilePath $supervisor -ArgumentList '--self-test' -WorkingDirectory $identity.Root -PassThru -Wait -WindowStyle Hidden
        if ($process.ExitCode -ne 0) {
            throw "CloudOS Supervisor V11 self-test failed with exit code $($process.ExitCode)."
        }
    }
    return $identity
}

function Copy-CloudOSPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    if (Test-Path -LiteralPath $DestinationRoot) {
        Remove-Item -LiteralPath $DestinationRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $SourceRoot -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $DestinationRoot -Recurse -Force
    }
}

function Write-CloudOSJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$Phase,
        [string]$TargetVersion,
        [string]$PreviousActive,
        [string]$StagingPath
    )

    $journal = [ordered]@{
        schema = $script:DeploymentSchema
        product = $script:ProductName
        operation = $Operation
        phase = $Phase
        target_version = $TargetVersion
        previous_active = $PreviousActive
        staging_path = $StagingPath
        updated_utc = [DateTime]::UtcNow.ToString('o')
    }
    Write-CloudOSJsonAtomic -Path $Paths.Journal -Value $journal
}

function Remove-CloudOSJournal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Paths)
    if (Test-Path -LiteralPath $Paths.Journal) {
        Remove-Item -LiteralPath $Paths.Journal -Force
    }
}

function Get-CloudOSInstalledVersions {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Paths)

    if (-not (Test-Path -LiteralPath $Paths.Versions -PathType Container)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $Paths.Versions -Directory -Force |
        Sort-Object Name |
        ForEach-Object { $_.Name })
}

function Save-CloudOSState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)]$State
    )
    $State.installed_versions = @(Get-CloudOSInstalledVersions -Paths $Paths)
    $State.updated_utc = [DateTime]::UtcNow.ToString('o')
    Write-CloudOSJsonAtomic -Path $Paths.State -Value $State
}

function Install-CloudOSStableTools {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Paths)

    $source = $PSScriptRoot
    New-Item -ItemType Directory -Path $Paths.Tools -Force | Out-Null
    foreach ($name in @(
        'CloudOS.Deployment.V13.psm1',
        'start-cloudos-installed-v13.ps1',
        'rollback-cloudos-native-v13.ps1',
        'repair-cloudos-native-v13.ps1',
        'get-cloudos-deployment-status-v13.ps1'
    )) {
        $path = Join-Path $source $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "CloudOS V13 deployment tool missing beside module: $path"
        }
        Copy-Item -LiteralPath $path -Destination (Join-Path $Paths.Tools $name) -Force
    }

    $launch = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\start-cloudos-installed-v13.ps1" -InstallRoot "%ROOT%"
exit /b %ERRORLEVEL%
'@
    [IO.File]::WriteAllText((Join-Path $Paths.Root 'Iniciar CloudOS.cmd'), $launch, [Text.Encoding]::ASCII)

    $recovery = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\start-cloudos-installed-v13.ps1" -InstallRoot "%ROOT%" -Recovery
exit /b %ERRORLEVEL%
'@
    [IO.File]::WriteAllText((Join-Path $Paths.Root 'Recuperacao CloudOS.cmd'), $recovery, [Text.Encoding]::ASCII)

    $rollback = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\rollback-cloudos-native-v13.ps1" -InstallRoot "%ROOT%"
exit /b %ERRORLEVEL%
'@
    [IO.File]::WriteAllText((Join-Path $Paths.Root 'Rollback CloudOS.cmd'), $rollback, [Text.Encoding]::ASCII)
}

function Remove-CloudOSOldVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)]$State,
        [int]$RetainVersions = 2
    )

    $retain = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$State.active_version)) {
        $retain += [string]$State.active_version
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$State.last_known_good)) {
        $retain += [string]$State.last_known_good
    }

    $dirs = @(Get-ChildItem -LiteralPath $Paths.Versions -Directory -Force |
        Sort-Object LastWriteTimeUtc -Descending)
    foreach ($dir in $dirs) {
        if ($retain -contains $dir.Name) {
            continue
        }
        if ($retain.Count -lt [Math]::Max(2, $RetainVersions)) {
            $retain += $dir.Name
            continue
        }
        Remove-Item -LiteralPath $dir.FullName -Recurse -Force
    }
}

function Invoke-CloudOSDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourcePackageRoot,
        [string]$InstallRoot = (Get-CloudOSDefaultInstallRoot),
        [int]$RetainVersions = 2
    )

    $paths = Get-CloudOSDeploymentPaths -InstallRoot $InstallRoot
    New-CloudOSDirectoryLayout -Paths $paths
    $lock = Enter-CloudOSDeploymentLock -Paths $paths
    try {
        Invoke-CloudOSRepair -InstallRoot $paths.Root -LockAlreadyHeld | Out-Null

        # Source validation occurs before any active-state mutation.
        $sourceIdentity = Test-CloudOSPayload -PackageRoot $SourcePackageRoot -SkipSupervisorSelfTest
        $state = Read-CloudOSJson -Path $paths.State
        if ($null -eq $state) {
            $state = New-CloudOSDeploymentState
        }
        else {
            Assert-CloudOSState -State $state
        }

        $previousActive = [string]$state.active_version
        $targetVersion = $sourceIdentity.Version
        $targetPath = Join-Path $paths.Versions $targetVersion

        if (Test-Path -LiteralPath $targetPath -PathType Container) {
            $existingIdentity = Test-CloudOSPayload -PackageRoot $targetPath
            if ($existingIdentity.Version -ne $targetVersion) {
                throw "Existing immutable CloudOS version directory is inconsistent: $targetPath"
            }
        }
        else {
            $transaction = [Guid]::NewGuid().ToString('N')
            $stagingPath = Join-Path $paths.Staging $transaction
            Write-CloudOSJournal -Paths $paths -Operation 'deploy' -Phase 'copying' `
                -TargetVersion $targetVersion -PreviousActive $previousActive -StagingPath $stagingPath
            Copy-CloudOSPackage -SourceRoot $sourceIdentity.Root -DestinationRoot $stagingPath

            Write-CloudOSJournal -Paths $paths -Operation 'deploy' -Phase 'verifying' `
                -TargetVersion $targetVersion -PreviousActive $previousActive -StagingPath $stagingPath
            $stagedIdentity = Test-CloudOSPayload -PackageRoot $stagingPath
            if ($stagedIdentity.Version -ne $targetVersion) {
                throw 'Staged CloudOS identity changed during deployment.'
            }

            Write-CloudOSJournal -Paths $paths -Operation 'deploy' -Phase 'publishing' `
                -TargetVersion $targetVersion -PreviousActive $previousActive -StagingPath $stagingPath
            Move-Item -LiteralPath $stagingPath -Destination $targetPath
        }

        Install-CloudOSStableTools -Paths $paths

        if ($previousActive -ne $targetVersion) {
            if (-not [string]::IsNullOrWhiteSpace($previousActive)) {
                $state.last_known_good = $previousActive
            }
            $state.active_version = $targetVersion
        }
        $state.status = 'ready'

        Write-CloudOSJournal -Paths $paths -Operation 'deploy' -Phase 'activating' `
            -TargetVersion $targetVersion -PreviousActive $previousActive -StagingPath $null
        Save-CloudOSState -Paths $paths -State $state
        Remove-CloudOSOldVersions -Paths $paths -State $state -RetainVersions $RetainVersions
        Save-CloudOSState -Paths $paths -State $state
        Remove-CloudOSJournal -Paths $paths

        return Get-CloudOSDeploymentStatus -InstallRoot $paths.Root
    }
    finally {
        if ($null -ne $lock) {
            $lock.Dispose()
        }
    }
}

function Invoke-CloudOSRollback {
    [CmdletBinding()]
    param(
        [string]$InstallRoot = (Get-CloudOSDefaultInstallRoot),
        [switch]$LockAlreadyHeld
    )

    $paths = Get-CloudOSDeploymentPaths -InstallRoot $InstallRoot
    if (-not (Test-Path -LiteralPath $paths.State -PathType Leaf)) {
        throw 'CloudOS V13 rollback requires an existing managed deployment state.'
    }
    $lock = $null
    if (-not $LockAlreadyHeld) {
        $lock = Enter-CloudOSDeploymentLock -Paths $paths
    }
    try {
        $state = Read-CloudOSJson -Path $paths.State
        Assert-CloudOSState -State $state
        $target = [string]$state.last_known_good
        if ([string]::IsNullOrWhiteSpace($target)) {
            throw 'CloudOS V13 has no last-known-good version to roll back to.'
        }
        $targetPath = Join-Path $paths.Versions $target
        [void](Test-CloudOSPayload -PackageRoot $targetPath)

        $oldActive = [string]$state.active_version
        Write-CloudOSJournal -Paths $paths -Operation 'rollback' -Phase 'activating' `
            -TargetVersion $target -PreviousActive $oldActive -StagingPath $null
        $state.active_version = $target
        $state.last_known_good = $oldActive
        $state.status = 'ready'
        Save-CloudOSState -Paths $paths -State $state
        Remove-CloudOSJournal -Paths $paths
        return Get-CloudOSDeploymentStatus -InstallRoot $paths.Root
    }
    finally {
        if ($null -ne $lock) {
            $lock.Dispose()
        }
    }
}

function Invoke-CloudOSRepair {
    [CmdletBinding()]
    param(
        [string]$InstallRoot = (Get-CloudOSDefaultInstallRoot),
        [switch]$LockAlreadyHeld
    )

    $paths = Get-CloudOSDeploymentPaths -InstallRoot $InstallRoot
    New-CloudOSDirectoryLayout -Paths $paths
    $lock = $null
    if (-not $LockAlreadyHeld) {
        $lock = Enter-CloudOSDeploymentLock -Paths $paths
    }
    try {
        $journal = Read-CloudOSJson -Path $paths.Journal
        if ($null -ne $journal) {
            if ([int]$journal.schema -ne $script:DeploymentSchema -or
                [string]$journal.product -ne $script:ProductName) {
                throw 'Unknown deployment journal found; refusing destructive repair.'
            }
            $staging = [string]$journal.staging_path
            if (-not [string]::IsNullOrWhiteSpace($staging)) {
                $stagingFull = [IO.Path]::GetFullPath($staging)
                $stagingRoot = [IO.Path]::GetFullPath($paths.Staging).TrimEnd('\') + '\'
                if ($stagingFull.StartsWith($stagingRoot, [StringComparison]::OrdinalIgnoreCase) -and
                    (Test-Path -LiteralPath $stagingFull)) {
                    Remove-Item -LiteralPath $stagingFull -Recurse -Force
                }
            }
        }

        $state = Read-CloudOSJson -Path $paths.State
        if ($null -eq $state) {
            Remove-CloudOSJournal -Paths $paths
            return [pscustomobject]@{ repaired = $true; action = 'empty'; active_version = $null }
        }
        Assert-CloudOSState -State $state

        $active = [string]$state.active_version
        $activeValid = $false
        if (-not [string]::IsNullOrWhiteSpace($active)) {
            try {
                [void](Test-CloudOSPayload -PackageRoot (Join-Path $paths.Versions $active) -SkipSupervisorSelfTest)
                $activeValid = $true
            }
            catch {
                $activeValid = $false
            }
        }

        if (-not $activeValid) {
            $fallback = [string]$state.last_known_good
            if ([string]::IsNullOrWhiteSpace($fallback)) {
                throw 'Active CloudOS version is invalid and no last-known-good version is available.'
            }
            [void](Test-CloudOSPayload -PackageRoot (Join-Path $paths.Versions $fallback))
            $state.active_version = $fallback
            $state.last_known_good = $active
            $state.status = 'repaired'
            Save-CloudOSState -Paths $paths -State $state
        }

        Remove-CloudOSJournal -Paths $paths
        $action = 'journal-cleanup'
        if (-not $activeValid) { $action = 'fallback' }
        return [pscustomobject]@{
            repaired = $true
            action = $action
            active_version = [string]$state.active_version
        }
    }
    finally {
        if ($null -ne $lock) {
            $lock.Dispose()
        }
    }
}

function Get-CloudOSDeploymentStatus {
    [CmdletBinding()]
    param([string]$InstallRoot = (Get-CloudOSDefaultInstallRoot))

    $paths = Get-CloudOSDeploymentPaths -InstallRoot $InstallRoot
    $state = Read-CloudOSJson -Path $paths.State
    if ($null -eq $state) {
        return [pscustomobject]@{
            schema = $script:DeploymentSchema
            product = $script:ProductName
            installed = $false
            install_root = $paths.Root
            active_version = $null
            last_known_good = $null
            active_valid = $false
            journal_present = Test-Path -LiteralPath $paths.Journal
            installed_versions = @()
        }
    }

    Assert-CloudOSState -State $state
    $activeValid = $false
    $active = [string]$state.active_version
    if (-not [string]::IsNullOrWhiteSpace($active)) {
        try {
            [void](Test-CloudOSPayload -PackageRoot (Join-Path $paths.Versions $active) -SkipSupervisorSelfTest)
            $activeValid = $true
        }
        catch {
            $activeValid = $false
        }
    }

    return [pscustomobject]@{
        schema = $script:DeploymentSchema
        product = $script:ProductName
        installed = $true
        install_root = $paths.Root
        active_version = $active
        last_known_good = [string]$state.last_known_good
        active_valid = $activeValid
        journal_present = Test-Path -LiteralPath $paths.Journal
        installed_versions = @(Get-CloudOSInstalledVersions -Paths $paths)
    }
}

function Start-CloudOSInstalled {
    [CmdletBinding()]
    param(
        [string]$InstallRoot = (Get-CloudOSDefaultInstallRoot),
        [switch]$Recovery
    )

    $paths = Get-CloudOSDeploymentPaths -InstallRoot $InstallRoot
    $state = Read-CloudOSJson -Path $paths.State
    if ($null -eq $state) {
        throw 'CloudOS V13 is not installed.'
    }
    Assert-CloudOSState -State $state
    $active = [string]$state.active_version
    if ([string]::IsNullOrWhiteSpace($active)) {
        throw 'CloudOS V13 deployment has no active version.'
    }
    $activeRoot = Join-Path $paths.Versions $active
    [void](Test-CloudOSPayload -PackageRoot $activeRoot -SkipSupervisorSelfTest)
    $supervisor = Join-Path $activeRoot 'CloudOS.Supervisor.exe'
    $args = @()
    if ($Recovery) {
        $args = @('--recovery-ui')
    }
    Start-Process -FilePath $supervisor -ArgumentList $args -WorkingDirectory $activeRoot | Out-Null
}

function Assert-CloudOSManagedInstallRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Paths)

    if (-not (Test-Path -LiteralPath $Paths.State -PathType Leaf)) {
        throw 'Refusing to remove an install root that has no CloudOS V13 managed state.'
    }
    $state = Read-CloudOSJson -Path $Paths.State
    Assert-CloudOSState -State $state
}

function Invoke-CloudOSUninstall {
    [CmdletBinding()]
    param([string]$InstallRoot = (Get-CloudOSDefaultInstallRoot))

    $paths = Get-CloudOSDeploymentPaths -InstallRoot $InstallRoot
    Assert-CloudOSManagedInstallRoot -Paths $paths
    $lock = Enter-CloudOSDeploymentLock -Paths $paths
    try {
        foreach ($name in @('CloudOS', 'CloudOS.Supervisor', 'CloudOS.SystemBroker', 'CloudOS.BrokerProbe')) {
            foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
                try { $path = $process.Path } catch { continue }
                if (-not [string]::IsNullOrWhiteSpace($path) -and
                    [IO.Path]::GetFullPath($path).StartsWith($paths.Root + '\', [StringComparison]::OrdinalIgnoreCase)) {
                    throw "CloudOS is still running from the managed install root (PID $($process.Id)). Close it before uninstall."
                }
            }
        }
        $lock.Dispose()
        $lock = $null
        Remove-Item -LiteralPath $paths.Root -Recurse -Force
        return [pscustomobject]@{ uninstalled = $true; install_root = $paths.Root }
    }
    finally {
        if ($null -ne $lock) {
            $lock.Dispose()
        }
    }
}

Export-ModuleMember -Function @(
    'Get-CloudOSDefaultInstallRoot',
    'Get-CloudOSDeploymentPaths',
    'Get-CloudOSPayloadIdentity',
    'Test-CloudOSPayload',
    'Invoke-CloudOSDeployment',
    'Invoke-CloudOSRollback',
    'Invoke-CloudOSRepair',
    'Get-CloudOSDeploymentStatus',
    'Start-CloudOSInstalled',
    'Invoke-CloudOSUninstall'
)
