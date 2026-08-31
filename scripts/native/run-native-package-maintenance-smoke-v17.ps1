[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$OutputPath = (Join-Path $Root 'desktop\CloudOS.NativeShell\artifacts\package-maintenance-v17-smoke.json')
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
$maintenancePath = Join-Path $Root 'desktop\CloudOS.NativeShell\src\native_package_maintenance_v17.h'
$appsPath = Join-Path $Root 'desktop\CloudOS.NativeShell\src\native_apps_window.cpp'
$binaryPath = Join-Path $Root 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.exe'
foreach ($path in @($maintenancePath, $appsPath, $binaryPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "V17 smoke prerequisite missing: $path" }
}

$maintenance = Get-Content -LiteralPath $maintenancePath -Raw
$apps = Get-Content -LiteralPath $appsPath -Raw
$wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
$distros = Get-WslDistributions -WslPath $(if ($null -ne $wslCommand) { $wslCommand.Source } else { '' })

$windowsUpgradeBuilder = $maintenance.Contains('BuildWindowsUpgradeCommand') -and
    $maintenance.Contains(' upgrade --name ') -and
    $maintenance.Contains('--exact --accept-package-agreements --accept-source-agreements')
$linuxUpgradeBuilders = $maintenance.Contains('BuildLinuxUpgradeCommand') -and
    $maintenance.Contains('flatpak update ') -and
    $maintenance.Contains('sudo snap refresh ') -and
    $maintenance.Contains('sudo apt install --only-upgrade -- ')
$safeAptResolution = $maintenance.Contains('dpkg-query -S --') -and
    $maintenance.Contains('SafeLinuxToken') -and
    $maintenance.Contains('test -n \\"$p\\"')
$appsUpdateAction = $apps.Contains('L"Atualizar app"') -and
    $apps.Contains('void CloudOSNativeAppsWindow::UpdateSelection()') -and
    $apps.Contains('NativePackageMaintenanceV17::CanUpgrade') -and
    $apps.Contains('MB_YESNO') -and
    $apps.Contains('CloudOSNativeTerminalWindow::Open')

$afterShell = Get-CurrentUserShellValue
$shellUnchanged = ($beforeShell | ConvertTo-Json -Compress) -eq ($afterShell | ConvertTo-Json -Compress)

$failures = New-Object System.Collections.Generic.List[string]
if (-not $windowsUpgradeBuilder) { $failures.Add('Windows WinGet upgrade builder is incomplete.') }
if (-not $linuxUpgradeBuilders) { $failures.Add('Linux apt/Snap/Flatpak upgrade builders are incomplete.') }
if (-not $safeAptResolution) { $failures.Add('Safe apt package ownership resolution is incomplete.') }
if (-not $appsUpdateAction) { $failures.Add('Apps V17 explicit update action is incomplete.') }
if (-not $shellUnchanged) { $failures.Add('Production HKCU Winlogon Shell changed during non-mutating V17 smoke.') }

$report = [ordered]@{
    schema = 17
    test = 'CloudOS Package Maintenance V17'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    verdict = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    scope = 'Non-mutating hosted compiled-graph/capability smoke for explicit Windows and Linux package upgrade flows.'
    evidence = [ordered]@{
        native_binary_present = $true
        windows_upgrade_builder = $windowsUpgradeBuilder
        linux_upgrade_builders = $linuxUpgradeBuilders
        safe_apt_package_resolution = $safeAptResolution
        apps_explicit_update_action = $appsUpdateAction
        winget_available = $null -ne $wingetCommand
        wsl_available = $null -ne $wslCommand
        wsl_distribution_count = @($distros).Count
        wsl_distributions = @($distros)
        production_winlogon_unchanged = $shellUnchanged
        mutating_package_operation_executed = $false
    }
    limitations = @(
        'No package upgrade was executed.',
        'Hosted CI does not approve UAC or sudo prompts.',
        'A real apt/Snap/Flatpak/WinGet upgrade remains a manual VM or pilot test.',
        'A hosted runner without a WSL distro does not prove Linux package manager execution.'
    )
    failures = @($failures)
}

$directory = Split-Path -Parent $OutputPath
if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8

if ($report.verdict -ne 'pass') {
    throw "Package Maintenance V17 smoke failed: $($failures -join ' | ')"
}
Write-Host "PASS: Package Maintenance V17 non-mutating smoke -> $OutputPath"
