[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source

# Keep this list as the single ordered inventory of structural/native contracts.
# Runtime smokes remain in the Full-System workflow because they need built binaries.
$contracts = @(
    'test-performance-visual-v12-contract.ps1',
    'test-cloudos-native-shell-contracts.ps1',
    'test-shell-lifecycle-contract.ps1',
    'test-native-web-ui-contract.ps1',
    'test-browser-resilience-v22-contract.ps1',
    'test-visual-platform-v7-contract.ps1',
    'test-stability-readiness-v9-contract.ps1',
    'test-lifecycle-v10-contract.ps1',
    'test-shell-supervisor-v11-contract.ps1',
    'test-supervisor-recovery-v22-contract.ps1',
    'test-external-app-breakaway-v22-contract.ps1',
    'test-windows-shutdown-v22-contract.ps1',
    'test-taskbar-productivity-contract.ps1',
    'test-workspace-overview-contract.ps1',
    'test-workspace-studio-contract.ps1',
    'test-session-continuity-contract.ps1',
    'test-shell-control-plane-contract.ps1',
    'test-files-storage-v5-contract.ps1',
    'test-files-shell-operations-v22-contract.ps1',
    'test-archive-extraction-v22-contract.ps1',
    'test-window-rehome-v22-contract.ps1',
    'test-env-doctor-v22-contract.ps1',
    'test-quick-settings-system-v22-contract.ps1',
    'test-native-release-pipeline-contract.ps1',
    'test-health-gate-v22-contract.ps1',
    'test-transactional-install-v22-contract.ps1',
    'test-transactional-update-v22-contract.ps1',
    'test-runtime-repair-v22-contract.ps1',
    'test-transactional-deployment-v13-contract.ps1',
    'test-shell-activation-v14-contract.ps1',
    'test-repository-clarity-v15-contract.ps1',
    'test-unified-integration-v16-contract.ps1',
    'test-unified-start-search-v17-contract.ps1',
    'test-system-broker-v21-contract.ps1',
    'test-system-broker-security-v22-contract.ps1',
    'test-system-broker-wsl-inventory-v22-contract.ps1',
    'test-system-broker-wsl-probe-v22-contract.ps1',
    'test-v21-integrated-runtime-contract.ps1',
    'test-shell-notification-bridge-v21-contract.ps1',
    'test-crash-diagnostics-v22-contract.ps1'
)

$duplicates = @($contracts | Group-Object | Where-Object Count -gt 1)
if ($duplicates.Count -ne 0) {
    throw "Native contract suite contains duplicate entries: $($duplicates.Name -join ', ')"
}

$started = [DateTime]::UtcNow
$completed = New-Object System.Collections.Generic.List[string]

foreach ($name in $contracts) {
    $path = Join-Path $scriptRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Native contract listed by suite is missing: $path"
    }

    Write-Host "[CloudOS contracts] RUN  $name"
    & $pwsh -NoLogo -NoProfile -File $path
    if ($LASTEXITCODE -ne 0) {
        throw "Native contract failed with exit code ${LASTEXITCODE}: $name"
    }

    $completed.Add($name)
    Write-Host "[CloudOS contracts] PASS $name"
}

$elapsed = [DateTime]::UtcNow - $started
Write-Host "PASS: CloudOS native contract suite ($($completed.Count) contracts, $([Math]::Round($elapsed.TotalSeconds, 2))s)."
