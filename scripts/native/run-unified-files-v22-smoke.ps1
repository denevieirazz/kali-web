# run-unified-files-v22-smoke.ps1
# End-to-end smoke verification for CloudOS V22 Unified Files

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$brokerBin = Join-Path $repoRoot "desktop\CloudOS.NativeShell\bin\Release\CloudOS.SystemBroker.exe"
$probeBin = Join-Path $repoRoot "desktop\CloudOS.NativeShell\bin\Release\CloudOS.BrokerProbe.exe"

if (-not (Test-Path $brokerBin)) {
    throw "CloudOS.SystemBroker.exe not found at $brokerBin. Run build-cloudos-native.cmd first."
}

if (-not (Test-Path $probeBin)) {
    throw "CloudOS.BrokerProbe.exe not found at $probeBin. Run build-cloudos-native.cmd first."
}

Write-Host "`n[SMOKE-V22] 1. Executing System Broker Self-Test Suite..." -ForegroundColor Cyan
& $brokerBin --self-test
if ($LASTEXITCODE -ne 0) {
    throw "SystemBroker --self-test failed with exit code $LASTEXITCODE"
}
Write-Host "[SMOKE-V22] System Broker Self-Test: PASS" -ForegroundColor Green

Write-Host "`n[SMOKE-V22] 2. Spawning System Broker for Live Probing..." -ForegroundColor Cyan
$brokerProc = Start-Process -FilePath $brokerBin -PassThru

try {
    Start-Sleep -Milliseconds 800

    Write-Host "[SMOKE-V22] Probing Known Folders..." -ForegroundColor Yellow
    & $probeBin known-folders
    if ($LASTEXITCODE -ne 0) { throw "Probe known-folders failed" }

    Write-Host "[SMOKE-V22] Probing Logical Drives..." -ForegroundColor Yellow
    & $probeBin drives
    if ($LASTEXITCODE -ne 0) { throw "Probe drives failed" }

    Write-Host "[SMOKE-V22] Probing Directory Listing (Home)..." -ForegroundColor Yellow
    & $probeBin list home
    if ($LASTEXITCODE -ne 0) { throw "Probe list home failed" }

    Write-Host "[SMOKE-V22] Probing File Metadata..." -ForegroundColor Yellow
    & $probeBin metadata "$repoRoot\README.md"
    if ($LASTEXITCODE -ne 0) { throw "Probe metadata failed" }

    Write-Host "[SMOKE-V22] Probing Open With Associations..." -ForegroundColor Yellow
    & $probeBin open-with "$repoRoot\README.md"
    if ($LASTEXITCODE -ne 0) { throw "Probe open-with failed" }

    Write-Host "`n[SMOKE-V22] ALL V22 Live File Probes Passed Successfully!" -ForegroundColor Green
}
finally {
    if ($brokerProc -and -not $brokerProc.HasExited) {
        Stop-Process -Id $brokerProc.Id -Force -ErrorAction SilentlyContinue
    }
}
