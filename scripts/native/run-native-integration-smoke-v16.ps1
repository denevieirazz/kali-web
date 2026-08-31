[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$OutputPath = (Join-Path $Root 'desktop\CloudOS.NativeShell\artifacts\integration-v16-smoke.json')
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
$desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
$documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
$userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
$downloads = if ($userProfile) { Join-Path $userProfile 'Downloads' } else { $null }
$publicDesktop = Join-Path $env:PUBLIC 'Desktop'

$wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
$distros = Get-WslDistributions -WslPath $(if ($null -ne $wslCommand) { $wslCommand.Source } else { '' })

$projectPath = Join-Path $Root 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
$browserPath = Join-Path $Root 'desktop\CloudOS.NativeShell\src\native_browser_window.cpp'
$integrationPath = Join-Path $Root 'desktop\CloudOS.NativeShell\src\native_integration_v16.cpp'
$pickerPath = Join-Path $Root 'desktop\CloudOS.NativeShell\src\native_folder_picker_v16.cpp'
foreach ($path in @($projectPath, $browserPath, $integrationPath, $pickerPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "V16 smoke prerequisite missing: $path" }
}

$project = Get-Content -LiteralPath $projectPath -Raw
$browser = Get-Content -LiteralPath $browserPath -Raw
$integration = Get-Content -LiteralPath $integrationPath -Raw

$graphOk = $project.Contains('src\native_integration_v16.cpp') -and
    $project.Contains('src\native_folder_picker_v16.cpp')
$downloadHookOk = $browser.Contains('add_DownloadStarting') -and
    $browser.Contains('put_ResultFilePath') -and
    $browser.Contains('CloudOSNativeFolderPickerV16::Pick')
$packageBoundaryOk = $integration.Contains('winget.exe') -and
    $integration.Contains('gtk-launch') -and
    $integration.Contains('dpkg-query -S')

$afterShell = Get-CurrentUserShellValue
$shellUnchanged = ($beforeShell | ConvertTo-Json -Compress) -eq ($afterShell | ConvertTo-Json -Compress)
$foldersOk = -not [string]::IsNullOrWhiteSpace($desktop) -and
    -not [string]::IsNullOrWhiteSpace($documents) -and
    -not [string]::IsNullOrWhiteSpace($userProfile)

$failures = New-Object System.Collections.Generic.List[string]
if (-not $graphOk) { $failures.Add('V16 compile graph is incomplete.') }
if (-not $downloadHookOk) { $failures.Add('Browser V16 download hook is incomplete.') }
if (-not $packageBoundaryOk) { $failures.Add('Unified package boundary is incomplete.') }
if (-not $foldersOk) { $failures.Add('Required current-user known folders did not resolve.') }
if (-not $shellUnchanged) { $failures.Add('Production HKCU Winlogon Shell changed during non-mutating V16 smoke.') }

$report = [ordered]@{
    schema = 16
    test = 'CloudOS Unified Windows Linux Integration V16'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    verdict = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    scope = 'Non-mutating hosted capability/compiled-graph smoke. Does not install/uninstall packages and does not claim a real WSLg GUI launch.'
    evidence = [ordered]@{
        native_compile_graph = $graphOk
        browser_download_hook = $downloadHookOk
        unified_package_boundary = $packageBoundaryOk
        known_folders_resolved = $foldersOk
        desktop = $desktop
        documents = $documents
        downloads = $downloads
        public_desktop = $publicDesktop
        winget_available = $null -ne $wingetCommand
        wsl_available = $null -ne $wslCommand
        wsl_distribution_count = @($distros).Count
        wsl_distributions = @($distros)
        production_winlogon_unchanged = $shellUnchanged
        mutating_package_operation_executed = $false
    }
    limitations = @(
        'No package was installed, upgraded or removed.',
        'WSLg GUI launch is not required on the hosted runner.',
        'No UAC, sudo, logoff, reboot or default-app association flow is exercised.'
    )
    failures = @($failures)
}

$directory = Split-Path -Parent $OutputPath
if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8

if ($report.verdict -ne 'pass') {
    throw "Unified Integration V16 smoke failed: $($failures -join ' | ')"
}
Write-Host "PASS: Unified Integration V16 non-mutating smoke -> $OutputPath"
