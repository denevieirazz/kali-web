[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$OutputPath = (Join-Path $Root 'desktop\CloudOS.NativeShell\artifacts\unified-start-search-v17-smoke.json')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-CurrentUserShellValue {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows NT\CurrentVersion\Winlogon', $false)
    if ($null -eq $key) { return [pscustomobject]@{ present = $false; kind = $null; value = $null } }
    try {
        $names = @($key.GetValueNames())
        if ($names -notcontains 'Shell') { return [pscustomobject]@{ present = $false; kind = $null; value = $null } }
        return [pscustomobject]@{
            present = $true
            kind = $key.GetValueKind('Shell').ToString()
            value = [string]$key.GetValue('Shell', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
    }
    finally { $key.Dispose() }
}

function Get-WslDistributions {
    param([string]$WslPath)
    if ([string]::IsNullOrWhiteSpace($WslPath)) { return @() }
    try {
        $lines = @(& $WslPath --list --quiet 2>$null)
        if ($LASTEXITCODE -ne 0) { return @() }
        return @($lines | ForEach-Object { ([string]$_).Trim([char]0).Trim() } | Where-Object { $_ } | Select-Object -Unique)
    }
    catch { return @() }
}

$beforeShell = Get-CurrentUserShellValue
$src = Join-Path $Root 'desktop\CloudOS.NativeShell\src'
$startHeaderPath = Join-Path $src 'native_start_index.h'
$startPath = Join-Path $src 'native_start_index.cpp'
$launcherPath = Join-Path $src 'native_integration_v16_launchers.h'
$desktopPath = Join-Path $src 'native_desktop_model_v12.h'
$supervisorPath = Join-Path $Root 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.Supervisor.exe'

foreach ($path in @($startHeaderPath, $startPath, $launcherPath, $desktopPath, $supervisorPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "V17 smoke prerequisite missing: $path" }
}

$startHeader = Get-Content -LiteralPath $startHeaderPath -Raw
$start = Get-Content -LiteralPath $startPath -Raw
$launcher = Get-Content -LiteralPath $launcherPath -Raw
$desktop = Get-Content -LiteralPath $desktopPath -Raw

$linuxStartKind = $startHeader.Contains('LinuxApp') -and $start.Contains('NativeStartIndexKind::LinuxApp')
$linuxCatalogConsumed = $start.Contains('NativeIntegrationV16::EnumerateLinuxGuiApps()') -and
    $start.Contains('ScanLinuxApps(next);')
$sharedLauncherAdapter = $launcher.Contains('NativeIntegrationV16::EnsureLinuxLauncherShortcut') -and
    $start.Contains('NativeIntegrationV16::EnsureLinuxLauncherShortcut(app)') -and
    $desktop.Contains('NativeIntegrationV16::EnsureLinuxLauncherShortcut(app)')
$eventDrivenLinuxRefresh = $desktop.Contains('NativeIntegrationV16::LinuxApplicationsDirectory(distro)') -and
    $desktop.Contains('FindFirstChangeNotificationW') -and
    $desktop.Contains('FindNextChangeNotification') -and
    $desktop.Contains('NativeStartIndex::Instance().RefreshAsync();')
$startHasNoDirectWslCommand = -not $start.Contains('wsl.exe') -and -not $start.Contains('gtk-launch')

$supervisor = Start-Process -FilePath $supervisorPath -ArgumentList '--self-test' -Wait -PassThru -WindowStyle Hidden
$supervisorExit = $supervisor.ExitCode

$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
$distros = Get-WslDistributions -WslPath $(if ($null -ne $wslCommand) { $wslCommand.Source } else { '' })

$afterShell = Get-CurrentUserShellValue
$shellUnchanged = ($beforeShell | ConvertTo-Json -Compress) -eq ($afterShell | ConvertTo-Json -Compress)

$failures = New-Object System.Collections.Generic.List[string]
if (-not $linuxStartKind) { $failures.Add('NativeStartIndex does not model Linux apps.') }
if (-not $linuxCatalogConsumed) { $failures.Add('Start index does not consume the V16 Linux catalog.') }
if (-not $sharedLauncherAdapter) { $failures.Add('Desktop and Start do not share the V16 Linux launcher adapter.') }
if (-not $eventDrivenLinuxRefresh) { $failures.Add('Linux application changes are not wired to event-driven Desktop/Start refresh.') }
if (-not $startHasNoDirectWslCommand) { $failures.Add('Start duplicated direct WSL command construction outside NativeIntegrationV16.') }
if ($supervisorExit -ne 0) { $failures.Add("Supervisor V11 self-test failed with exit code $supervisorExit.") }
if (-not $shellUnchanged) { $failures.Add('Production HKCU Winlogon Shell changed during non-mutating V17 smoke.') }

$report = [ordered]@{
    schema = 17
    test = 'CloudOS Unified Start Search V17'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    verdict = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    scope = 'Non-mutating hosted source/compiled-release smoke for unified Windows+Linux Start/Search integration and Supervisor runtime sanity.'
    evidence = [ordered]@{
        linux_start_kind = $linuxStartKind
        linux_catalog_consumed = $linuxCatalogConsumed
        shared_launcher_adapter = $sharedLauncherAdapter
        event_driven_linux_refresh = $eventDrivenLinuxRefresh
        start_has_no_direct_wsl_command = $startHasNoDirectWslCommand
        supervisor_self_test_exit_code = $supervisorExit
        wsl_available = $null -ne $wslCommand
        wsl_distribution_count = @($distros).Count
        wsl_distributions = @($distros)
        production_winlogon_unchanged = $shellUnchanged
        mutating_package_operation_executed = $false
    }
    limitations = @(
        'No package was installed, upgraded or removed.',
        'A hosted runner with zero WSL distributions cannot prove a real Linux GUI entry appears in Start or launches through WSLg.',
        'Adding a brand-new WSL distribution after the Desktop watcher starts may require manual reindex or shell restart before its application directory becomes watched.',
        'No UAC, sudo, logoff, reboot or production Winlogon mutation is exercised.'
    )
    failures = @($failures)
}

$directory = Split-Path -Parent $OutputPath
if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8

if ($report.verdict -ne 'pass') {
    throw "Unified Start/Search V17 smoke failed: $($failures -join ' | ')"
}
Write-Host "PASS: Unified Start/Search V17 non-mutating smoke -> $OutputPath"
