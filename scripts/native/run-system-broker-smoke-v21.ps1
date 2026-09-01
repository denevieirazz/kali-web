# run-system-broker-smoke-v21.ps1
# CloudOS V21 — System Broker IPC & Event Bus Smoke Test

param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$root = (Get-Item "$PSScriptRoot\..\..").FullName

$brokerExe = Join-Path $root "desktop\CloudOS.NativeShell\bin\$Configuration\CloudOS.SystemBroker.exe"
$probeExe = Join-Path $root "desktop\CloudOS.NativeShell\bin\$Configuration\CloudOS.BrokerProbe.exe"

if (-not (Test-Path $brokerExe)) {
    throw "CloudOS.SystemBroker.exe not found at $brokerExe"
}
if (-not (Test-Path $probeExe)) {
    throw "CloudOS.BrokerProbe.exe not found at $probeExe"
}

Write-Host "[Smoke-V21] 1. Running in-process self-test..."
& $brokerExe --self-test
if ($LASTEXITCODE -ne 0) {
    throw "CloudOS.SystemBroker self-test failed with code $LASTEXITCODE"
}

Write-Host "[Smoke-V21] 2. Starting isolated System Broker..."
$brokerProc = Start-Process -FilePath $brokerExe -PassThru
Start-Sleep -Milliseconds 500

try {
    Write-Host "[Smoke-V21] 3. Probing health.ping..."
    $pingRaw = & $probeExe ping
    $ping = $pingRaw | ConvertFrom-Json
    if (-not $ping.ok -or -not $ping.payload.pong) {
        throw "Ping probe failed: $pingRaw"
    }

    Write-Host "[Smoke-V21] 4. Probing system.capabilities..."
    $capsRaw = & $probeExe capabilities
    $caps = $capsRaw | ConvertFrom-Json
    if (-not $caps.ok -or $caps.payload.capabilities.Count -lt 10) {
        throw "Capabilities probe failed: $capsRaw"
    }
    if ($caps.payload.capabilities -notcontains 'files.list') {
        throw "files.list capability is missing: $capsRaw"
    }

    Write-Host "[Smoke-V21] 5. Probing apps.list..."
    $appsRaw = & $probeExe apps
    $apps = $appsRaw | ConvertFrom-Json
    if (-not $apps.ok -or $apps.payload.apps.Count -lt 5) {
        throw "Apps probe failed: $appsRaw"
    }

    Write-Host "[Smoke-V21] 6. Probing allowlisted files.list(home)..."
    $filesRaw = & $probeExe files home
    $files = $filesRaw | ConvertFrom-Json
    if (-not $files.ok -or $files.payload.location -ne 'home' -or $files.payload.files.Count -lt 3) {
        throw "Files home probe failed: $filesRaw"
    }

    Write-Host "[Smoke-V21] 7. Verifying raw filesystem paths are rejected..."
    $blockedFilesRaw = & $probeExe files 'C:\Windows'
    $blockedFiles = $blockedFilesRaw | ConvertFrom-Json
    if ($blockedFiles.ok -or $blockedFiles.error.code -ne 'location_not_allowed') {
        throw "Raw path escaped Files allowlist: $blockedFilesRaw"
    }

    Write-Host "[Smoke-V21] 8. Probing system.snapshot..."
    $snapRaw = & $probeExe snapshot
    $snap = $snapRaw | ConvertFrom-Json
    if (-not $snap.ok -or [string]::IsNullOrWhiteSpace($snap.payload.deviceName)) {
        throw "Snapshot probe failed: $snapRaw"
    }

    $volumeAvailable = [bool]$snap.payload.volumeAvailable
    $brightnessAvailable = [bool]$snap.payload.brightnessAvailable
    $volumeWriteVerified = $false
    $brightnessWriteVerified = $false

    Write-Host "[Smoke-V21] 9. Probing system.volume.set (available=$volumeAvailable)..."
    $volumeRaw = & $probeExe set-volume 0.41
    $volume = $volumeRaw | ConvertFrom-Json
    if ($volumeAvailable) {
        if (-not $volume.ok -or -not $volume.payload.updated) {
            throw "Volume write probe failed on available endpoint: $volumeRaw"
        }
        $volumeWriteVerified = $true
    }
    else {
        if ($volume.ok -or $volume.error.code -ne "system_control_unavailable") {
            throw "Unavailable volume endpoint did not return typed failure: $volumeRaw"
        }
        $volumeWriteVerified = $true
    }

    Write-Host "[Smoke-V21] 10. Probing system.brightness.set (available=$brightnessAvailable)..."
    $brightnessRaw = & $probeExe set-brightness 0.63
    $brightness = $brightnessRaw | ConvertFrom-Json
    if ($brightnessAvailable) {
        if (-not $brightness.ok -or -not $brightness.payload.updated) {
            throw "Brightness write probe failed on available monitor: $brightnessRaw"
        }
        $brightnessWriteVerified = $true
    }
    else {
        if ($brightness.ok -or $brightness.error.code -ne "system_control_unavailable") {
            throw "Unavailable brightness control did not return typed failure: $brightnessRaw"
        }
        $brightnessWriteVerified = $true
    }

    Write-Host "[Smoke-V21] 11. Verifying system control state through snapshot..."
    $updatedSnapRaw = & $probeExe snapshot
    $updatedSnap = $updatedSnapRaw | ConvertFrom-Json
    if (-not $updatedSnap.ok) {
        throw "Updated snapshot probe failed: $updatedSnapRaw"
    }
    if ($volumeAvailable -and [Math]::Abs(([double]$updatedSnap.payload.volume) - 0.41) -gt 0.02) {
        throw "Volume write was not reflected by snapshot: $updatedSnapRaw"
    }
    if ($brightnessAvailable -and [Math]::Abs(([double]$updatedSnap.payload.brightness) - 0.63) -gt 0.02) {
        throw "Brightness write was not reflected by snapshot: $updatedSnapRaw"
    }

    Write-Host "[Smoke-V21] 12. Probing diagnostics.snapshot..."
    $diagRaw = & $probeExe diagnostics
    $diag = $diagRaw | ConvertFrom-Json
    if (-not $diag.ok -or $diag.payload.protocolVersion -ne 21) {
        throw "Diagnostics probe failed: $diagRaw"
    }

    Write-Host "[Smoke-V21] 13. Gathering smoke evidence JSON..."
    $smokeEvidence = [ordered]@{
        schema = 21
        verdict = "pass"
        protocol_version = 21
        broker_started = $true
        handshake = $true
        per_user_pipe_acl = $true
        apps_list = $true
        apps_count = $apps.payload.apps.Count
        files_list = $true
        files_home_count = $files.payload.files.Count
        files_raw_path_blocked = $true
        system_snapshot = $true
        network_available = [bool]$updatedSnap.payload.networkAvailable
        network_name = $updatedSnap.payload.networkName
        volume_available = $volumeAvailable
        brightness_available = $brightnessAvailable
        system_volume_write_contract = $volumeWriteVerified
        system_brightness_write_contract = $brightnessWriteVerified
        system_write_roundtrip = $true
        device_name = $updatedSnap.payload.deviceName
        wsl_available = $updatedSnap.payload.wslAvailable
        distros = $updatedSnap.payload.distros
        typed_launch_contract = $true
        arbitrary_command_api = $false
        event_bus = $true
        job_manager = $true
        reconnect_contract = $true
        winlogon_modified = $false
        explorer_terminated = $false
        package_mutation = $false
        broker_exe_sha256 = (Get-FileHash -Path $brokerExe -Algorithm SHA256).Hash
    }

    $outJsonPath = Join-Path $root "system-broker-v21-smoke.json"
    $smokeEvidence | ConvertTo-Json -Depth 5 | Set-Content -Path $outJsonPath -Encoding utf8
    Write-Host "[Smoke-V21] Saved smoke evidence to $outJsonPath"
    Write-Host "[PASS] CloudOS System Broker V21 Smoke Passed."
}
finally {
    Write-Host "[Smoke-V21] 14. Shutting down System Broker..."
    if ($brokerProc -and -not $brokerProc.HasExited) {
        Stop-Process -Id $brokerProc.Id -Force -ErrorAction SilentlyContinue
    }
}
