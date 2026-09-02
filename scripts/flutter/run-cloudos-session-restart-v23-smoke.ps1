param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory,
    [string]$EvidencePath = 'TestResults/v23-session-restart/session-restart-v23-smoke.json',
    [int]$ExitTimeoutSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Wait-CloudOSMainWindow {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds = 15
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($Process.HasExited) {
            throw "CloudOS exited before creating a main window. ExitCode=$($Process.ExitCode)"
        }
        $Process.Refresh()
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
            return $Process.MainWindowHandle
        }
        Start-Sleep -Milliseconds 100
    }
    throw "CloudOS did not expose a main window within ${TimeoutSeconds}s."
}

function Invoke-CloudOSCloseCycle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,
        [int]$Cycle,
        [int]$TimeoutSeconds
    )

    $startedAt = [DateTime]::UtcNow
    $process = Start-Process -FilePath $Executable -WorkingDirectory $WorkingDirectory -PassThru
    try {
        $null = Wait-CloudOSMainWindow -Process $process -TimeoutSeconds $TimeoutSeconds
        # Give the first Flutter frame, session restore and geometry clamp enough
        # time to execute before exercising the native close path.
        Start-Sleep -Milliseconds 1500
        $process.Refresh()
        $closeRequested = $process.CloseMainWindow()
        if (-not $closeRequested) {
            throw "Cycle $Cycle could not send WM_CLOSE through CloseMainWindow()."
        }
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill($true) } catch {}
            throw "Cycle $Cycle did not exit within ${TimeoutSeconds}s after WM_CLOSE."
        }
        return [ordered]@{
            cycle = $Cycle
            pid = $process.Id
            close_requested = $closeRequested
            exit_code = $process.ExitCode
            duration_ms = [int]([DateTime]::UtcNow - $startedAt).TotalMilliseconds
        }
    }
    finally {
        if (-not $process.HasExited) {
            try { $process.Kill($true) } catch {}
        }
        $process.Dispose()
    }
}

$release = (Resolve-Path $ReleaseDirectory).Path
$exe = Join-Path $release 'cloudos_flutter_shell.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "CloudOS release executable missing: $exe"
}

$repoRoot = (Resolve-Path '.').Path
$evidenceFull = [IO.Path]::GetFullPath((Join-Path $repoRoot $EvidencePath))
$evidenceDirectory = Split-Path -Parent $evidenceFull
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null

$sandbox = Join-Path $env:RUNNER_TEMP ("cloudos-session-restart-" + [Guid]::NewGuid().ToString('N'))
$localAppData = Join-Path $sandbox 'LocalAppData'
$cloudosState = Join-Path $localAppData 'CloudOS'
New-Item -ItemType Directory -Path $cloudosState -Force | Out-Null
$sessionFile = Join-Path $cloudosState 'desktop_session.json'

$seed = [ordered]@{
    schemaVersion = 3
    timestamp = [DateTime]::UtcNow.ToString('o')
    activeWorkspace = 2
    sequence = 1
    mruWindowIds = @('restart-files')
    windows = @(
        [ordered]@{
            id = 'restart-files'
            appId = 'cloudos:files'
            title = 'Arquivos'
            x = 9000.0
            y = 9000.0
            width = 5000.0
            height = 4000.0
            minimized = $false
            maximized = $false
            focused = $true
            workspaceIndex = 2
            previousX = 9000.0
            previousY = 9000.0
            previousWidth = 5000.0
            previousHeight = 4000.0
            customParams = [ordered]@{ initialPath = 'home' }
        }
    )
}
$seed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sessionFile -Encoding UTF8
$seedHash = (Get-FileHash -LiteralPath $sessionFile -Algorithm SHA256).Hash.ToLowerInvariant()

$oldLocalAppData = $env:LOCALAPPDATA
$oldUserProfile = $env:USERPROFILE
$cycles = @()
try {
    # Child processes inherit this isolated per-run profile. USERPROFILE is not
    # changed because plugins/Windows may rely on the hosted account profile.
    $env:LOCALAPPDATA = $localAppData

    $cycles += Invoke-CloudOSCloseCycle -Executable $exe -WorkingDirectory $release -Cycle 1 -TimeoutSeconds $ExitTimeoutSeconds

    if (-not (Test-Path -LiteralPath $sessionFile -PathType Leaf)) {
        throw 'Session file disappeared after first orderly close.'
    }
    $first = Get-Content -LiteralPath $sessionFile -Raw | ConvertFrom-Json
    if ($first.schemaVersion -ne 3) { throw "Unexpected session schema after first close: $($first.schemaVersion)" }
    if ($first.activeWorkspace -ne 2) { throw "Workspace was not restored/persisted: $($first.activeWorkspace)" }
    if (@($first.windows).Count -ne 1) { throw 'Expected exactly one restored session window.' }
    $firstWindow = @($first.windows)[0]

    # This is the key cross-process assertion: the seeded impossible geometry
    # must have been loaded into WindowManager, clamped by the real desktop
    # layout and persisted during orderly WM_CLOSE. Merely preserving the seed
    # file is not enough to pass.
    if ([double]$firstWindow.x -ge 9000.0 -or [double]$firstWindow.y -ge 9000.0) {
        throw 'First process did not persist the runtime-clamped window position.'
    }
    if ([double]$firstWindow.width -ge 5000.0 -or [double]$firstWindow.height -ge 4000.0) {
        throw 'First process did not persist the runtime-clamped window size.'
    }
    if ($firstWindow.customParams.initialPath -ne 'home') {
        throw 'Session customParams were not preserved across the first process.'
    }

    $firstHash = (Get-FileHash -LiteralPath $sessionFile -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($firstHash -eq $seedHash) {
        throw 'Session file hash did not change after runtime restore + orderly close.'
    }

    $cycles += Invoke-CloudOSCloseCycle -Executable $exe -WorkingDirectory $release -Cycle 2 -TimeoutSeconds $ExitTimeoutSeconds

    $second = Get-Content -LiteralPath $sessionFile -Raw | ConvertFrom-Json
    if ($second.schemaVersion -ne 3) { throw 'Second launch corrupted the session schema.' }
    if ($second.activeWorkspace -ne 2) { throw 'Second launch lost the active workspace.' }
    if (@($second.windows).Count -ne 1) { throw 'Second launch lost the restored window.' }
    $secondWindow = @($second.windows)[0]
    if ($secondWindow.customParams.initialPath -ne 'home') {
        throw 'Second launch lost session customParams.'
    }

    $evidence = [ordered]@{
        schema = 23
        verdict = 'pass'
        test = 'real-windows-exe-session-restart'
        executable = $exe
        executable_sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
        isolated_localappdata = $true
        wm_close_requested = $true
        launches = 2
        seed_sha256 = $seedHash
        final_session_sha256 = (Get-FileHash -LiteralPath $sessionFile -Algorithm SHA256).Hash.ToLowerInvariant()
        schema_version = [int]$second.schemaVersion
        active_workspace = [int]$second.activeWorkspace
        restored_app_id = [string]$secondWindow.appId
        restored_initial_path = [string]$secondWindow.customParams.initialPath
        first_persisted_geometry = [ordered]@{
            x = [double]$firstWindow.x
            y = [double]$firstWindow.y
            width = [double]$firstWindow.width
            height = [double]$firstWindow.height
        }
        cycles = $cycles
    }
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidenceFull -Encoding UTF8
    Get-Content -LiteralPath $evidenceFull
    Write-Host "[PASS] CloudOS V23 real EXE session restart/WM_CLOSE smoke passed. Evidence: $evidenceFull"
}
finally {
    if ($null -eq $oldLocalAppData) { Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue } else { $env:LOCALAPPDATA = $oldLocalAppData }
    if ($null -eq $oldUserProfile) { Remove-Item Env:USERPROFILE -ErrorAction SilentlyContinue } else { $env:USERPROFILE = $oldUserProfile }
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}
